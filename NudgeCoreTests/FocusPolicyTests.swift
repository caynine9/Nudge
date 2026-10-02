import XCTest

final class FocusPolicyTests: XCTestCase {
    func testAttentionWinsThenWorkingContextAndRecentCompletion() {
        let now = Date(timeIntervalSince1970: 10_000)
        let working = make("work", .toolUse, now.addingTimeInterval(-1))
        let olderAttention = make("attention", .waitingInput, now.addingTimeInterval(-40))
        let policy = FocusPolicy()
        XCTAssertEqual(policy.focused(sessions: [working, olderAttention], now: now)?.id, "attention")
        XCTAssertEqual(policy.focused(sessions: [working], now: now)?.id, "work")
        XCTAssertNil(policy.focused(sessions: [make("done", .completed, now.addingTimeInterval(-20))], now: now))
        XCTAssertEqual(policy.focused(sessions: [make("done", .completed, now.addingTimeInterval(-2))], now: now)?.id, "done")
    }

    func testExplicitSelectionWinsAndTieBreakIsStable() {
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertEqual(FocusPolicy().focused(
            sessions: [make("z", .thinking, now), make("a", .thinking, now)],
            now: now
        )?.id, "a")
        XCTAssertEqual(FocusPolicy().focused(
            sessions: [make("z", .thinking, now), make("a", .thinking, now)],
            explicitlySelectedID: "z", now: now
        )?.id, "z")
    }

    func testNewWorkingContextTakesFocusOverOlderInterruption() {
        let now = Date(timeIntervalSince1970: 6_000)
        let interrupted = make("stopped", .interrupted, now.addingTimeInterval(-1))
        let working = make("active", .thinking, now)
        XCTAssertEqual(FocusPolicy().focused(sessions: [interrupted, working], now: now)?.id, "active")
        XCTAssertEqual(FocusPolicy().focused(sessions: [interrupted], now: now)?.id, "stopped")
    }

    private func make(_ id: String, _ phase: SessionPhase, _ at: Date) -> CodexSessionState {
        CodexSessionState(id: id, turnID: "turn-\(id)", projectLabel: id, phase: phase,
                          activeTools: [:], lastActivityAt: at, completedTurnIDs: [])
    }
}
