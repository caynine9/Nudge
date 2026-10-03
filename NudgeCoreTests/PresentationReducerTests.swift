import XCTest

final class PresentationReducerTests: XCTestCase {
    func testHoverOpensExpandedAndLeavingClosesIt() {
        let reducer = PresentationReducer()
        var state = PresentationState()
        state.snapshot = snapshot(session: "s", turn: "t", phase: .thinking)
        let entered = reducer.reduce(state, .pointerChanged(true)).state
        XCTAssertEqual(entered.mode, .collapsed)
        let opened = reducer.reduce(entered, .timerElapsed(.hover, generation: entered.hoverGeneration)).state
        XCTAssertEqual(opened.mode, .expanded)

        let exited = reducer.reduce(opened, .pointerChanged(false)).state
        XCTAssertEqual(exited.mode, .expanded)
        let closed = reducer.reduce(exited, .timerElapsed(.collapse, generation: exited.collapseGeneration)).state
        XCTAssertEqual(closed.mode, .collapsed)
    }

    func testRapidPointerReentryRejectsOldCloseAndOpenTimers() {
        let reducer = PresentationReducer()
        var state = PresentationState()
        state.snapshot = snapshot(session: "s", turn: "t", phase: .toolUse)
        let firstEntry = reducer.reduce(state, .pointerChanged(true)).state
        let quickExit = reducer.reduce(firstEntry, .pointerChanged(false)).state
        XCTAssertEqual(reducer.reduce(quickExit, .timerElapsed(.hover, generation: firstEntry.hoverGeneration)).state.mode,
                       .collapsed)

        let reentry = reducer.reduce(quickExit, .pointerChanged(true)).state
        let opened = reducer.reduce(reentry, .timerElapsed(.hover, generation: reentry.hoverGeneration)).state
        let exited = reducer.reduce(opened, .pointerChanged(false)).state
        let returned = reducer.reduce(exited, .pointerChanged(true)).state
        XCTAssertEqual(reducer.reduce(returned, .timerElapsed(.collapse, generation: exited.collapseGeneration)).state.mode,
                       .expanded)
    }

    func testClickExpansionDoesNotPinPanelAfterPointerLeaves() {
        let reducer = PresentationReducer()
        var state = PresentationState()
        state.snapshot = snapshot(session: "s", turn: "t", phase: .thinking)
        let entered = reducer.reduce(state, .pointerChanged(true)).state
        let clicked = reducer.reduce(entered, .toggleExpanded).state
        XCTAssertEqual(clicked.mode, .expanded)
        let exited = reducer.reduce(clicked, .pointerChanged(false)).state
        XCTAssertEqual(reducer.reduce(exited, .timerElapsed(.collapse, generation: exited.collapseGeneration)).state.mode,
                       .collapsed)

        let escaped = reducer.reduce(clicked, .collapse).state
        XCTAssertEqual(reducer.reduce(escaped, .timerElapsed(.hover, generation: entered.hoverGeneration)).state.mode,
                       .collapsed)
    }

    func testLeavingExpandedAttentionListPreservesUnansweredRequest() {
        let reducer = PresentationReducer()
        var state = PresentationState()
        state.snapshot = snapshot(session: "s", turn: "t", phase: .waitingInput)
        state.pointerInside = true
        let listed = reducer.reduce(state, .toggleSessionList).state
        let exited = reducer.reduce(listed, .pointerChanged(false)).state
        let closed = reducer.reduce(exited, .timerElapsed(.collapse, generation: exited.collapseGeneration)).state
        XCTAssertEqual(closed.mode, .attention)
        XCTAssertEqual(closed.snapshot, state.snapshot)
        XCTAssertFalse(closed.showsSessionList)
    }

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

    func testReturningToPreviouslyCompletedFocusDoesNotReplayCardOrCelebration() {
        let reducer = PresentationReducer()
        var state = PresentationState()
        let first = reducer.reduce(state, .snapshotChanged(snapshot(session: "A", turn: "one", phase: .completed)))
        state = first.state
        XCTAssertEqual(first.effects.filter { if case .celebrate = $0 { return true }; return false }.count, 1)

        state = reducer.reduce(state, .snapshotChanged(snapshot(session: "B", turn: "two", phase: .completed))).state
        let returnedToFirst = reducer.reduce(state, .snapshotChanged(snapshot(session: "A", turn: "one", phase: .completed)))
        XCTAssertNil(returnedToFirst.state.transientPhase)
        XCTAssertFalse(returnedToFirst.effects.contains { if case .celebrate = $0 { return true }; return false })
        XCTAssertTrue(returnedToFirst.effects.contains { if case .cancel(.transient) = $0 { return true }; return false })
    }

    func testCompletionDuringSleepIsConsumedWithoutReplayAfterWake() {
        let reducer = PresentationReducer()
        var sleeping = reducer.reduce(PresentationState(), .sleep).state
        let completed = reducer.reduce(sleeping, .snapshotChanged(snapshot(session: "A", turn: "one", phase: .completed)))
        sleeping = completed.state
        XCTAssertTrue(sleeping.isSleeping)
        XCTAssertNil(sleeping.transientPhase)
        XCTAssertFalse(completed.effects.contains { if case .celebrate = $0 { return true }; return false })

        let woke = reducer.reduce(sleeping, .wake)
        let repeated = reducer.reduce(woke.state, .snapshotChanged(woke.state.snapshot))
        XCTAssertFalse(repeated.effects.contains { if case .celebrate = $0 { return true }; return false })
        XCTAssertNil(repeated.state.transientPhase)
    }

    func testDelayedPreWakeCompletionIsSuppressedButNewPostWakeCompletionPlays() {
        let reducer = PresentationReducer()
        let sleeping = reducer.reduce(PresentationState(), .sleep).state
        let wakeAt = Date(timeIntervalSince1970: 100)
        let woke = reducer.reduce(sleeping, .wake, now: wakeAt).state

        let deliveredLate = reducer.reduce(woke, .snapshotChanged(
            snapshot(session: "old", turn: "during-sleep", phase: .completed, observedAt: wakeAt.addingTimeInterval(-0.2))
        ))
        XCTAssertFalse(deliveredLate.effects.contains { if case .celebrate = $0 { return true }; return false })
        XCTAssertNil(deliveredLate.state.transientPhase)

        let newCompletion = reducer.reduce(deliveredLate.state, .snapshotChanged(
            snapshot(session: "new", turn: "after-wake", phase: .completed, observedAt: wakeAt.addingTimeInterval(1))
        ))
        XCTAssertEqual(newCompletion.effects.filter { if case .celebrate = $0 { return true }; return false }.count, 1)
    }

    func testLiveAttentionCanShowSessionListWithoutClearingPendingState() {
        let reducer = PresentationReducer()
        var attention = snapshot(session: "s", turn: "t", phase: .waitingInput)
        attention = ActivitySnapshot(sessionID: attention.sessionID, turnID: attention.turnID,
            projectLabel: attention.projectLabel, phase: attention.phase, currentTool: nil,
            activityLabel: attention.activityLabel, detail: attention.detail,
            pendingInteractions: [PendingInteraction(id: "question-1", kind: .question,
                                                      toolCallID: "tool-1", preview: "Question?")])
        let waiting = reducer.reduce(PresentationState(), .snapshotChanged(attention)).state
        XCTAssertEqual(waiting.mode, .attention)

        let expanded = reducer.reduce(waiting, .toggleSessionList).state
        XCTAssertEqual(expanded.mode, .expanded)
        XCTAssertTrue(expanded.showsSessionList)
        XCTAssertEqual(expanded.snapshot.pendingInteraction?.id, "question-1")

        let returned = reducer.reduce(expanded, .collapse).state
        XCTAssertEqual(returned.mode, .attention)
        XCTAssertFalse(returned.showsSessionList)
        XCTAssertEqual(returned.snapshot.pendingInteraction?.id, "question-1")
    }

    private func snapshot(session: String, turn: String, phase: SessionPhase, observedAt: Date = Date()) -> ActivitySnapshot {
        ActivitySnapshot(sessionID: session, turnID: turn, projectLabel: "Test", phase: phase,
                         currentTool: nil, activityLabel: phase.title, detail: phase.detail, observedAt: observedAt)
    }
}
