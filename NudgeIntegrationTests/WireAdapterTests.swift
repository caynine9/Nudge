import XCTest

final class WireAdapterTests: XCTestCase {
    private let hooks: [CodexHookEvent] = [.sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .stop, .interrupt]

    func testSyntheticDesktopAndCLIFixturesSanitizePayloadBeforeWire() throws {
        for host in ["desktop", "cli"] {
            for hook in hooks {
                let fixture = Bundle(for: Self.self).resourceURL!
                    .appendingPathComponent("Codex/\(host)/\(hook.rawValue).json")
                let input = try Data(contentsOf: fixture)
                let envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: hook,
                    now: Date(timeIntervalSince1970: 1_700_000_000))
                try envelope.validate()
                let wire = try WireCodec.encode(envelope)
                let wireString = String(decoding: wire.dropFirst(4), as: UTF8.self)
                XCTAssertFalse(wireString.contains("SYNTHETIC_SECRET"), "\(host) \(hook)")
                XCTAssertFalse(wireString.contains("tool_input"))
                XCTAssertFalse(wireString.contains("tool_response"))
                XCTAssertEqual(envelope.event, hook)
                if hook == .preToolUse { XCTAssertEqual(envelope.tool?.summary, "Running command") }
            }
        }
    }

    func testUnexpectedEventAndOversizedIdentityAreRejected() {
        let unexpected = Data(#"{"hook_event_name":"PermissionRequest","session_id":"s"}"#.utf8)
        XCTAssertThrowsError(try CodexHookAdapter().envelope(from: unexpected, expectedEvent: .sessionStart))

        let longID = String(repeating: "x", count: 300)
        let oversized = Data(#"{"hook_event_name":"SessionStart","session_id":"\#(longID)"}"#.utf8)
        XCTAssertThrowsError(try CodexHookAdapter().envelope(from: oversized, expectedEvent: .sessionStart))
    }

    func testContinuedStopIsNotReportedAsTurnCompletion() {
        let continued = Data(#"{"hook_event_name":"Stop","session_id":"s","turn_id":"t","stop_hook_active":true}"#.utf8)
        XCTAssertThrowsError(try CodexHookAdapter().envelope(from: continued, expectedEvent: .stop)) { error in
            XCTAssertEqual(error as? HookPayloadError, .nonTerminalStop)
        }
    }
}
