import Foundation
import XCTest

final class BridgeFailureTests: XCTestCase {
    func testBridgeSubprocessReturnsNeutralOutputWhenListenerIsUnavailable() throws {
        let (directory, socketPath) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = Data(#"{"hook_event_name":"Stop","session_id":"synthetic","turn_id":"t1","last_assistant_message":"SYNTHETIC_SECRET"}"#.utf8)
        let (status, output, elapsed) = try runBridge(input: input, socketPath: socketPath)
        XCTAssertEqual(status, EXIT_SUCCESS)
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "{}\n")
        XCTAssertLessThan(elapsed, 2)
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("SYNTHETIC_SECRET"))
    }

    func testNonStopHookCompletesWithoutOutput() throws {
        let (directory, socketPath) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"synthetic","turn_id":"t1","prompt":"SYNTHETIC_SECRET"}"#.utf8)
        let (status, output, _) = try runBridge(input: input, socketPath: socketPath, event: "UserPromptSubmit")
        XCTAssertEqual(status, EXIT_SUCCESS)
        XCTAssertTrue(output.isEmpty)
    }

    func testBridgeSubprocessHandlesStalledInputWithinDeadline() throws {
        let process = try bridgeProcess(socketPath: "/tmp/nudge-test-no-listener.sock")
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let startedAt = Date()
        try process.run()
        input.fileHandleForWriting.write(Data("{".utf8))
        XCTAssertEqual(output.fileHandleForReading.readDataToEndOfFile(), Data("{}\n".utf8))
        process.waitUntilExit()
        input.fileHandleForWriting.closeFile()
        XCTAssertEqual(process.terminationStatus, EXIT_SUCCESS)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2)
    }

    private func runBridge(input: Data, socketPath: String, event: String = "Stop") throws -> (Int32, Data, TimeInterval) {
        let process = try bridgeProcess(socketPath: socketPath, event: event)
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let started = Date()
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: watchdog)
        defer { watchdog.cancel() }
        stdin.fileHandleForWriting.write(input)
        stdin.fileHandleForWriting.closeFile()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, output, Date().timeIntervalSince(started))
    }

    private func bridgeProcess(socketPath: String, event: String = "Stop") throws -> Process {
        let integrationBundle = Bundle(for: BridgeFailureTests.self).bundleURL
        let executable = integrationBundle.appendingPathComponent("Contents/MacOS/NudgeBridge")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "NudgeIntegrationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "NudgeBridge test executable is missing from the integration test bundle."])
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--event", event]
        process.environment = ProcessInfo.processInfo.environment.merging(["NUDGE_TEST_SOCKET_PATH": socketPath]) { _, new in new }
        return process
    }

    private func temporarySocketPath() -> (URL, String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ndg-b-\(UUID().uuidString.prefix(7))", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("e.sock").path)
    }
}
