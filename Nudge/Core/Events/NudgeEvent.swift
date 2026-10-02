import Foundation

struct NudgeEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case sessionStarted(projectLabel: String)
        case promptSubmitted
        case toolStarted(id: String, activity: ToolActivity)
        case toolFinished(id: String)
        case turnFinished
        case interrupted
    }

    let sessionID: String
    let turnID: String?
    let observedAt: Date
    let kind: Kind
    var projectLabel: String? = nil

    var semanticKey: String {
        let identity: String
        switch kind {
        case let .sessionStarted(label): identity = "session:\(label)"
        case .promptSubmitted: identity = "prompt"
        case let .toolStarted(id, _): identity = "tool-start:\(id)"
        case let .toolFinished(id): identity = "tool-finish:\(id)"
        case .turnFinished: identity = "finish"
        case .interrupted: identity = "interrupt"
        }
        return "\(sessionID)|\(turnID ?? "")|\(identity)"
    }
}
