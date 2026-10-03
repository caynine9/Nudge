import Foundation

enum PendingInteractionKind: String, Equatable, Sendable {
    case permission
    case question
}

struct PendingInteraction: Equatable, Sendable {
    let id: String
    let kind: PendingInteractionKind
    var toolCallID: String?
    var toolName: String? = nil
    var preview: String? = nil
    var createdAt: Date? = nil
    var permissionCorrelationWasAmbiguous = false
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
    var toolName: String? = nil
    var interaction: PendingInteraction? = nil

    var semanticKey: String {
        let identity: [String]
        switch kind {
        case .sessionStarted: identity = ["session"]
        case .promptSubmitted: identity = ["prompt"]
        case let .toolStarted(id, activity): identity = ["tool-start", id, activity.category.rawValue, activity.summary, activity.symbol]
        case let .toolFinished(id): identity = ["tool-finish", id, toolName ?? ""]
        case let .pendingInteraction(interaction):
            identity = ["pending", interaction.id, interaction.kind.rawValue, interaction.toolCallID ?? ""]
        case let .interactionResolved(id): identity = ["resolved", id]
        case .lifecycleEnded: identity = ["ended"]
        case .turnFinished: identity = ["finish"]
        case .interrupted: identity = ["interrupt"]
        }
        // Length prefixing makes arbitrary host identifiers safe as a composite key.
        let interactionKey = interaction.map { ["attached", $0.id, $0.kind.rawValue, $0.toolCallID ?? ""] } ?? []
        return ([sessionID, turnID ?? ""] + identity + interactionKey).map { "\($0.utf8.count):\($0)" }.joined()
    }
}
