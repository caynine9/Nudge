import Foundation

struct CodexSessionState: Equatable, Sendable {
    let id: String
    var turnID: String?
    var projectLabel: String
    var phase: SessionPhase
    var activeTools: [String: ToolActivity]
    var lastActivityAt: Date
    var completedTurnIDs: [String]

    var snapshot: ActivitySnapshot {
        let currentTool = activeTools.sorted(by: { $0.key < $1.key }).first?.value
        let detail: String
        switch phase {
        case .toolUse: detail = "Using a local Codex tool."
        case .completed: detail = "Turn finished."
        default: detail = phase.detail
        }
        return ActivitySnapshot(
            sessionID: id,
            turnID: turnID ?? "",
            projectLabel: projectLabel,
            phase: phase,
            currentTool: currentTool,
            activityLabel: currentTool?.summary ?? phase.title,
            detail: detail
        )
    }
}

struct SessionReducer {
    struct Result: Equatable, Sendable {
        var session: CodexSessionState?
        var didCompleteTurn = false
        var didInterruptTurn = false
    }

    func reduce(_ previous: CodexSessionState?, event: NudgeEvent) -> Result {
        var session = previous ?? CodexSessionState(
            id: event.sessionID,
            turnID: nil,
            projectLabel: "Codex",
            phase: .discovered,
            activeTools: [:],
            lastActivityAt: event.observedAt,
            completedTurnIDs: []
        )
        guard session.id == event.sessionID else { return Result(session: previous) }

        var result = Result(session: session)
        if let incomingTurn = event.turnID,
           let currentTurn = session.turnID,
           incomingTurn != currentTurn,
           isOlderEvent(event, than: currentTurn) {
            return result
        }
        if case .promptSubmitted = event.kind,
           let incomingTurn = event.turnID,
           let currentTurn = session.turnID,
           incomingTurn != currentTurn,
           event.observedAt <= session.lastActivityAt {
            return result
        }
        if let label = event.projectLabel, !label.isEmpty { session.projectLabel = label }
        result.session = session

        switch event.kind {
        case let .sessionStarted(label):
            if !label.isEmpty { session.projectLabel = label }
            if session.phase == .discovered { session.phase = .idle }

        case .promptSubmitted:
            if let incoming = event.turnID,
               session.turnID == incoming,
               session.phase == .thinking || session.phase == .toolUse || session.phase.isTerminal {
                return result
            }
            if let incoming = event.turnID, session.turnID != incoming {
                session.turnID = incoming
                session.activeTools.removeAll()
            }
            session.phase = .thinking

        case let .toolStarted(id, activity):
            guard !isTerminal(session.phase, turnID: event.turnID, session: session) else { return result }
            if let incoming = event.turnID {
                if let current = session.turnID, incoming != current { return result }
                session.turnID = incoming
            }
            session.activeTools[id] = activity
            session.phase = .toolUse

        case let .toolFinished(id):
            guard !isTerminal(session.phase, turnID: event.turnID, session: session),
                  session.activeTools[id] != nil else { return result }
            if let incoming = event.turnID, let current = session.turnID, incoming != current { return result }
            session.activeTools.removeValue(forKey: id)
            session.phase = session.activeTools.isEmpty ? .thinking : .toolUse

        case .turnFinished:
            guard let turnID = event.turnID, !turnID.isEmpty,
                  session.phase != .interrupted && session.phase != .failed && session.phase != .ended else { return result }
            if let current = session.turnID, current != turnID { return result }
            guard !session.completedTurnIDs.contains(turnID) else { return result }
            session.turnID = turnID
            session.activeTools.removeAll()
            session.phase = .completed
            session.completedTurnIDs.append(turnID)
            if session.completedTurnIDs.count > 32 { session.completedTurnIDs.removeFirst() }
            result.didCompleteTurn = true

        case .interrupted:
            guard let turnID = event.turnID, !turnID.isEmpty,
                  session.phase != .interrupted && session.phase != .completed && session.phase != .failed else { return result }
            if let current = session.turnID, current != turnID { return result }
            session.turnID = turnID
            session.activeTools.removeAll()
            session.phase = .interrupted
            result.didInterruptTurn = true
        }

        session.lastActivityAt = max(session.lastActivityAt, event.observedAt)
        result.session = session
        return result
    }

    private func isTerminal(_ phase: SessionPhase, turnID: String?, session: CodexSessionState) -> Bool {
        guard turnID == session.turnID else { return false }
        return phase == .completed || phase == .interrupted || phase == .failed || phase == .ended
    }

    private func isOlderEvent(_ event: NudgeEvent, than currentTurn: String) -> Bool {
        guard let incoming = event.turnID,
              let incomingNumber = UInt64(incoming),
              let currentNumber = UInt64(currentTurn) else { return false }
        return incomingNumber < currentNumber
    }
}
