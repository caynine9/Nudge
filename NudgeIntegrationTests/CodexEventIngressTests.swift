import XCTest

final class CodexEventIngressTests: XCTestCase {
    func testIngressProcessesEventsInOrderAndWakeBarrierWaitsForPendingEvents() async {
        let monitor = CodexEventMonitor()
        let capture = SnapshotCapture()
        let ingress = CodexEventIngress(monitor: monitor) { snapshot in
            await capture.append(snapshot)
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
        ingress.finish()
    }

    private func envelope(_ event: CodexHookEvent, turn: String, at date: Date,
                          toolID: String? = nil, tool: ToolActivity? = nil) -> WireEnvelope {
        WireEnvelope(schemaVersion: WireEnvelope.currentVersion, source: "codex", event: event,
                     sessionID: "ingress-test", turnID: turn,
                     observedAtMilliseconds: Int64(date.timeIntervalSince1970 * 1_000),
                     projectLabel: nil, toolCallID: toolID, tool: tool)
    }
}

private actor SnapshotCapture {
    private(set) var phases: [SessionPhase] = []

    func append(_ snapshot: ActivityMonitorSnapshot) {
        phases.append(snapshot.focused.phase)
    }
}
