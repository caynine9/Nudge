import Foundation

actor CodexEventMonitor {
    static let duplicateTTL: UInt64 = 2_000_000_000
    static let maximumRecentEvents = 512
    static let idleRetention: TimeInterval = 30 * 60

    private var sessions: [String: CodexSessionState] = [:]
    private var recentEventTimes: [String: UInt64] = [:]
    private var recentEventOrder: [String] = []
    private var selectedSessionID: String?
    private let reducer = SessionReducer()
    private let focusPolicy = FocusPolicy()

    func consume(
        _ envelope: WireEnvelope,
        now: Date = Date(),
        monotonicNow: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> ActivityMonitorSnapshot {
        let event = Self.event(from: envelope)
        pruneRecentEvents(at: monotonicNow)

        let current = sessions[event.sessionID]
        let duplicate = recentEventTimes[event.semanticKey].map {
            monotonicNow >= $0 && monotonicNow - $0 < Self.duplicateTTL
        } ?? false
        if duplicate {
            if let enriched = reducer.enrichMetadata(current, event: event) { sessions[event.sessionID] = enriched }
            pruneIdleSessions(at: now)
            return monitorSnapshot(at: now)
        }

        let transition = reducer.reduce(current, event: event)
        if let session = transition.session { sessions[event.sessionID] = session }
        if transition.didMakeProgress || transition.session != current {
            recentEventTimes[event.semanticKey] = monotonicNow
            recentEventOrder.append(event.semanticKey)
            trimRecentEvents()
        }

        pruneIdleSessions(at: now)
        return monitorSnapshot(at: now)
    }

    func select(sessionID: String?) { selectedSessionID = sessionID }

    func currentSnapshot(now: Date = Date()) -> ActivityMonitorSnapshot {
        pruneIdleSessions(at: now)
        return monitorSnapshot(at: now)
    }

    private func pruneRecentEvents(at now: UInt64) {
        let expired = recentEventOrder.filter { key in
            guard let recorded = recentEventTimes[key] else { return true }
            return now < recorded || now - recorded >= Self.duplicateTTL
        }
        guard !expired.isEmpty else { return }
        let expiredSet = Set(expired)
        for key in expired { recentEventTimes.removeValue(forKey: key) }
        recentEventOrder.removeAll { expiredSet.contains($0) }
    }

    private func trimRecentEvents() {
        while recentEventOrder.count > Self.maximumRecentEvents {
            recentEventTimes.removeValue(forKey: recentEventOrder.removeFirst())
        }
    }

    private func pruneIdleSessions(at now: Date) {
        let expired = sessions.values.filter { session in
            guard session.id != selectedSessionID, !session.isRetainable else { return false }
            let age = now.timeIntervalSince(session.lastActivityAt)
            return age >= Self.idleRetention
        }
        for session in expired { sessions.removeValue(forKey: session.id) }
    }

    private func monitorSnapshot(at now: Date) -> ActivityMonitorSnapshot {
        let values = Array(sessions.values)
        let focused = focusPolicy.focused(sessions: values, explicitlySelectedID: selectedSessionID, now: now)?.snapshot
            ?? .empty
        let active = focusPolicy.orderedActiveSessions(values).map(\.snapshot)
        return ActivityMonitorSnapshot(focused: focused, activeSessions: active)
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
