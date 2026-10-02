import Foundation

struct CodexSessionState: Equatable, Sendable {
    let id: String
    var turnID: String?
    var projectLabel: String
    var metadataUpdatedAt: Date? = nil
    var phase: SessionPhase
    var activeTools: [String: ToolActivity]
    var finishedToolIDs: [String] = []
    var pendingInteraction: PendingInteraction? = nil
    var lastActivityAt: Date
    var completedTurnIDs: [String]
    var retiredTurnIDs: [String] = []

    var presentationPhase: SessionPhase {
        pendingInteraction.map { $0.kind == .permission ? .waitingPermission : .waitingInput } ?? phase
    }

    var snapshot: ActivitySnapshot {
        let currentTool = activeTools.sorted(by: { $0.key < $1.key }).first?.value
        let displayPhase = presentationPhase
        let detail: String
        switch displayPhase {
        case .toolUse: detail = "Using a local Codex tool."
        case .completed: detail = "Turn finished."
        case .waitingPermission: detail = "Codex needs permission."
        case .waitingInput: detail = "Codex has a question."
        default: detail = displayPhase.detail
        }
        return ActivitySnapshot(
            sessionID: id,
            turnID: turnID ?? "",
            projectLabel: projectLabel,
            phase: displayPhase,
            currentTool: displayPhase.isAttention ? nil : currentTool,
            activityLabel: displayPhase.isAttention ? displayPhase.title : (currentTool?.summary ?? displayPhase.title),
            detail: detail,
            observedAt: lastActivityAt
        )
    }

    var isRetainable: Bool {
        !phase.isTerminal && phase != .idle || !activeTools.isEmpty || pendingInteraction != nil
    }
}

struct SessionReducer {
    static let retainedTurnLimit = 64
    static let retainedToolLimit = 512

    struct Result: Equatable, Sendable {
        var session: CodexSessionState?
        var didCompleteTurn = false
        var didInterruptTurn = false
        var didMakeProgress = false
    }

    func enrichMetadata(_ previous: CodexSessionState?, event: NudgeEvent) -> CodexSessionState? {
        guard var session = previous, session.id == event.sessionID,
              let label = metadataLabel(for: event), !label.isEmpty, label != "Codex",
              session.metadataUpdatedAt.map({ event.observedAt >= $0 }) ?? true else { return previous }
        session.projectLabel = label
        session.metadataUpdatedAt = event.observedAt
        return session
    }

    func reduce(_ previous: CodexSessionState?, event: NudgeEvent) -> Result {
        var session = previous ?? CodexSessionState(
            id: event.sessionID,
            turnID: nil,
            projectLabel: "Codex",
            metadataUpdatedAt: nil,
            phase: .discovered,
            activeTools: [:],
            lastActivityAt: event.observedAt,
            completedTurnIDs: []
        )
        guard session.id == event.sessionID else { return Result(session: previous) }

        // Turn identifiers are opaque. A retained terminal tombstone is the only
        // reliable way to reject a delayed event from an older turn.
        if let incoming = event.turnID, incoming != session.turnID,
           session.retiredTurnIDs.contains(incoming) {
            return Result(session: previous)
        }

        var result = Result(session: session)
        if let enriched = enrichMetadata(session, event: event) { session = enriched }
        result.session = session

        switch event.kind {
        case .sessionStarted:
            if session.phase == .discovered {
                session.phase = .idle
                result.didMakeProgress = true
            }

        case .promptSubmitted:
            guard let incoming = validTurnID(event.turnID), !session.retiredTurnIDs.contains(incoming) else {
                return Result(session: previous)
            }
            if session.turnID == incoming {
                // A duplicate prompt cannot reopen or reset an in-progress/terminal turn.
                if session.phase != .discovered && session.phase != .idle { return result }
            } else {
                if let oldTurn = session.turnID { retireTurn(oldTurn, in: &session) }
                startTurn(incoming, in: &session)
            }
            session.phase = .thinking
            result.didMakeProgress = true

        case let .toolStarted(id, activity):
            guard !id.isEmpty, let incoming = validTurnID(event.turnID),
                  prepareProgressTurn(incoming, session: &session) else { return Result(session: previous) }
            guard !session.finishedToolIDs.contains(id) else { return Result(session: previous) }
            if let existing = session.activeTools[id] {
                // A repeated PreToolUse may enrich the normalized tool label, but
                // must not advance activity time or create another transition.
                if existing != activity { session.activeTools[id] = activity }
                result.session = session
                return result
            }
            session.activeTools[id] = activity
            session.phase = .toolUse
            result.didMakeProgress = true

        case let .toolFinished(id):
            guard !id.isEmpty, let incoming = validTurnID(event.turnID),
                  prepareProgressTurn(incoming, session: &session) else { return Result(session: previous) }
            guard !session.finishedToolIDs.contains(id) else { return Result(session: previous) }
            session.activeTools.removeValue(forKey: id)
            appendUnique(id, to: &session.finishedToolIDs)
            if session.finishedToolIDs.count > Self.retainedToolLimit {
                session.finishedToolIDs.removeFirst(session.finishedToolIDs.count - Self.retainedToolLimit)
            }
            if session.pendingInteraction?.toolCallID == id { session.pendingInteraction = nil }
            updateWorkingPhase(&session)
            result.didMakeProgress = true

        case let .pendingInteraction(interaction):
            guard let incoming = validTurnID(event.turnID),
                  prepareProgressTurn(incoming, session: &session) else { return Result(session: previous) }
            if session.pendingInteraction == interaction { return result }
            session.pendingInteraction = interaction
            session.phase = .thinking
            result.didMakeProgress = true

        case let .interactionResolved(id):
            guard let pending = session.pendingInteraction, pending.id == id,
                  event.turnID == nil || event.turnID == session.turnID else { return Result(session: previous) }
            session.pendingInteraction = nil
            updateWorkingPhase(&session)
            result.didMakeProgress = true

        case .lifecycleEnded:
            if let incoming = event.turnID, incoming != session.turnID { return Result(session: previous) }
            guard session.phase != .ended || session.pendingInteraction != nil || !session.activeTools.isEmpty else {
                return Result(session: previous)
            }
            if let turnID = session.turnID { retireTurn(turnID, in: &session) }
            session.pendingInteraction = nil
            session.activeTools.removeAll()
            session.phase = .ended
            result.didMakeProgress = true

        case .turnFinished:
            guard let incoming = validTurnID(event.turnID),
                  prepareTerminalTurn(incoming, session: &session),
                  session.phase != .completed else { return Result(session: previous) }
            session.activeTools.removeAll()
            session.finishedToolIDs.removeAll()
            session.pendingInteraction = nil
            session.phase = .completed
            appendUnique(incoming, to: &session.completedTurnIDs)
            retireTurn(incoming, in: &session)
            result.didCompleteTurn = true
            result.didMakeProgress = true

        case .interrupted:
            guard let incoming = validTurnID(event.turnID),
                  prepareTerminalTurn(incoming, session: &session),
                  session.phase != .interrupted && session.phase != .completed && session.phase != .failed else {
                return Result(session: previous)
            }
            session.activeTools.removeAll()
            session.finishedToolIDs.removeAll()
            session.pendingInteraction = nil
            session.phase = .interrupted
            retireTurn(incoming, in: &session)
            result.didInterruptTurn = true
            result.didMakeProgress = true
        }

        if result.didMakeProgress {
            session.lastActivityAt = max(session.lastActivityAt, event.observedAt)
        }
        result.session = session
        return result
    }

    private func validTurnID(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func metadataLabel(for event: NudgeEvent) -> String? {
        if let label = event.projectLabel { return label }
        if case let .sessionStarted(label) = event.kind { return label }
        return nil
    }

    private func prepareProgressTurn(_ incoming: String, session: inout CodexSessionState) -> Bool {
        guard !session.retiredTurnIDs.contains(incoming) else { return false }
        guard let current = session.turnID else {
            startTurn(incoming, in: &session)
            return true
        }
        guard current != incoming else { return !session.phase.isTerminal }
        // A different tool turn is a safe resume anchor only once the old turn
        // is terminal. While it is active, ignore the ambiguous out-of-order event.
        guard session.phase.isTerminal else { return false }
        retireCurrentTurn(&session)
        startTurn(incoming, in: &session)
        return true
    }

    private func prepareTerminalTurn(_ incoming: String, session: inout CodexSessionState) -> Bool {
        guard !session.retiredTurnIDs.contains(incoming) else { return false }
        guard let current = session.turnID else {
            startTurn(incoming, in: &session)
            return true
        }
        guard current != incoming else { return !session.phase.isTerminal }
        guard session.phase.isTerminal else { return false }
        retireCurrentTurn(&session)
        startTurn(incoming, in: &session)
        return true
    }

    private func startTurn(_ id: String, in session: inout CodexSessionState) {
        session.turnID = id
        session.activeTools.removeAll()
        session.finishedToolIDs.removeAll()
        session.pendingInteraction = nil
        session.phase = .thinking
    }

    private func updateWorkingPhase(_ session: inout CodexSessionState) {
        if session.pendingInteraction != nil { session.phase = .thinking }
        else { session.phase = session.activeTools.isEmpty ? .thinking : .toolUse }
    }

    private func retireCurrentTurn(_ session: inout CodexSessionState) {
        guard let turnID = session.turnID, session.phase.isTerminal else { return }
        retireTurn(turnID, in: &session)
    }

    private func retireTurn(_ turnID: String, in session: inout CodexSessionState) {
        appendUnique(turnID, to: &session.retiredTurnIDs)
    }

    private func appendUnique(_ value: String, to values: inout [String]) {
        values.removeAll { $0 == value }
        values.append(value)
        if values.count > Self.retainedTurnLimit { values.removeFirst(values.count - Self.retainedTurnLimit) }
    }
}
