import Foundation

struct FocusPolicy {
    func orderedActiveSessions(_ sessions: [CodexSessionState]) -> [CodexSessionState] {
        sessions.filter { $0.presentationPhase.isActive }.sorted { lhs, rhs in
            let lhsAttention = lhs.presentationPhase.isAttention
            let rhsAttention = rhs.presentationPhase.isAttention
            if lhsAttention != rhsAttention { return lhsAttention }

            let lhsStart = lhsAttention ? lhs.pendingInteractionStartedAt : lhs.turnStartedAt
            let rhsStart = rhsAttention ? rhs.pendingInteractionStartedAt : rhs.turnStartedAt
            if lhsStart != rhsStart { return (lhsStart ?? .distantPast) > (rhsStart ?? .distantPast) }
            return lhs.id < rhs.id
        }
    }

    func focused(
        sessions: [CodexSessionState],
        explicitlySelectedID: String? = nil,
        now: Date,
        completionGrace: TimeInterval = 8
    ) -> CodexSessionState? {
        func newest(_ candidates: [CodexSessionState]) -> CodexSessionState? {
            candidates.sorted {
                if $0.lastActivityAt != $1.lastActivityAt { return $0.lastActivityAt > $1.lastActivityAt }
                return $0.id < $1.id
            }.first
        }
        if let session = newest(sessions.filter { $0.presentationPhase.isAttention }) { return session }
        if let explicitlySelectedID, let selected = sessions.first(where: { $0.id == explicitlySelectedID }) { return selected }
        if let session = newest(sessions.filter { $0.presentationPhase == .thinking || $0.presentationPhase == .toolUse }) { return session }
        if let session = newest(sessions.filter {
            let age = now.timeIntervalSince($0.lastActivityAt)
            return $0.presentationPhase.isTerminal && age >= 0 && age <= completionGrace
        }) { return session }
        return nil
    }
}
