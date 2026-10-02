import Foundation

enum SessionPhase: String, CaseIterable, Codable, Identifiable, Sendable {
    case discovered
    case idle
    case thinking
    case toolUse
    case waitingPermission
    case waitingInput
    case completed
    case failed
    case interrupted
    case ended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discovered: "Found session"
        case .idle: "Ready"
        case .thinking: "Thinking…"
        case .toolUse: "Running tests"
        case .waitingPermission: "Needs permission"
        case .waitingInput: "Has a question"
        case .completed: "Done"
        case .failed: "Hit a problem"
        case .interrupted: "Stopped"
        case .ended: "Session ended"
        }
    }

    var symbol: String {
        switch self {
        case .discovered: "sparkle.magnifyingglass"
        case .idle: "circle.dashed"
        case .thinking: "sparkles"
        case .toolUse: "hammer.fill"
        case .waitingPermission: "hand.raised.fill"
        case .waitingInput: "questionmark.bubble.fill"
        case .completed: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        case .interrupted: "pause.fill"
        case .ended: "moon.zzz.fill"
        }
    }

    var isAttention: Bool {
        self == .waitingPermission || self == .waitingInput
    }

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .interrupted || self == .ended
    }

    var transientDuration: Duration? {
        switch self {
        case .completed: .seconds(3.2)
        case .failed: .seconds(5)
        default: nil
        }
    }

    var detail: String {
        switch self {
        case .discovered: "A local Codex session is ready to follow."
        case .idle: "Everything is quiet for now."
        case .thinking: "Codex is working through the next step."
        case .toolUse: "Running the Nudge test suite."
        case .waitingPermission: "Codex needs permission before it can continue."
        case .waitingInput: "Codex has a question for you."
        case .completed: "Finished the task and checked the result."
        case .failed: "Codex stopped after an error."
        case .interrupted: "The turn was interrupted before it finished."
        case .ended: "This session has ended."
        }
    }
}

enum ToolCategory: String, Codable, Sendable {
    case read
    case edit
    case shell
    case test
    case web
    case git
    case other
}

struct ToolActivity: Codable, Equatable, Sendable {
    let category: ToolCategory
    let summary: String
    let symbol: String

    private enum CodingKeys: String, CodingKey { case category, summary, symbol }

    init(category: ToolCategory, summary: String, symbol: String) {
        self.category = category
        self.summary = summary
        self.symbol = symbol
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: ToolActivityJSONKey.self)
        let allowed: Set<String> = ["category", "summary", "symbol"]
        guard Set(dynamic.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                     debugDescription: "Unknown ToolActivity field."))
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        category = try container.decode(ToolCategory.self, forKey: .category)
        summary = try container.decode(String.self, forKey: .summary)
        symbol = try container.decode(String.self, forKey: .symbol)
    }
}

private struct ToolActivityJSONKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

struct ActivitySnapshot: Equatable, Sendable {
    let sessionID: String
    let turnID: String
    let projectLabel: String
    let phase: SessionPhase
    let currentTool: ToolActivity?
    let activityLabel: String
    let detail: String

    static let empty = Self(
        sessionID: "", turnID: "", projectLabel: "Codex", phase: .idle,
        currentTool: nil, activityLabel: "Ready", detail: "Waiting for local Codex activity."
    )

    static func demo(turn: Int, phase: SessionPhase) -> Self {
        let activity: String
        switch phase {
        case .toolUse: activity = "Running tests"
        case .waitingPermission: activity = "Permission needed"
        case .waitingInput: activity = "Question for you"
        default: activity = phase.title
        }

        return Self(
            sessionID: "playground-session",
            turnID: "playground-turn-\(turn)",
            projectLabel: "Nudge Playground",
            phase: phase,
            currentTool: phase == .toolUse
                ? ToolActivity(category: .test, summary: "Running tests", symbol: "checkmark.circle")
                : nil,
            activityLabel: activity,
            detail: phase.detail
        )
    }
}

enum NotchPresentation: Equatable, CaseIterable {
    case collapsed
    case peek
    case expanded
    case attention
    case confirmation
}

struct InteractionFeedback: Equatable {
    enum Kind { case allowed, denied, selected }
    let label: String
    let kind: Kind
}

enum PresentationTimer: Hashable {
    case peek
    case collapse
    case transient
    case feedback
}

struct PresentationState: Equatable {
    var snapshot = ActivitySnapshot.empty
    var pointerInside = false
    var peekVisible = false
    var pinnedOpen = false
    var isSleeping = false
    var feedback: InteractionFeedback?
    var feedbackGeneration = 0
    var transientPhase: SessionPhase?
    var consumedCompletionTurnID: String?
    var consumedFailureTurnID: String?
    var peekGeneration = 0
    var collapseGeneration = 0
    var transientGeneration = 0

    var mode: NotchPresentation {
        if snapshot.phase.isAttention { return .attention }
        if feedback != nil { return .confirmation }
        if transientPhase != nil { return .expanded }
        if pinnedOpen { return .expanded }
        if peekVisible { return .peek }
        return .collapsed
    }
}

enum PresentationInput {
    case snapshotChanged(ActivitySnapshot)
    case previewInteractionResolved(ActivitySnapshot, InteractionFeedback)
    case pointerChanged(Bool)
    case togglePinned
    case collapse
    case timerElapsed(PresentationTimer, generation: Int)
    case sleep
    case wake
}

enum PresentationEffect {
    case schedule(PresentationTimer, after: Duration, generation: Int)
    case cancel(PresentationTimer)
    case celebrate
}

struct PresentationTransition {
    var state: PresentationState
    var effects: [PresentationEffect] = []
}
