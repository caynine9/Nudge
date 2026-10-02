import Darwin
import Foundation
import XCTest

final class SocketTransportTests: XCTestCase {
    func testOwnerOnlySocketAcceptsLengthPrefixedEnvelope() throws {
        let (directory, path) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let received = expectation(description: "validated local event received")
        let server = NudgeSocketServer(path: path) { envelope in
            XCTAssertEqual(envelope.sessionID, "socket-fixture")
            received.fulfill()
        }
        try server.start()
        defer { server.stop() }
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0)
        XCTAssertEqual(info.st_mode & 0o777, 0o600)

        try UnixSocketTransport.send(envelope(), to: path, timeout: 0.4)
        wait(for: [received], timeout: 2)
    }

    func testFragmentedFrameIsReadCompletely() throws {
        let (directory, path) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let received = expectation(description: "fragmented frame received")
        let server = NudgeSocketServer(path: path) { _ in received.fulfill() }
        try server.start()
        defer { server.stop() }

        let descriptor = try UnixSocketTransport.openSocket()
        defer { Darwin.close(descriptor) }
        let deadline = DispatchTime.now().uptimeNanoseconds + 500_000_000
        try UnixSocketTransport.connect(descriptor, path: path, deadline: deadline)
        try UnixSocketTransport.verifyPeer(descriptor)
        for byte in try WireCodec.encode(envelope()) {
            try UnixSocketTransport.writeAll(Data([byte]), descriptor: descriptor, deadline: deadline)
        }
        wait(for: [received], timeout: 2)
    }

    func testFlushWaitsForAcceptedFramesToReachEventHandler() throws {
        let (directory, path) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = SocketEventCapture()
        let server = NudgeSocketServer(path: path) { envelope in capture.append(envelope.sessionID) }
        try server.start()
        defer { server.stop() }

        try UnixSocketTransport.send(envelope(), to: path, timeout: 0.4)
        server.flushEvents()

        XCTAssertEqual(capture.sessionIDs, ["socket-fixture"])
    }

    func testRegularFileAndSecondLiveListenerAreNeverUnlinked() throws {
        let (directory, path) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("keep".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertThrowsError(try NudgeSocketServer(path: path) { _ in }.start())
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("keep".utf8))
        try FileManager.default.removeItem(atPath: path)

        let first = NudgeSocketServer(path: path) { _ in }
        try first.start()
        defer { first.stop() }
        let second = NudgeSocketServer(path: path) { _ in }
        XCTAssertThrowsError(try second.start())
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
    }

    func testStaleOwnedSocketIsReplacedAfterRefusedProbe() throws {
        let (directory, path) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = try UnixSocketTransport.openSocket()
        var address = try UnixSocketTransport.socketAddress(path)
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        Darwin.close(stale)

        let server = NudgeSocketServer(path: path) { _ in }
        try server.start()
        defer { server.stop() }
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFSOCK)
    }

    func testSymlinkAtSocketPathIsNeverRemoved() throws {
        let (directory, path) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target")
        try Data("keep".utf8).write(to: target)
        XCTAssertEqual(symlink(target.path, path), 0)
        XCTAssertThrowsError(try NudgeSocketServer(path: path) { _ in }.start())
        var info = stat()
        XCTAssertEqual(lstat(path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFLNK)
        XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    }

    private func temporarySocketPath() -> (URL, String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ndg-\(UUID().uuidString.prefix(7))", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("e.sock").path)
    }

    private func envelope() -> WireEnvelope {
        WireEnvelope(schemaVersion: 1, source: "codex", event: .userPromptSubmit, sessionID: "socket-fixture",
                     turnID: "turn-1", observedAtMilliseconds: 1, projectLabel: "Fixture", toolCallID: nil, tool: nil)
    }
}

private final class SocketEventCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    var sessionIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}
