import Darwin
import CoreFoundation
import Foundation

struct CodexUsageWindow: Equatable, Sendable {
    let usedPercent: Int
    let resetsAt: Date
}

struct CodexUsageSnapshot: Equatable, Sendable {
    let fiveHour: CodexUsageWindow
    let weekly: CodexUsageWindow
}

// Optional local metadata reads: thread titles and authenticated rate-limit snapshots.
// Lifecycle hooks remain the source of activity and session discovery.
actor CodexThreadMetadataReader {
    private struct CachedTitle {
        let value: String?
        let expiresAt: Date
    }

    private struct CachedUsage {
        let value: CodexUsageSnapshot?
        let expiresAt: Date
    }

    private let binaryCandidates: [URL]
    private let timeoutMilliseconds: Int32
    private var cached: [String: CachedTitle] = [:]
    private var pending: [String: Task<String?, Never>] = [:]
    private var cachedUsage: [String: CachedUsage] = [:]
    private var pendingUsage: [String: Task<CodexUsageSnapshot?, Never>] = [:]

    init(codexAppURL: URL?, timeoutMilliseconds: Int32 = 2_500) {
        var candidates: [URL] = []
        if let codexAppURL {
            candidates.append(codexAppURL.appendingPathComponent(
                "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".local/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        self.binaryCandidates = candidates
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    init(binaryCandidates: [URL], timeoutMilliseconds: Int32 = 2_500) {
        self.binaryCandidates = binaryCandidates
        self.timeoutMilliseconds = timeoutMilliseconds
    }

    func title(for sessionID: String, codexHomes: [URL], forceRefresh: Bool = false) async -> String? {
        guard !sessionID.isEmpty, sessionID.utf8.count <= 256,
              !sessionID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        let homes = Array(Set(codexHomes.map(\.standardizedFileURL))).sorted { $0.path < $1.path }
        let key = ([sessionID] + homes.map(\.path)).joined(separator: "\u{0}")
        if !forceRefresh, let cached = cached[key], cached.expiresAt > Date() { return cached.value }
        if let pending = pending[key] { return await pending.value }

        let binaries = binaryCandidates
        let timeout = timeoutMilliseconds
        let task = Task.detached(priority: .utility) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.lookup(sessionID: sessionID, homes: homes,
                                                               binaries: binaries, timeout: timeout))
                }
            }
        }
        pending[key] = task
        let value = await task.value
        pending.removeValue(forKey: key)
        cached[key] = CachedTitle(value: value, expiresAt: Date().addingTimeInterval(value == nil ? 3 : 45))
        cached = cached.filter { $0.value.expiresAt > Date() }
        while cached.count > 64, let oldest = cached.min(by: { $0.value.expiresAt < $1.value.expiresAt }) {
            cached.removeValue(forKey: oldest.key)
        }
        return value
    }

    func usage(for codexHome: URL, forceRefresh: Bool = false) async -> CodexUsageSnapshot? {
        let home = codexHome.standardizedFileURL
        let key = home.path
        if !forceRefresh, let cached = cachedUsage[key], cached.expiresAt > Date() { return cached.value }
        if let pending = pendingUsage[key] { return await pending.value }

        let binaries = binaryCandidates
        let timeout = timeoutMilliseconds
        let task = Task.detached(priority: .utility) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.lookupUsage(home: home, binaries: binaries, timeout: timeout))
                }
            }
        }
        pendingUsage[key] = task
        let value = await task.value
        pendingUsage.removeValue(forKey: key)
        cachedUsage[key] = CachedUsage(value: value, expiresAt: Date().addingTimeInterval(value == nil ? 30 : 120))
        cachedUsage = cachedUsage.filter { $0.value.expiresAt > Date() }
        while cachedUsage.count > 8, let oldest = cachedUsage.min(by: { $0.value.expiresAt < $1.value.expiresAt }) {
            cachedUsage.removeValue(forKey: oldest.key)
        }
        return value
    }

    private static func lookup(sessionID: String, homes: [URL], binaries: [URL], timeout: Int32) -> String? {
        for binary in binaries where FileManager.default.isExecutableFile(atPath: binary.path) {
            for home in homes {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: home.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                if let title = readTitle(sessionID: sessionID, binary: binary, home: home, timeout: timeout) {
                    return title
                }
            }
        }
        return nil
    }

    private static func readTitle(sessionID: String, binary: URL, home: URL, timeout: Int32) -> String? {
        guard let reply = readRequest(method: "thread/read",
                                      params: ["threadId": sessionID, "includeTurns": false],
                                      binary: binary, home: home, timeout: timeout) else { return nil }
        return title(in: reply, expectedSessionID: sessionID)
    }

    private static func lookupUsage(home: URL, binaries: [URL], timeout: Int32) -> CodexUsageSnapshot? {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(timeout, 1)) * 1_000_000
        for binary in binaries where FileManager.default.isExecutableFile(atPath: binary.path) {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: home.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            let remainingMilliseconds = Int32(max(1, (deadline - now) / 1_000_000))
            guard let reply = readRequest(method: "account/rateLimits/read", params: nil,
                                          binary: binary, home: home, timeout: remainingMilliseconds) else { continue }
            return usageSnapshot(in: reply, now: Date())
        }
        return nil
    }

    private static func readRequest(method: String, params: [String: Any]?, binary: URL,
                                    home: URL, timeout: Int32) -> [String: Any]? {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            try? input.fileHandleForWriting.close()
            // This is an ephemeral metadata subprocess. Force a bounded exit even if
            // an app-server ignores SIGTERM after an invalid or timed-out reply.
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }

        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(timeout, 1)) * 1_000_000
        var buffer = Data()
        var request: [String: Any] = ["method": method, "id": 2]
        if let params { request["params"] = params }
        guard send(["method": "initialize", "id": 1,
                    "params": ["clientInfo": ["name": "nudge_metadata_reader", "title": "Nudge", "version": "0.1.0"]]], to: input),
              let initialized = response(id: 1, from: output, buffer: &buffer, deadline: deadline),
              initialized["result"] != nil,
              send(["method": "initialized", "params": [:]], to: input),
              send(request, to: input) else { return nil }
        return response(id: 2, from: output, buffer: &buffer, deadline: deadline)
    }

    private static func send(_ object: [String: Any], to pipe: Pipe) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]) else {
            return false
        }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data + Data([0x0A]))
            return true
        } catch { return false }
    }

    private static func response(id: Int, from pipe: Pipe, buffer: inout Data,
                                 deadline: UInt64) -> [String: Any]? {
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        while true {
            if let lineEnd = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: lineEnd)
                buffer.removeSubrange(...lineEnd)
                if let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                   (object["id"] as? Int) == id { return object }
                continue
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { return nil }
            let remaining = deadline - now
            var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptorState, 1, Int32(max(1, remaining / 1_000_000)))
            guard ready > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            guard count > 0 else { return nil }
            buffer.append(contentsOf: bytes.prefix(count))
            guard buffer.count <= 128 * 1_024 else { return nil }
        }
        return nil
    }

    static func title(in response: [String: Any], expectedSessionID: String) -> String? {
        guard let result = response["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any],
              thread["id"] as? String == expectedSessionID,
              let rawTitle = thread["name"] as? String, rawTitle.utf8.count <= 4_096 else { return nil }
        let normalized = rawTitle.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : String($0)
        }.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(120))
    }

    static func usageSnapshot(in response: [String: Any], now: Date = Date()) -> CodexUsageSnapshot? {
        guard let result = response["result"] as? [String: Any] else { return nil }
        let buckets = result["rateLimitsByLimitId"] as? [String: Any]
        let bucket: [String: Any]?
        if let codexBucket = buckets?["codex"] as? [String: Any] {
            bucket = codexBucket
        } else if let legacy = result["rateLimits"] as? [String: Any],
                  legacy["limitId"] as? String == "codex" {
            bucket = legacy
        } else {
            bucket = nil
        }
        guard let bucket else { return nil }

        var fiveHour: CodexUsageWindow?
        var weekly: CodexUsageWindow?
        for field in ["primary", "secondary"] {
            guard let window = bucket[field] as? [String: Any],
                  let duration = number(window["windowDurationMins"]),
                  let percentage = number(window["usedPercent"]),
                  percentage >= 0, percentage <= 100,
                  let timestamp = decimal(window["resetsAt"]), timestamp.isFinite,
                  Date(timeIntervalSince1970: timestamp) > now else { continue }
            let usageWindow = CodexUsageWindow(usedPercent: Int(percentage.rounded()),
                                               resetsAt: Date(timeIntervalSince1970: timestamp))
            switch duration {
            case 300: fiveHour = usageWindow
            case 10_080: weekly = usageWindow
            default: continue
            }
        }
        guard let fiveHour, let weekly else { return nil }
        return CodexUsageSnapshot(fiveHour: fiveHour, weekly: weekly)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let result = value.doubleValue
        return result.isFinite ? result : nil
    }

    private static func decimal(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }
}
