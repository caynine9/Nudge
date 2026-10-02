import Darwin
import Foundation
import OSLog

enum UnixSocketTransport {
    static func send(_ envelope: WireEnvelope, to path: String, timeout: TimeInterval) throws {
        let frame = try WireCodec.encode(envelope)
        let descriptor = try openSocket()
        defer { Darwin.close(descriptor) }
        let deadline = DispatchTime.now().uptimeNanoseconds &+ UInt64(max(timeout, 0) * 1_000_000_000)
        try connect(descriptor, path: path, deadline: deadline)
        try verifyPeer(descriptor)
        try writeAll(frame, descriptor: descriptor, deadline: deadline)
    }

    static func openSocket() throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw WireError.unavailable }
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            Darwin.close(descriptor)
            throw WireError.unavailable
        }
        return descriptor
    }

    static func connect(_ descriptor: Int32, path: String, deadline: UInt64) throws {
        var address = try socketAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if result != 0, errno != EINPROGRESS { throw WireError.unavailable }
        if result != 0 {
            try wait(descriptor, events: Int16(POLLOUT), deadline: deadline)
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0, socketError == 0 else {
                throw WireError.unavailable
            }
        }
    }

    static func verifyPeer(_ descriptor: Int32) throws {
        var uid = uid_t.max
        var gid = gid_t.max
        guard getpeereid(descriptor, &uid, &gid) == 0, uid == getuid() else { throw WireError.invalidPeer }
    }

    static func writeAll(_ data: Data, descriptor: Int32, deadline: UInt64) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { throw WireError.malformedPayload }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count; continue }
                if count < 0, errno == EINTR { continue }
                if count < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    try wait(descriptor, events: Int16(POLLOUT), deadline: deadline)
                    continue
                }
                throw WireError.unavailable
            }
        }
    }

    static func readExact(_ count: Int, descriptor: Int32, deadline: UInt64) throws -> Data {
        guard count >= 0, count <= WireEnvelope.maximumFrameSize else { throw WireError.frameTooLarge }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else {
                if count == 0 { return }
                throw WireError.malformedPayload
            }
            var offset = 0
            while offset < count {
                let received = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if received > 0 { offset += received; continue }
                if received == 0 { throw WireError.unavailable }
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    try wait(descriptor, events: Int16(POLLIN), deadline: deadline)
                    continue
                }
                throw WireError.unavailable
            }
        }
        return data
    }

    static func wait(_ descriptor: Int32, events: Int16, deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw WireError.timedOut }
            let milliseconds = Int32(max(1, min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max))))
            var pollDescriptor = pollfd(fd: descriptor, events: events, revents: 0)
            let result = Darwin.poll(&pollDescriptor, 1, milliseconds)
            if result > 0 {
                if pollDescriptor.revents & Int16(POLLNVAL | POLLERR) != 0 { throw WireError.unavailable }
                if pollDescriptor.revents & events != 0 { return }
                if pollDescriptor.revents & Int16(POLLHUP) != 0 { throw WireError.unavailable }
            } else if result == 0 {
                throw WireError.timedOut
            } else if errno != EINTR {
                throw WireError.unavailable
            }
        }
    }

    static func socketAddress(_ path: String) throws -> sockaddr_un {
        guard path.hasPrefix("/"), path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw WireError.unavailable
        }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        path.withCString { source in
            withUnsafeMutableBytes(of: &address.sun_path) { destination in
                _ = strlcpy(destination.baseAddress!.assumingMemoryBound(to: CChar.self), source, destination.count)
            }
        }
        return address
    }
}

final class NudgeSocketServer: @unchecked Sendable {
    typealias EventHandler = @Sendable (WireEnvelope) -> Void

    let path: String
    private let handler: EventHandler
    private let queue = DispatchQueue(label: "com.nudge.socket-listener", qos: .userInitiated)
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private var ownedSocketIdentity: (dev_t, ino_t)?
    private let maximumConnections = DispatchSemaphore(value: 16)

    init(path: String = "/tmp/nudge-\(getuid()).sock", handler: @escaping EventHandler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        guard descriptor == -1 else { return }
        try prepareSocketPath()
        let listener = try UnixSocketTransport.openSocket()
        do {
            var address = try UnixSocketTransport.socketAddress(path)
            let bindResult = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard bindResult == 0 else { throw WireError.unavailable }
            guard lstat(path, &statBuffer) == 0,
                  (statBuffer.st_mode & S_IFMT) == S_IFSOCK, statBuffer.st_uid == getuid() else {
                throw WireError.unavailable
            }
            ownedSocketIdentity = (statBuffer.st_dev, statBuffer.st_ino)
            guard chmod(path, mode_t(S_IRUSR | S_IWUSR)) == 0,
                  Darwin.listen(listener, 8) == 0 else { throw WireError.unavailable }
            let flags = fcntl(listener, F_GETFL)
            guard flags >= 0, fcntl(listener, F_SETFL, flags | O_NONBLOCK) == 0 else {
                throw WireError.unavailable
            }
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
        guard (existing.st_mode & S_IFMT) == S_IFSOCK, existing.st_uid == getuid() else {
            throw WireError.invalidPeer
        }
        let probe = try UnixSocketTransport.openSocket()
        defer { Darwin.close(probe) }
        do {
            try UnixSocketTransport.connect(probe, path: path,
                                            deadline: DispatchTime.now().uptimeNanoseconds + 100_000_000)
            throw WireError.invalidPeer // A live listener owns the endpoint.
        } catch WireError.invalidPeer {
            throw WireError.invalidPeer
        } catch {
            guard error as? WireError == .unavailable else { throw error }
        }
        var current = stat()
        guard lstat(path, &current) == 0,
              current.st_dev == existing.st_dev, current.st_ino == existing.st_ino,
              current.st_uid == getuid(), (current.st_mode & S_IFMT) == S_IFSOCK,
              unlink(path) == 0 else { throw WireError.invalidPeer }
    }

    private func acceptAvailableConnections() {
        guard descriptor >= 0 else { return }
        while true {
            let client = Darwin.accept(descriptor, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            guard maximumConnections.wait(timeout: .now()) == .success else {
                Darwin.close(client)
                continue
            }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer {
                    Darwin.close(client)
                    maximumConnections.signal()
                }
                receive(from: client)
            }
        }
    }

    private func receive(from client: Int32) {
        do {
            try UnixSocketTransport.verifyPeer(client)
            let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
            let header = try UnixSocketTransport.readExact(4, descriptor: client, deadline: deadline)
            let length = header.withUnsafeBytes { raw -> UInt32 in
                raw.loadUnaligned(as: UInt32.self).bigEndian
            }
            guard length > 0, length <= WireEnvelope.maximumFrameSize else { throw WireError.frameTooLarge }
            let payload = try UnixSocketTransport.readExact(Int(length), descriptor: client, deadline: deadline)
            let envelope = try WireCodec.decode(payload)
            handler(envelope)
        } catch let error as WireError {
            SocketDiagnostics.record(error.diagnosticCode)
        } catch {
            SocketDiagnostics.record("unexpected-error")
        }
    }

    private func removeOwnedSocketPath() {
        guard let identity = ownedSocketIdentity else { return }
        var current = stat()
        if lstat(path, &current) == 0,
           current.st_dev == identity.0, current.st_ino == identity.1,
           current.st_uid == getuid(), (current.st_mode & S_IFMT) == S_IFSOCK {
            _ = unlink(path)
        }
        ownedSocketIdentity = nil
    }
}

private enum SocketDiagnostics {
    private static let throttle = SocketDiagnosticThrottle()

    static func record(_ code: String) { throttle.record(code) }
}

private final class SocketDiagnosticThrottle: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.nudge", category: "local-events")
    private let lock = NSLock()
    private var lastEmission: [String: UInt64] = [:]

    func record(_ code: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        let shouldEmit: Bool
        if let last = lastEmission[code], now >= last, now - last < 60_000_000_000 {
            shouldEmit = false
        } else {
            lastEmission[code] = now
            shouldEmit = true
        }
        lock.unlock()
        if shouldEmit { logger.error("Discarded local hook frame (\(code, privacy: .public))") }
    }
}
