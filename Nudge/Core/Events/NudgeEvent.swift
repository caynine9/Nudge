import Foundation

enum PendingInteractionKind: String, Equatable, Sendable {
    case permission
    case question
}

struct PendingInteraction: Equatable, Sendable {
    let id: String
    let kind: PendingInteractionKind
    var toolCallID: String?
}

struct NudgeEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case sessionStarted(projectLabel: String)
        case promptSubmitted
        case toolStarted(id: String, activity: ToolActivity)
        case toolFinished(id: String)
        case pendingInteraction(PendingInteraction)
        case interactionResolved(id: String)
        case lifecycleEnded
        case turnFinished
        case interrupted
    }

    let sessionID: String
    let turnID: String?
    let observedAt: Date
    let kind: Kind
    var projectLabel: String? = nil

    var semanticKey: String {
        let identity: [String]
        switch kind {
        case .sessionStarted: identity = ["session"]
        case .promptSubmitted: identity = ["prompt"]
        case let .toolStarted(id, activity): identity = ["tool-start", id, activity.category.rawValue, activity.summary, activity.symbol]
        case let .toolFinished(id): identity = ["tool-finish", id]
        case let .pendingInteraction(interaction):
            identity = ["pending", interaction.id, interaction.kind.rawValue, interaction.toolCallID ?? ""]
        case let .interactionResolved(id): identity = ["resolved", id]
        case .lifecycleEnded: identity = ["ended"]
        case .turnFinished: identity = ["finish"]
        case .interrupted: identity = ["interrupt"]
        }
        // Length prefixing makes arbitrary host identifiers safe as a composite key.
        return ([sessionID, turnID ?? ""] + identity).map { "\($0.utf8.count):\($0)" }.joined()
    }
}
