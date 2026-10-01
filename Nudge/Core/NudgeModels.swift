import Foundation

enum SessionPhase: String, CaseIterable, Identifiable {
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

enum ToolCategory {
    case read
    case edit
    case shell
    case test
    case web
    case git
    case other
}

struct ToolActivity: Equatable {
    let category: ToolCategory
    let summary: String
    let symbol: String
}

struct ActivitySnapshot: Equatable {
    let sessionID: String
    let turnID: String
    let projectLabel: String
    let phase: SessionPhase
    let currentTool: ToolActivity?
    let activityLabel: String
    let detail: String

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

enum NotchPresentation: Equatable {
    case collapsed
    case peek
    case expanded
    case attention
}

enum PresentationTimer: Hashable {
    case peek
    case collapse
    case transient
}

struct PresentationState: Equatable {
    var snapshot = ActivitySnapshot.demo(turn: 1, phase: .thinking)
    var pointerInside = false
    var peekVisible = false
    var pinnedOpen = false
    var isSleeping = false
    var transientPhase: SessionPhase?
    var consumedCompletionTurnID: String?
    var consumedFailureTurnID: String?
    var peekGeneration = 0
    var collapseGeneration = 0
    var transientGeneration = 0

    var mode: NotchPresentation {
        if snapshot.phase.isAttention { return .attention }
        if transientPhase != nil { return .expanded }
        if pinnedOpen { return .expanded }
        if peekVisible { return .peek }
        return .collapsed
    }
}

enum PresentationInput {
    case snapshotChanged(ActivitySnapshot)
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
