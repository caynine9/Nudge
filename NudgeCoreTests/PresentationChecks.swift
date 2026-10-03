// Hermetic reducer scenarios. Compile with NudgeModels, PresentationReducer and PlaygroundScenario.
@main
struct PresentationChecks {
    static func main() {
        let reducer = PresentationReducer()
        var waiting = PresentationState()
        waiting.snapshot = PlaygroundScenario.snapshot(turn: 1, phase: .waitingInput)
        waiting.pointerInside = true
        waiting.isExpanded = true
        let receipt = InteractionFeedback(label: "Production", kind: .selected)
        let progress = PlaygroundScenario.snapshot(turn: 1, phase: .toolUse)

        // Opening/collapsing UI is not a response; stale timers cannot clear the question.
        let collapsed = reducer.reduce(waiting, .collapse).state
        precondition(collapsed.mode == .attention && collapsed.snapshot.phase == .waitingInput)
        let quiet = reducer.reduce(collapsed, .timerElapsed(.collapse, generation: collapsed.collapseGeneration)).state
        precondition(quiet.mode == .attention)

        // A decision for another turn must not resolve this interaction.
        let wrongTurn = PlaygroundScenario.snapshot(turn: 2, phase: .toolUse)
        precondition(reducer.reduce(waiting, .previewInteractionResolved(wrongTurn, receipt)).state == waiting)

        let resolved = reducer.reduce(waiting, .previewInteractionResolved(progress, receipt))
        precondition(resolved.state.mode == .confirmation && !resolved.state.isExpanded)
        precondition(resolved.state.snapshot.phase == .toolUse)
        precondition(!resolved.effects.contains { if case .celebrate = $0 { return true }; return false })
        precondition(resolved.state.consumedCompletionTurnID == nil, "Decision feedback is not turn completion")
        // Duplicate clicks after progress cannot replay the receipt.
        precondition(reducer.reduce(resolved.state, .previewInteractionResolved(progress, receipt)).state == resolved.state)
        let expired = reducer.reduce(resolved.state, .timerElapsed(.feedback, generation: resolved.state.feedbackGeneration)).state
        precondition(expired.mode == .collapsed && expired.feedback == nil)

        // New attention invalidates the receipt; its old timeout must not remove the new question.
        let freshQuestion = reducer.reduce(resolved.state, .snapshotChanged(PlaygroundScenario.snapshot(turn: 2, phase: .waitingInput))).state
        let stale = reducer.reduce(freshQuestion, .timerElapsed(.feedback, generation: resolved.state.feedbackGeneration)).state
        precondition(stale == freshQuestion && stale.mode == .attention)

        let sleeping = reducer.reduce(resolved.state, .sleep).state
        let awake = reducer.reduce(sleeping, .wake)
        precondition(awake.state.feedback == nil && awake.state.mode == .collapsed)
        precondition(awake.effects.allSatisfy { if case .celebrate = $0 { return false }; return true })

        var permission = waiting
        permission.snapshot = PlaygroundScenario.snapshot(turn: 1, phase: .waitingPermission)
        let denied = reducer.reduce(permission, .previewInteractionResolved(
            PlaygroundScenario.snapshot(turn: 1, phase: .interrupted), .init(label: "Denied", kind: .denied)))
        precondition(denied.state.snapshot.phase == .interrupted && denied.state.mode == .confirmation)
        precondition(denied.state.consumedCompletionTurnID == nil)

        var idle = PresentationState()
        idle.snapshot = PlaygroundScenario.snapshot(turn: 1, phase: .thinking)
        let done = reducer.reduce(idle, .snapshotChanged(PlaygroundScenario.snapshot(turn: 1, phase: .completed)))
        precondition(done.effects.contains { if case .celebrate = $0 { return true }; return false })
        precondition(reducer.reduce(done.state, .snapshotChanged(done.state.snapshot)).effects.isEmpty)
        print("Presentation feedback, attention, stale timer, sleep and completion fixture checks passed")
    }
}
