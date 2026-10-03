import XCTest

final class CodexEventIngressTests: XCTestCase {
    func testSessionIDBuildsEncodedCodexLocalThreadLink() throws {
        let url = try XCTUnwrap(CodexThreadDeepLink.url(sessionID: "01a0fcb0-0000-4000-8000-aabbccddeeff"))
        XCTAssertEqual(url.absoluteString, "codex://threads/01a0fcb0-0000-4000-8000-aabbccddeeff")

        let opaqueID = try XCTUnwrap(CodexThreadDeepLink.url(sessionID: "session:part/with space"))
        XCTAssertEqual(opaqueID.absoluteString, "codex://threads/session%3Apart%2Fwith%20space")
    }

    func testInvalidSessionIDDoesNotProduceCodexLink() {
        XCTAssertNil(CodexThreadDeepLink.url(sessionID: ""))
        XCTAssertNil(CodexThreadDeepLink.url(sessionID: "session\nid"))
        XCTAssertNil(CodexThreadDeepLink.url(sessionID: String(repeating: "x", count: 257)))
    }

    func testIngressProcessesEventsInOrderAndWakeBarrierWaitsForPendingEvents() async {
        let monitor = CodexEventMonitor()
        let capture = SnapshotCapture()
        let ingress = CodexEventIngress(monitor: monitor) { snapshot, event in
            await capture.append(snapshot, event: event)
        }
        let origin = Date(timeIntervalSinceNow: -5)

        ingress.submit(envelope(.userPromptSubmit, turn: "turn", at: origin))
        ingress.submit(envelope(.preToolUse, turn: "turn", at: origin.addingTimeInterval(1),
                                toolID: "tool", tool: ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")))
        ingress.submit(envelope(.postToolUse, turn: "turn", at: origin.addingTimeInterval(2), toolID: "tool"))
        ingress.submit(envelope(.stop, turn: "turn", at: origin.addingTimeInterval(3)))

        let restored = await ingress.snapshotAfterPendingEvents()
        XCTAssertEqual(restored.focused.phase, .completed)
        XCTAssertEqual(restored.focused.turnID, "turn")
        let phases = await capture.phases
        XCTAssertEqual(phases, [.thinking, .toolUse, .thinking, .completed])
        let events = await capture.events
        XCTAssertEqual(events, [.userPromptSubmit, .preToolUse, .postToolUse, .stop])
        ingress.finish()
    }

    private func envelope(_ event: CodexHookEvent, turn: String, at date: Date,
                          toolID: String? = nil, tool: ToolActivity? = nil) -> WireEnvelope {
        WireEnvelope(schemaVersion: WireEnvelope.currentVersion, source: "codex", event: event,
                     sessionID: "ingress-test", turnID: turn,
                     observedAtMilliseconds: Int64(date.timeIntervalSince1970 * 1_000),
                     projectLabel: nil, toolCallID: toolID, tool: tool,
                     toolName: event == .preToolUse || event == .postToolUse ? "Bash" : nil)
    }
}

private actor SnapshotCapture {
    private(set) var phases: [SessionPhase] = []
    private(set) var events: [CodexHookEvent] = []

    func append(_ snapshot: ActivityMonitorSnapshot, event: CodexHookEvent) {
        phases.append(snapshot.focused.phase)
        events.append(event)
    }
}
