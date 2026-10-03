import Darwin
import Foundation

enum PermissionSocketTransport {
    static var socketPath: String {
        #if DEBUG
        if let testPath = ProcessInfo.processInfo.environment["NUDGE_TEST_PERMISSION_SOCKET_PATH"],
           testPath.hasPrefix("/tmp/") { return testPath }
        #endif
        return "/tmp/nudge-\(getuid())-p.sock"
    }

    static func exchange(_ request: PermissionRequestMessage, path: String = socketPath,
                         timeout: TimeInterval) throws -> PermissionDecision {
        try request.validate()
        let descriptor = try UnixSocketTransport.openSocket()
        defer { Darwin.close(descriptor) }
        let deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(max(0, timeout) * 1_000_000_000)
        try UnixSocketTransport.connect(descriptor, path: path, deadline: deadline)
        try UnixSocketTransport.verifyPeer(descriptor)
        try UnixSocketTransport.writeAll(try frame(request), descriptor: descriptor, deadline: deadline)
        let responseData = try readFrame(descriptor, deadline: deadline)
        let response = try PermissionMessageCodec.decodeResponse(responseData)
        try response.validate(expectedRequestID: request.requestID)
        return response.decision
    }

    static func frame<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(value)
        guard !payload.isEmpty, payload.count <= PermissionRequestMessage.maximumFrameSize else {
            throw WireError.frameTooLarge
        }
        var length = UInt32(payload.count).bigEndian
        var result = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        result.append(payload)
        return result
    }

    static func readFrame(_ descriptor: Int32, deadline: UInt64) throws -> Data {
        let header = try UnixSocketTransport.readExact(4, descriptor: descriptor, deadline: deadline)
        let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        guard length > 0, length <= PermissionRequestMessage.maximumFrameSize else { throw WireError.frameTooLarge }
        return try UnixSocketTransport.readExact(Int(length), descriptor: descriptor, deadline: deadline)
    }
}

final class NudgePermissionSocketServer: @unchecked Sendable {
    typealias RequestHandler = @Sendable (PermissionRequestMessage) async -> PermissionDecision?

    let path: String
    private let handler: RequestHandler
    private let queue = DispatchQueue(label: "com.nudge.permission-listener", qos: .userInitiated)
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var ownedSocketIdentity: (dev_t, ino_t)?
    private let maximumConnections = DispatchSemaphore(value: 8)

    init(path: String = PermissionSocketTransport.socketPath, handler: @escaping RequestHandler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        guard descriptor == -1 else { return }
        try prepareSocketPath()
        let listener = try UnixSocketTransport.openSocket()
        do {
            var address = try UnixSocketTransport.socketAddress(path)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0, lstat(path, &statBuffer) == 0,
                  (statBuffer.st_mode & S_IFMT) == S_IFSOCK, statBuffer.st_uid == getuid() else {
                throw WireError.unavailable
            }
            ownedSocketIdentity = (statBuffer.st_dev, statBuffer.st_ino)
            guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0, Darwin.listen(listener, 8) == 0 else {
                throw WireError.unavailable
            }
            let flags = fcntl(listener, F_GETFL)
            guard flags >= 0, fcntl(listener, F_SETFL, flags | O_NONBLOCK) == 0 else { throw WireError.unavailable }
            descriptor = listener
            let readSource = DispatchSource.makeReadSource(fileDescriptor: listener, queue: queue)
            readSource.setEventHandler { [weak self] in self?.acceptAvailableConnections() }
            readSource.setCancelHandler { Darwin.close(listener) }
            source = readSource
            readSource.resume()
        } catch {
            Darwin.close(listener)
            removeOwnedSocketPath()
            throw error
        }
    }

    func stop() {
        guard descriptor != -1 else { return }
        descriptor = -1
        source?.cancel()
        source = nil
        removeOwnedSocketPath()
    }

    private var statBuffer = stat()

    private func prepareSocketPath() throws {
        var existing = stat()
        guard lstat(path, &existing) == 0 else {
            if errno == ENOENT { return }
            throw WireError.unavailable
        }
        guard (existing.st_mode & S_IFMT) == S_IFSOCK, existing.st_uid == getuid() else { throw WireError.invalidPeer }
        let probe = try UnixSocketTransport.openSocket()
        defer { Darwin.close(probe) }
        do {
            try UnixSocketTransport.connect(probe, path: path,
                deadline: DispatchTime.now().uptimeNanoseconds + 100_000_000)
            throw WireError.invalidPeer
        } catch WireError.invalidPeer {
            throw WireError.invalidPeer
        } catch {
            guard error as? WireError == .unavailable else { throw error }
        }
        var current = stat()
        guard lstat(path, &current) == 0, current.st_dev == existing.st_dev, current.st_ino == existing.st_ino,
              current.st_uid == getuid(), (current.st_mode & S_IFMT) == S_IFSOCK, unlink(path) == 0 else {
            throw WireError.invalidPeer
        }
    }

    private func acceptAvailableConnections() {
        guard descriptor >= 0 else { return }
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard maximumConnections.wait(timeout: .now()) == .success else { Darwin.close(client); continue }
            let flags = fcntl(client, F_GETFL)
            guard flags >= 0, fcntl(client, F_SETFL, flags | O_NONBLOCK) == 0 else {
                Darwin.close(client)
                maximumConnections.signal()
                continue
            }
            Task.detached(priority: .userInitiated) { [self] in
                defer { Darwin.close(client); maximumConnections.signal() }
                await receive(from: client)
            }
        }
    }

    private func receive(from client: Int32) async {
        do {
            try UnixSocketTransport.verifyPeer(client)
            let deadline = DispatchTime.now().uptimeNanoseconds + 750_000_000
            let payload = try PermissionSocketTransport.readFrame(client, deadline: deadline)
            let request = try PermissionMessageCodec.decodeRequest(payload)
            try request.validate()
            guard let decision = await handler(request) else { return }
            let response = PermissionResponseMessage(requestID: request.requestID, decision: decision)
            try UnixSocketTransport.writeAll(try PermissionSocketTransport.frame(response), descriptor: client,
                                             deadline: DispatchTime.now().uptimeNanoseconds + 250_000_000)
        } catch {
            // An unavailable or invalid decision channel closes without a response; Codex keeps its native prompt.
        }
    }

    private func removeOwnedSocketPath() {
        guard let identity = ownedSocketIdentity else { return }
        var current = stat()
        if lstat(path, &current) == 0, current.st_dev == identity.0, current.st_ino == identity.1,
           current.st_uid == getuid(), (current.st_mode & S_IFMT) == S_IFSOCK { _ = unlink(path) }
        ownedSocketIdentity = nil
    }
}
