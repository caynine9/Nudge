import Foundation

struct FocusPolicy {
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
