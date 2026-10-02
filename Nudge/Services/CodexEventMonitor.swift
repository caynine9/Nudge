import Foundation

actor CodexEventMonitor {
    private var sessions: [String: CodexSessionState] = [:]
    private var recentEventKeys: [String] = []
    private var recentEventSet: Set<String> = []
    private var selectedSessionID: String?
    private let reducer = SessionReducer()
    private let focusPolicy = FocusPolicy()

    func consume(_ envelope: WireEnvelope, now: Date = Date()) -> ActivitySnapshot {
        let event = Self.event(from: envelope)
        guard !recentEventSet.contains(event.semanticKey) else { return focusedSnapshot(at: now) }
        recentEventKeys.append(event.semanticKey)
        recentEventSet.insert(event.semanticKey)
        if recentEventKeys.count > 512 {
            recentEventSet.remove(recentEventKeys.removeFirst())
        }

        let current = sessions[event.sessionID]
        let transition = reducer.reduce(current, event: event)
        if let session = transition.session { sessions[event.sessionID] = session }
        return focusedSnapshot(at: now)
    }

    func select(sessionID: String?) { selectedSessionID = sessionID }

    private func focusedSnapshot(at now: Date) -> ActivitySnapshot {
        focusPolicy.focused(sessions: Array(sessions.values), explicitlySelectedID: selectedSessionID, now: now)?.snapshot
            ?? .empty
    }

    private static func event(from envelope: WireEnvelope) -> NudgeEvent {
        let date = Date(timeIntervalSince1970: Double(envelope.observedAtMilliseconds) / 1_000)
        let kind: NudgeEvent.Kind
        switch envelope.event {
        case .sessionStart:
            kind = .sessionStarted(projectLabel: envelope.projectLabel ?? "Codex")
        case .userPromptSubmit:
            kind = .promptSubmitted
        case .preToolUse:
            kind = .toolStarted(id: envelope.toolCallID ?? "", activity: envelope.tool ??
                ToolActivity(category: .other, summary: "Using Codex tool", symbol: "sparkles"))
        case .postToolUse:
            kind = .toolFinished(id: envelope.toolCallID ?? "")
        case .stop:
            kind = .turnFinished
        case .interrupt:
            kind = .interrupted
        }
        return NudgeEvent(sessionID: envelope.sessionID, turnID: envelope.turnID, observedAt: date,
                          kind: kind, projectLabel: envelope.projectLabel)
    }
}
