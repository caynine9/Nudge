import Foundation

struct CodexSessionState: Equatable, Sendable {
    let id: String
    var turnID: String?
    var projectLabel: String
    var metadataUpdatedAt: Date? = nil
    var phase: SessionPhase
    var activeTools: [String: ToolActivity]
    var activeToolNames: [String: String] = [:]
    var activeToolOrder: [String] = []
    var finishedToolIDs: [String] = []
    var pendingInteractions: [PendingInteraction] = []
    var pendingInteractionOverflowed = false
    var resolvedInteractionIDs: [String] = []
    var pendingInteractionStartedAt: Date? = nil
    var lastActivityAt: Date
    var turnStartedAt: Date? = nil
    var completedTurnIDs: [String]
    var retiredTurnIDs: [String] = []

    static let retainedInteractionLimit = 16

    var pendingInteraction: PendingInteraction? {
        get { pendingInteractions.first }
        set {
            if let newValue {
                if let index = pendingInteractions.firstIndex(where: { $0.id == newValue.id }) {
                    pendingInteractions[index] = newValue
                } else if pendingInteractions.count < Self.retainedInteractionLimit {
                    pendingInteractions.append(newValue)
                } else {
                    pendingInteractionOverflowed = true
                }
            } else {
                pendingInteractions.removeAll()
                pendingInteractionOverflowed = false
            }
        }
    }

    var presentationPhase: SessionPhase {
        if let pendingInteraction { return pendingInteraction.kind == .permission ? .waitingPermission : .waitingInput }
        if pendingInteractionOverflowed { return .waitingInput }
        return phase
    }

    var snapshot: ActivitySnapshot {
        let currentTool = activeToolOrder.last.flatMap { activeTools[$0] }
        let displayPhase = presentationPhase
        let detail: String
        switch displayPhase {
        case .toolUse: detail = currentTool?.summary ?? "Working"
        case .completed: detail = "Turn finished."
        case .waitingPermission: detail = "Codex needs permission."
        case .waitingInput: detail = pendingInteractionOverflowed && pendingInteractions.isEmpty
            ? "More Codex requests need attention." : "Codex has a question."
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
            observedAt: lastActivityAt,
            turnStartedAt: turnStartedAt,
            pendingInteractions: pendingInteractions,
            pendingInteractionOverflowed: pendingInteractionOverflowed
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
            activeToolNames: [:],
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
                startTurn(incoming, at: event.observedAt, in: &session)
            }
            session.phase = .thinking
            result.didMakeProgress = true

        case let .toolStarted(id, activity):
            guard !id.isEmpty, let incoming = validTurnID(event.turnID),
                  prepareProgressTurn(incoming, at: event.observedAt, session: &session) else { return Result(session: previous) }
            guard !session.finishedToolIDs.contains(id) else { return Result(session: previous) }
            if let existing = session.activeTools[id] {
                // A repeated PreToolUse may enrich the normalized tool label, but
                // must not advance activity time or create another transition.
                if existing != activity { session.activeTools[id] = activity }
                result.session = session
                return result
            }
            session.activeTools[id] = activity
            if let toolName = event.toolName { session.activeToolNames[id] = toolName }
            session.activeToolOrder.append(id)
            session.phase = .toolUse
            bindPendingPermissionToUniqueTool(in: &session, at: event.observedAt)
            if let interaction = event.interaction {
                register(interaction, at: event.observedAt, in: &session)
            }
            result.didMakeProgress = true

        case let .toolFinished(id):
            guard !id.isEmpty, let incoming = validTurnID(event.turnID),
                  prepareProgressTurn(incoming, at: event.observedAt, session: &session) else { return Result(session: previous) }
            guard !session.finishedToolIDs.contains(id) else { return Result(session: previous) }
            let toolName = event.toolName ?? session.activeToolNames[id]
            let resolvable = session.pendingInteractions.filter { pending in
                if pending.toolCallID == id { return true }
                return pending.kind == .permission && pending.toolCallID == nil
                    && !pending.permissionCorrelationWasAmbiguous
                    && pending.toolName == toolName
                    && session.activeTools.filter { session.activeToolNames[$0.key] == toolName }.count == 1
            }
            for pending in resolvable { appendResolved(pending.id, in: &session) }
            session.pendingInteractions.removeAll { resolved in resolvable.contains { $0.id == resolved.id } }
            session.pendingInteractionStartedAt = session.pendingInteractions.first?.createdAt
            session.activeTools.removeValue(forKey: id)
            session.activeToolNames.removeValue(forKey: id)
            session.activeToolOrder.removeAll { $0 == id }
            appendUnique(id, to: &session.finishedToolIDs)
            if session.finishedToolIDs.count > Self.retainedToolLimit {
                session.finishedToolIDs.removeFirst(session.finishedToolIDs.count - Self.retainedToolLimit)
            }
            updateWorkingPhase(&session)
            result.didMakeProgress = true

        case let .pendingInteraction(interaction):
            guard let incoming = validTurnID(event.turnID),
                  prepareProgressTurn(incoming, at: event.observedAt, session: &session) else { return Result(session: previous) }
            guard !session.resolvedInteractionIDs.contains(interaction.id),
                  interaction.toolCallID.map({ !session.finishedToolIDs.contains($0) }) ?? true else { return result }
            register(interaction, at: event.observedAt, in: &session)
            session.phase = .thinking
            result.didMakeProgress = true

        case let .interactionResolved(id):
            guard session.pendingInteractions.contains(where: { $0.id == id }),
                  event.turnID == nil || event.turnID == session.turnID else { return Result(session: previous) }
            session.pendingInteractions.removeAll { $0.id == id }
            appendResolved(id, in: &session)
            session.pendingInteractionStartedAt = session.pendingInteractions.first?.createdAt
            updateWorkingPhase(&session)
            result.didMakeProgress = true

        case .lifecycleEnded:
            if let incoming = event.turnID, incoming != session.turnID { return Result(session: previous) }
            guard session.phase != .ended || session.pendingInteraction != nil || !session.activeTools.isEmpty else {
                return Result(session: previous)
            }
            if let turnID = session.turnID { retireTurn(turnID, in: &session) }
            session.pendingInteraction = nil
            session.pendingInteractionStartedAt = nil
            session.activeTools.removeAll()
            session.activeToolNames.removeAll()
            session.activeToolOrder.removeAll()
            session.phase = .ended
            result.didMakeProgress = true

        case .turnFinished:
            guard let incoming = validTurnID(event.turnID),
                  prepareTerminalTurn(incoming, at: event.observedAt, session: &session),
                  session.phase != .completed else { return Result(session: previous) }
            session.activeTools.removeAll()
            session.activeToolNames.removeAll()
            session.activeToolOrder.removeAll()
            session.finishedToolIDs.removeAll()
            session.pendingInteraction = nil
            session.pendingInteractionStartedAt = nil
            session.resolvedInteractionIDs.removeAll()
            session.phase = .completed
            appendUnique(incoming, to: &session.completedTurnIDs)
            retireTurn(incoming, in: &session)
            result.didCompleteTurn = true
            result.didMakeProgress = true

        case .interrupted:
            guard let incoming = validTurnID(event.turnID),
                  prepareTerminalTurn(incoming, at: event.observedAt, session: &session),
                  session.phase != .interrupted && session.phase != .completed && session.phase != .failed else {
                return Result(session: previous)
            }
            session.activeTools.removeAll()
            session.activeToolNames.removeAll()
            session.activeToolOrder.removeAll()
            session.finishedToolIDs.removeAll()
            session.pendingInteraction = nil
            session.pendingInteractionStartedAt = nil
            session.resolvedInteractionIDs.removeAll()
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

    private func prepareProgressTurn(_ incoming: String, at date: Date, session: inout CodexSessionState) -> Bool {
        guard !session.retiredTurnIDs.contains(incoming) else { return false }
        guard let current = session.turnID else {
            startTurn(incoming, at: date, in: &session)
            return true
        }
        guard current != incoming else { return !session.phase.isTerminal }
        // A different tool turn is a safe resume anchor only once the old turn
        // is terminal. While it is active, ignore the ambiguous out-of-order event.
        guard session.phase.isTerminal else { return false }
        retireCurrentTurn(&session)
        startTurn(incoming, at: date, in: &session)
        return true
    }

    private func prepareTerminalTurn(_ incoming: String, at date: Date, session: inout CodexSessionState) -> Bool {
        guard !session.retiredTurnIDs.contains(incoming) else { return false }
        guard let current = session.turnID else {
            startTurn(incoming, at: date, in: &session)
            return true
        }
        guard current != incoming else { return !session.phase.isTerminal }
        guard session.phase.isTerminal else { return false }
        retireCurrentTurn(&session)
        startTurn(incoming, at: date, in: &session)
        return true
    }

    private func startTurn(_ id: String, at date: Date, in session: inout CodexSessionState) {
        session.turnID = id
        session.turnStartedAt = date
        session.activeTools.removeAll()
        session.activeToolNames.removeAll()
        session.activeToolOrder.removeAll()
        session.finishedToolIDs.removeAll()
        session.pendingInteraction = nil
        session.pendingInteractionStartedAt = nil
        session.resolvedInteractionIDs.removeAll()
        session.phase = .thinking
    }

    private func updateWorkingPhase(_ session: inout CodexSessionState) {
        if !session.pendingInteractions.isEmpty || session.pendingInteractionOverflowed { session.phase = .thinking }
        else { session.phase = session.activeTools.isEmpty ? .thinking : .toolUse }
    }

    private func register(_ interaction: PendingInteraction, at date: Date, in session: inout CodexSessionState) {
        var value = interaction
        if value.kind == .permission, value.toolCallID == nil, !value.permissionCorrelationWasAmbiguous {
            let matching = session.activeTools.keys.filter { session.activeToolNames[$0] == value.toolName }
            if matching.count == 1 { value.toolCallID = matching[0] }
            else if matching.count > 1 { value.permissionCorrelationWasAmbiguous = true }
        }
        if let index = session.pendingInteractions.firstIndex(where: { $0.id == value.id }) {
            value.createdAt = session.pendingInteractions[index].createdAt ?? date
            session.pendingInteractions[index] = value
        } else {
            value.createdAt = date
            session.pendingInteraction = value
        }
        session.pendingInteractionStartedAt = session.pendingInteractions.first?.createdAt ?? date
    }

    private func bindPendingPermissionToUniqueTool(in session: inout CodexSessionState, at date: Date) {
        for index in session.pendingInteractions.indices where session.pendingInteractions[index].kind == .permission
            && session.pendingInteractions[index].toolCallID == nil
            && !session.pendingInteractions[index].permissionCorrelationWasAmbiguous {
            let pending = session.pendingInteractions[index]
            let matching = session.activeTools.keys.filter { session.activeToolNames[$0] == pending.toolName }
            if matching.count == 1 {
                session.pendingInteractions[index].toolCallID = matching[0]
                session.pendingInteractions[index].createdAt = pending.createdAt ?? date
            } else if matching.count > 1 {
                session.pendingInteractions[index].permissionCorrelationWasAmbiguous = true
            }
        }
    }

    private func appendResolved(_ id: String, in session: inout CodexSessionState) {
        guard !id.isEmpty, !session.resolvedInteractionIDs.contains(id) else { return }
        session.resolvedInteractionIDs.append(id)
        if session.resolvedInteractionIDs.count > Self.retainedTurnLimit {
            session.resolvedInteractionIDs.removeFirst(session.resolvedInteractionIDs.count - Self.retainedTurnLimit)
        }
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
