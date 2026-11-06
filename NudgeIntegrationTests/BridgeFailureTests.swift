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

    func testMemoryWorkersNeverReachNudgeButUserSessionsStillDo() throws {
        let (directory, eventPath) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let codexHome = directory.appendingPathComponent("custom codex home")
        let memoryRoot = codexHome.appendingPathComponent("memories_v2")
        let legacyMemoryRoot = codexHome.appendingPathComponent("memories")
        let userProject = directory.appendingPathComponent("memories_v2")
        for workspace in [memoryRoot, legacyMemoryRoot, userProject] {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        }

        let userSessions = expectation(description: "only user sessions reach the event socket")
        userSessions.expectedFulfillmentCount = 2
        let eventServer = NudgeSocketServer(path: eventPath) { event in
            guard ["saved-thread", "same-name-project"].contains(event.sessionID) else {
                XCTFail("An internal memory worker reached Nudge")
                return
            }
            userSessions.fulfill()
        }
        let permissionPath = directory.appendingPathComponent("permission.sock").path
        let permissionServer = NudgePermissionSocketServer(path: permissionPath) { _ in
            XCTFail("An internal memory worker requested a Nudge permission decision")
            return .allowOnce
        }
        try eventServer.start()
        try permissionServer.start()
        defer { eventServer.stop(); permissionServer.stop() }

        func invoke(_ event: String, session: String, workspace: URL, reportedCWD: URL? = nil,
                    transcript: String? = nil, permissionActions: Bool = false) throws {
            let payload: [String: Any] = [
                "hook_event_name": event, "session_id": session, "turn_id": "turn",
                "cwd": (reportedCWD ?? workspace).path, "transcript_path": transcript as Any? ?? NSNull(),
                "tool_name": "apply_patch", "tool_use_id": "tool"
            ]
            let (status, output, _) = try runBridge(input: JSONSerialization.data(withJSONObject: payload),
                                                   socketPath: eventPath, event: event,
                                                   permissionSocketPath: permissionPath,
                                                   permissionActions: permissionActions,
                                                   workingDirectory: workspace, codexHome: codexHome)
            XCTAssertEqual(status, EXIT_SUCCESS)
            XCTAssertEqual(String(decoding: output, as: UTF8.self), event == "Stop" ? "{}\n" : "")
        }

        try invoke("PreToolUse", session: "worker", workspace: memoryRoot, reportedCWD: userProject)
        try invoke("Stop", session: "legacy-worker", workspace: legacyMemoryRoot)
        try invoke("PermissionRequest", session: "worker", workspace: memoryRoot, permissionActions: true)
        try invoke("PreToolUse", session: "saved-thread", workspace: memoryRoot, transcript: "/fake/session.jsonl")
        try invoke("PreToolUse", session: "same-name-project", workspace: userProject, reportedCWD: memoryRoot)
        eventServer.flushEvents()
        wait(for: [userSessions], timeout: 2)
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

    func testPermissionSubprocessReturnsOfficialOneShotDecisionWithoutForwardingCommand() throws {
        let (directory, eventPath) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let permissionPath = directory.appendingPathComponent("permission.sock").path
        let capture = PermissionInvocationCapture()
        let eventReceived = expectation(description: "permission mirror event received")
        let requestReceived = expectation(description: "one-shot request received")
        let eventServer = NudgeSocketServer(path: eventPath) { envelope in
            capture.record(envelope)
            eventReceived.fulfill()
        }
        let permissionServer = NudgePermissionSocketServer(path: permissionPath) { request in
            capture.record(request)
            requestReceived.fulfill()
            return .allowOnce
        }
        try eventServer.start()
        try permissionServer.start()
        defer { eventServer.stop(); permissionServer.stop() }

        let input = Data(#"{"hook_event_name":"PermissionRequest","session_id":"synthetic-session","turn_id":"turn-1","tool_name":"Bash","tool_input":{"description":"Run the unit tests","command":"echo NUDGE_COMMAND_SECRET"}}"#.utf8)
        let (status, output, elapsed) = try runBridge(input: input, socketPath: eventPath, event: "PermissionRequest",
                                                     permissionSocketPath: permissionPath, permissionActions: true)
        wait(for: [eventReceived, requestReceived], timeout: 2)
        XCTAssertEqual(status, EXIT_SUCCESS)
        XCTAssertLessThan(elapsed, 2)
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("NUDGE_COMMAND_SECRET"))
        let response = try JSONSerialization.jsonObject(with: output) as! [String: Any]
        let hook = response["hookSpecificOutput"] as! [String: Any]
        let decision = hook["decision"] as! [String: Any]
        XCTAssertEqual(hook["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertEqual(Set(decision.keys), ["behavior"])

        let captured = capture.values
        XCTAssertEqual(captured.0?.interaction?.id, captured.1?.interactionID)
        XCTAssertEqual(captured.0?.interaction?.preview, "Run the unit tests")
        XCTAssertEqual(captured.1?.summary, "Run the unit tests")
    }

    func testPermissionSubprocessUsesNativeFallbackWhenResponseListenerIsUnavailable() throws {
        let (directory, eventPath) = temporarySocketPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unavailablePermissionPath = directory.appendingPathComponent("missing.sock").path
        let eventReceived = expectation(description: "mirror still reaches Nudge")
        let eventServer = NudgeSocketServer(path: eventPath) { _ in eventReceived.fulfill() }
        try eventServer.start()
        defer { eventServer.stop() }

        let input = Data(#"{"hook_event_name":"PermissionRequest","session_id":"synthetic-session","turn_id":"turn-1","tool_name":"Bash","tool_input":{"description":"Run the unit tests"}}"#.utf8)
        let (status, output, elapsed) = try runBridge(input: input, socketPath: eventPath, event: "PermissionRequest",
                                                     permissionSocketPath: unavailablePermissionPath,
                                                     permissionActions: true)
        wait(for: [eventReceived], timeout: 2)
        XCTAssertEqual(status, EXIT_SUCCESS)
        XCTAssertTrue(output.isEmpty, "No decision output leaves Codex's native approval flow active.")
        XCTAssertLessThan(elapsed, 2)
    }

    private func runBridge(input: Data, socketPath: String, event: String = "Stop",
                           permissionSocketPath: String? = nil,
                           permissionActions: Bool = false,
                           workingDirectory: URL? = nil, codexHome: URL? = nil) throws -> (Int32, Data, TimeInterval) {
        let process = try bridgeProcess(socketPath: socketPath, event: event,
                                        permissionActions: permissionActions,
                                        permissionSocketPath: permissionSocketPath)
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        if let codexHome { process.environment?["CODEX_HOME"] = codexHome.path }
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

    private func bridgeProcess(socketPath: String, event: String = "Stop", permissionActions: Bool = false,
                               permissionSocketPath: String? = nil) throws -> Process {
        let integrationBundle = Bundle(for: BridgeFailureTests.self).bundleURL
        let executable = integrationBundle.appendingPathComponent("Contents/MacOS/NudgeBridge")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw NSError(domain: "NudgeIntegrationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "NudgeBridge test executable is missing from the integration test bundle."])
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--event", event] + (permissionActions ? ["--permission-actions"] : [])
        var overrides = ["NUDGE_TEST_SOCKET_PATH": socketPath]
        if let permissionSocketPath { overrides["NUDGE_TEST_PERMISSION_SOCKET_PATH"] = permissionSocketPath }
        process.environment = ProcessInfo.processInfo.environment.merging(overrides) { _, new in new }
        return process
    }

    private func temporarySocketPath() -> (URL, String) {
        let directory = URL(fileURLWithPath: "/tmp/nudge-b-\(UUID().uuidString.prefix(7))", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appendingPathComponent("e.sock").path)
    }
}

private final class PermissionInvocationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var event: WireEnvelope?
    private var request: PermissionRequestMessage?

    var values: (WireEnvelope?, PermissionRequestMessage?) {
        lock.lock()
        defer { lock.unlock() }
        return (event, request)
    }

    func record(_ value: WireEnvelope) {
        lock.lock()
        event = value
        lock.unlock()
    }

    func record(_ value: PermissionRequestMessage) {
        lock.lock()
        request = value
        lock.unlock()
    }
}
