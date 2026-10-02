import XCTest

final class PresentationReducerTests: XCTestCase {
    func testCompletionIdentityIncludesSessionAndTurn() {
        let reducer = PresentationReducer()
        var state = PresentationState()
        let first = snapshot(session: "one", turn: "same", phase: .thinking)
        state.snapshot = first
        let completedFirst = reducer.reduce(state, .snapshotChanged(snapshot(session: "one", turn: "same", phase: .completed)))
        XCTAssertEqual(completedFirst.effects.filter { if case .celebrate = $0 { return true }; return false }.count, 1)
        XCTAssertTrue(reducer.reduce(completedFirst.state, .snapshotChanged(completedFirst.state.snapshot)).effects.isEmpty)

        let secondSession = snapshot(session: "two", turn: "same", phase: .completed)
        let completedSecond = reducer.reduce(completedFirst.state, .snapshotChanged(secondSession))
        XCTAssertEqual(completedSecond.effects.filter { if case .celebrate = $0 { return true }; return false }.count, 1)
    }

    private func snapshot(session: String, turn: String, phase: SessionPhase) -> ActivitySnapshot {
        ActivitySnapshot(sessionID: session, turnID: turn, projectLabel: "Test", phase: phase,
                         currentTool: nil, activityLabel: phase.title, detail: phase.detail)
    }
}
