import CryptoKit
import Darwin
import Foundation

enum HookInstallResult: Equatable, Sendable {
    case installed(backupPath: String?)
    case removed
    case alreadyInstalled
    case notInstalled
    case malformedExistingConfig
    case unsupportedConfiguration(String)
    case permissionDenied
    case conflict
    case failed(String)
}

struct CodexHookInstaller {
    let target: CodexConfigurationTarget
    let helperPath: URL
    var backupDirectory: URL? = nil
    var permissionActionsEnabled = false

    private var command: String {
        "\(Self.shellQuote(helperPath.path)) --event"
    }

    func install() -> HookInstallResult {
        mutate(installing: true)
    }

    func uninstall() -> HookInstallResult {
        mutate(installing: false)
    }

    private func mutate(installing: Bool) -> HookInstallResult {
        if let issue = target.resolutionIssue { return .unsupportedConfiguration(issue) }
        let configURL = target.hooksFile
        do {
            var targetInfo = stat()
            if lstat(target.codexHome.path, &targetInfo) != 0 {
                guard errno == ENOENT else { return .permissionDenied }
                guard installing else { return .notInstalled }
                try Self.ensureDirectory(target.codexHome, mode: 0o700)
            } else if (targetInfo.st_mode & S_IFMT) != S_IFDIR || targetInfo.st_uid != getuid() {
                return .permissionDenied
            }
            let lock = try Self.lockFile(configURL.appendingPathExtension("nudge.lock"))
            defer { flock(lock, LOCK_UN); Darwin.close(lock) }

            let original = try Self.readRegularFileIfPresent(configURL)
            if let original {
                do {
                    if try StrictJSONValidator.hasDuplicateObjectKeys(original) { return .malformedExistingConfig }
                } catch {
                    return .malformedExistingConfig
                }
            }
            var root: [String: Any]
            if let original {
                guard let parsed = try JSONSerialization.jsonObject(with: original) as? [String: Any] else {
                    return .malformedExistingConfig
                }
                root = parsed
            } else {
                root = [:]
            }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            if root["hooks"] != nil, !(root["hooks"] is [String: Any]) {
                return .unsupportedConfiguration("The hooks root has an unsupported shape.")
            }

            var changed = false
            for event in CodexHookEvent.allCases {
                let key = event.rawValue
                guard let groups = hooks[key] as? [[String: Any]] ?? (hooks[key] == nil ? [] : nil) else {
                    return .unsupportedConfiguration("The \(key) hook group has an unsupported shape.")
                }
                let expectedHandler = Self.handler(command: command, event: event,
                                                   permissionActionsEnabled: permissionActionsEnabled)
                var foundCanonicalOwned = false
                var rewritten: [[String: Any]] = []
                for var group in groups {
                    guard var handlers = group["hooks"] as? [[String: Any]] else {
                        return .unsupportedConfiguration("A \(key) matcher group has an unsupported handler list.")
                    }
                    let matching = handlers.indices.filter { Self.isOwned(handlers[$0], command: command) }
                    let canonicalOwnedGroup = Set(group.keys) == ["hooks"] && handlers.count == 1 && matching.count == 1
                        && NSDictionary(dictionary: handlers[matching[0]]).isEqual(to: expectedHandler)
                    if installing && canonicalOwnedGroup {
                        if foundCanonicalOwned {
                            changed = true
                            continue
                        }
                        foundCanonicalOwned = true
                        rewritten.append(group)
                        continue
                    }
                    var removedOwnedFromGroup = false
                    if !matching.isEmpty {
                        for index in matching.reversed() {
                            handlers.remove(at: index)
                            removedOwnedFromGroup = true
                        }
                        changed = true
                        group["hooks"] = handlers
                    }
                    if handlers.isEmpty, removedOwnedFromGroup, Set(group.keys) == ["hooks"] {
                        continue
                    }
                    rewritten.append(group)
                }
                if installing && !foundCanonicalOwned {
                    rewritten.append(["hooks": [Self.handler(command: command, event: event,
                                                               permissionActionsEnabled: permissionActionsEnabled)]])
                    changed = true
                }
                if !rewritten.isEmpty || hooks[key] != nil { hooks[key] = rewritten }
            }

            guard changed else { return installing ? .alreadyInstalled : .notInstalled }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
            let updated: Data
            do { updated = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8) }
            catch { return .failed("Could not serialize Codex hooks.") }

            let backupPath: String?
            if let original {
                do { backupPath = try Self.createBackup(original, for: target, directory: backupDirectory) }
                catch { return .failed("Could not create a protected configuration backup; the original was not changed.") }
            } else {
                backupPath = nil
            }

            do {
                try Self.compareAndReplace(updated, at: configURL, expected: original)
                return installing ? .installed(backupPath: backupPath) : .removed
            } catch FileMutationError.permissionDenied {
                return .permissionDenied
            } catch FileMutationError.conflict {
                return .conflict
            } catch {
                return .failed("Could not safely replace Codex hooks.")
            }
        } catch FileMutationError.permissionDenied {
            return .permissionDenied
        } catch FileMutationError.malformed {
            return .malformedExistingConfig
        } catch FileMutationError.conflict {
            return .conflict
        } catch {
            return .failed("Could not access the selected Codex configuration.")
        }
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func handler(command: String, event: CodexHookEvent,
                                permissionActionsEnabled: Bool) -> [String: Any] {
        let usesActionMode = event == .permissionRequest && permissionActionsEnabled
        let arguments = usesActionMode ? " \(event.rawValue) --permission-actions" : " \(event.rawValue)"
        return ["type": "command", "command": command + arguments,
                "timeout": usesActionMode ? 12 : 1]
    }

    private static func isOwned(_ handler: [String: Any], command: String) -> Bool {
        guard handler["type"] as? String == "command",
              let value = handler["command"] as? String else { return false }
        if CodexHookEvent.allCases.contains(where: { value == "\(command) \($0.rawValue)" }) { return true }
        return value == "\(command) PermissionRequest --permission-actions"
    }

    private static func ensureDirectory(_ url: URL, mode: mode_t) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid() else { throw FileMutationError.permissionDenied }
            return
        }
        guard errno == ENOENT else { throw FileMutationError.permissionDenied }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard chmod(url.path, mode) == 0 else { throw FileMutationError.permissionDenied }
    }

    private static func lockFile(_ url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw FileMutationError.permissionDenied }
        guard flock(descriptor, LOCK_EX) == 0 else { Darwin.close(descriptor); throw FileMutationError.permissionDenied }
        return descriptor
    }

    private static func readRegularFileIfPresent(_ url: URL) throws -> Data? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            if errno == ENOENT { return nil }
            throw FileMutationError.permissionDenied
        }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else { throw FileMutationError.permissionDenied }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw FileMutationError.permissionDenied }
        defer { Darwin.close(descriptor) }
        var current = stat()
        guard fstat(descriptor, &current) == 0, current.st_dev == info.st_dev, current.st_ino == info.st_ino else {
            throw FileMutationError.conflict
        }
        guard current.st_size <= 1_048_576 else { throw FileMutationError.malformed }
        var data = Data(count: Int(current.st_size))
        try data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.read(descriptor, base.advanced(by: offset), raw.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                throw FileMutationError.conflict
            }
        }
        return data
    }

    private static func compareAndReplace(_ data: Data, at url: URL, expected: Data?) throws {
        let current = try readRegularFileIfPresent(url)
        guard current == expected else { throw FileMutationError.conflict }
        let parent = url.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".nudge-\(UUID().uuidString).tmp")
        let permissions = (urlAttributes(url)?[.posixPermissions] as? NSNumber)?.intValue ?? 0o600
        let descriptor = open(temporary.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(permissions))
        guard descriptor >= 0 else { throw FileMutationError.permissionDenied }
        defer { Darwin.close(descriptor); _ = unlink(temporary.path) }
        guard fchmod(descriptor, mode_t(permissions)) == 0 else { throw FileMutationError.permissionDenied }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                throw FileMutationError.permissionDenied
            }
        }
        guard fsync(descriptor) == 0 else { throw FileMutationError.permissionDenied }
        let latest = try readRegularFileIfPresent(url)
        guard latest == expected else { throw FileMutationError.conflict }
        guard rename(temporary.path, url.path) == 0 else { throw FileMutationError.permissionDenied }
        let directory = open(parent.path, O_RDONLY)
        if directory >= 0 { _ = fsync(directory); Darwin.close(directory) }
    }

    private static func urlAttributes(_ url: URL) -> [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfItem(atPath: url.path)
    }

    private static func createBackup(_ data: Data, for target: CodexConfigurationTarget, directory override: URL?) throws -> String {
        let appSupport = override ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Nudge/Backups", isDirectory: true)
        try ensureDirectory(appSupport.deletingLastPathComponent(), mode: 0o700)
        try ensureDirectory(appSupport, mode: 0o700)
        guard chmod(appSupport.path, mode_t(0o700)) == 0 else { throw FileMutationError.permissionDenied }
        let timestamp = Int(Date().timeIntervalSince1970)
        let name = "hooks-\(target.host.rawValue)-\(timestamp)-\(UUID().uuidString).json.bak"
        let url = appSupport.appendingPathComponent(name)
        let descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw FileMutationError.permissionDenied }
        defer { Darwin.close(descriptor) }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), raw.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                throw FileMutationError.permissionDenied
            }
        }
        guard fsync(descriptor) == 0 else { throw FileMutationError.permissionDenied }
        let directory = open(appSupport.path, O_RDONLY)
        if directory >= 0 { _ = fsync(directory); Darwin.close(directory) }
        return url.path
    }

}

private enum FileMutationError: Error { case permissionDenied, malformed, conflict }
