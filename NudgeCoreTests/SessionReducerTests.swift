import XCTest

final class SessionReducerTests: XCTestCase {
    private let reducer = SessionReducer()
    private let origin = Date(timeIntervalSince1970: 1_000)

    func testToolProgressBeforeSessionStartCreatesAndEnrichesPlaceholder() {
        let tool = event("PreToolUse", session: "s", turn: "1", at: 1_001,
                         kind: .toolStarted(id: "tool-a", activity: .init(category: .shell, summary: "Running command", symbol: "terminal")))
        var state = reducer.reduce(nil, event: tool).session!
        XCTAssertEqual(state.phase, .toolUse)
        let lateStart = event("SessionStart", session: "s", turn: nil, at: 1_002,
                              kind: .sessionStarted(projectLabel: "Sandbox"))
        state = reducer.reduce(state, event: lateStart).session!
        XCTAssertEqual(state.phase, .toolUse)
        XCTAssertEqual(state.projectLabel, "Sandbox")

        let observedProject = event("PreToolUse", session: "s", turn: "1", at: 1_003,
            kind: .toolStarted(id: "tool-b", activity: .init(category: .shell, summary: "Running command", symbol: "terminal")),
            projectLabel: "Resumed Repo")
        state = reducer.reduce(state, event: observedProject).session!
        XCTAssertEqual(state.projectLabel, "Resumed Repo")
    }

    func testConcurrentToolsRemainActiveUntilEachCallFinishes() {
        var state = reducer.reduce(nil, event: event("UserPromptSubmit", session: "s", turn: "1", at: 1_001, kind: .promptSubmitted)).session!
        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: "1", at: 1_002,
            kind: .toolStarted(id: "a", activity: .init(category: .shell, summary: "Running command", symbol: "terminal")))).session!
        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: "1", at: 1_003,
            kind: .toolStarted(id: "b", activity: .init(category: .edit, summary: "Editing files", symbol: "pencil")))).session!
        state = reducer.reduce(state, event: event("PostToolUse", session: "s", turn: "1", at: 1_004,
            kind: .toolFinished(id: "a"))).session!
        XCTAssertEqual(state.phase, .toolUse)
        XCTAssertEqual(state.activeTools.count, 1)
        state = reducer.reduce(state, event: event("PostToolUse", session: "s", turn: "1", at: 1_005,
            kind: .toolFinished(id: "b"))).session!
        XCTAssertEqual(state.phase, .thinking)
        XCTAssertTrue(state.activeTools.isEmpty)
    }

    func testDuplicateStopCompletesOnceAndInterruptNeverCompletes() {
        let running = reducer.reduce(nil, event: event("UserPromptSubmit", session: "s", turn: "1", at: 1_001, kind: .promptSubmitted)).session!
        let stop = event("Stop", session: "s", turn: "1", at: 1_002, kind: .turnFinished)
        let first = reducer.reduce(running, event: stop)
        XCTAssertTrue(first.didCompleteTurn)
        XCTAssertFalse(reducer.reduce(first.session, event: stop).didCompleteTurn)
        let lateDuplicatePrompt = reducer.reduce(first.session, event: event("UserPromptSubmit", session: "s", turn: "1", at: 1_003, kind: .promptSubmitted))
        XCTAssertEqual(lateDuplicatePrompt.session?.phase, .completed)

        let interrupted = reducer.reduce(running, event: event("Interrupt", session: "s", turn: "1", at: 1_003, kind: .interrupted))
        XCTAssertTrue(interrupted.didInterruptTurn)
        XCTAssertFalse(reducer.reduce(interrupted.session, event: stop).didCompleteTurn)
        XCTAssertEqual(interrupted.session?.phase, .interrupted)
    }

    func testDifferentToolTurnCannotReplaceCurrentActiveTurnWithoutAnchor() {
        var state = reducer.reduce(nil, event: event("UserPromptSubmit", session: "s", turn: "2", at: 1_010, kind: .promptSubmitted)).session!
        let late = event("PreToolUse", session: "s", turn: "1", at: 1_011,
                         kind: .toolStarted(id: "old", activity: .init(category: .shell, summary: "Running command", symbol: "terminal")))
        state = reducer.reduce(state, event: late).session!
        XCTAssertEqual(state.turnID, "2")
        XCTAssertEqual(state.phase, .thinking)
    }

    func testOpaqueTurnIDsResumeFromToolAfterTerminalAndRetiredEventsStayIgnored() {
        let oldTurn = "turn:old/uuid"
        let newTurn = "turn:new/uuid"
        var state = reducer.reduce(nil, event: event("PreToolUse", session: "s", turn: oldTurn, at: 1_001,
            kind: .toolStarted(id: "old-tool", activity: shell))).session!
        let completed = reducer.reduce(state, event: event("Stop", session: "s", turn: oldTurn, at: 1_002, kind: .turnFinished))
        XCTAssertTrue(completed.didCompleteTurn)
        state = completed.session!

        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: newTurn, at: 1_003,
            kind: .toolStarted(id: "new-tool", activity: shell))).session!
        XCTAssertEqual(state.turnID, newTurn)
        XCTAssertEqual(state.phase, .toolUse)

        let delayedStart = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: oldTurn, at: 1_004,
            kind: .toolStarted(id: "late-tool", activity: shell)))
        let delayedStop = reducer.reduce(state, event: event("Stop", session: "s", turn: oldTurn, at: 1_005,
            kind: .turnFinished))
        XCTAssertEqual(delayedStart.session, state)
        XCTAssertEqual(delayedStop.session, state)
    }

    func testPostToolCanMaterializeResumedTurnAndLatePreDoesNotReopen() {
        let turn = "non-numeric:turn"
        var state = reducer.reduce(nil, event: event("PostToolUse", session: "s", turn: turn, at: 1_001,
            kind: .toolFinished(id: "tool-1"))).session!
        XCTAssertEqual(state.turnID, turn)
        XCTAssertEqual(state.phase, .thinking)

        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: turn, at: 1_002,
            kind: .toolStarted(id: "tool-1", activity: shell))).session!
        XCTAssertEqual(state.phase, .thinking)
        XCTAssertTrue(state.activeTools.isEmpty)
    }

    func testPendingInteractionOnlyClearsForMatchingProgress() {
        var state = reducer.reduce(nil, event: event("UserPromptSubmit", session: "s", turn: "q", at: 1_001,
            kind: .promptSubmitted)).session!
        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: "q", at: 1_002,
            kind: .toolStarted(id: "request", activity: shell))).session!
        let pending = PendingInteraction(id: "request-1", kind: .question, toolCallID: "request")
        state = reducer.reduce(state, event: event("Question", session: "s", turn: "q", at: 1_003,
            kind: .pendingInteraction(pending))).session!
        XCTAssertEqual(state.snapshot.phase, .waitingInput)

        state = reducer.reduce(state, event: event("PostToolUse", session: "s", turn: "q", at: 1_004,
            kind: .toolFinished(id: "unrelated"))).session!
        XCTAssertEqual(state.pendingInteraction, pending)
        state = reducer.reduce(state, event: event("Resolved", session: "s", turn: "q", at: 1_005,
            kind: .interactionResolved(id: "other-request"))).session!
        XCTAssertEqual(state.pendingInteraction, pending)

        state = reducer.reduce(state, event: event("PostToolUse", session: "s", turn: "q", at: 1_006,
            kind: .toolFinished(id: "request"))).session!
        XCTAssertNil(state.pendingInteraction)
        XCTAssertEqual(state.phase, .thinking)
    }

    func testDuplicateToolStartDoesNotAdvanceActivityTimeOrReopenFinishedTool() {
        var state = reducer.reduce(nil, event: event("PreToolUse", session: "s", turn: "opaque", at: 1_001,
            kind: .toolStarted(id: "tool", activity: shell))).session!
        let initialActivity = state.lastActivityAt
        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: "opaque", at: 1_100,
            kind: .toolStarted(id: "tool", activity: shell))).session!
        XCTAssertEqual(state.lastActivityAt, initialActivity)
        state = reducer.reduce(state, event: event("PostToolUse", session: "s", turn: "opaque", at: 1_101,
            kind: .toolFinished(id: "tool"))).session!
        state = reducer.reduce(state, event: event("PreToolUse", session: "s", turn: "opaque", at: 1_102,
            kind: .toolStarted(id: "tool", activity: shell))).session!
        XCTAssertEqual(state.phase, .thinking)
        XCTAssertTrue(state.activeTools.isEmpty)
    }

    private var shell: ToolActivity {
        .init(category: .shell, summary: "Running command", symbol: "terminal")
    }

    private func event(_ name: String, session: String, turn: String?, at: TimeInterval, kind: NudgeEvent.Kind,
                       projectLabel: String? = nil) -> NudgeEvent {
        NudgeEvent(sessionID: session, turnID: turn, observedAt: origin.addingTimeInterval(at - 1_000),
                   kind: kind, projectLabel: projectLabel)
    }
}
