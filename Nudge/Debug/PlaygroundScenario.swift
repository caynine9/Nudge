import Foundation

// Authored demo data only. No transcript, file read, provider response or real approval is used.
enum PlaygroundScenario {
    static let taskTitle = "fix auth bug"
    static let prompt = "Fix the auth bug in middleware"
    static let filePath = "src/auth/middleware.ts"
    static let question = "Which deployment target?"
    static let options = ["Production", "Staging", "Local only"]

    struct UsageWindow {
        let label: String
        let accessibilityName: String
        let usedPercent: Int
        let resetIn: String
        let accessibilityReset: String
    }

    // Fixed preview values, not account limits. No polling or reset timer in M0.
    static let fiveHourUsage = UsageWindow(
        label: "5h", accessibilityName: "5-hour window", usedPercent: 11,
        resetIn: "4h1m", accessibilityReset: "4 hours, 1 minute"
    )
    static let weeklyUsage = UsageWindow(
        label: "7d", accessibilityName: "weekly window", usedPercent: 2,
        resetIn: "6h1m", accessibilityReset: "6 hours, 1 minute"
    )

    struct DiffLine: Identifiable {
        enum Kind { case context, removed, added }
        let id: Int
        let number: String
        let marker: String
        let code: String
        let kind: Kind
    }

    static let diff: [DiffLine] = [
        .init(id: 0, number: "12", marker: " ", code: "const verify = (token) => {", kind: .context),
        .init(id: 1, number: "13", marker: "−", code: "  jwt.verify(token);", kind: .removed),
        .init(id: 2, number: "13", marker: "+", code: "  if (!token) throw new", kind: .added),
        .init(id: 3, number: "14", marker: "+", code: "    AuthError('missing');", kind: .added),
        .init(id: 4, number: "15", marker: "+", code: "  return jwt.verify(token);", kind: .added)
    ]

    static func snapshot(turn: Int, phase: SessionPhase) -> ActivitySnapshot {
        ActivitySnapshot(
            sessionID: "playground-session", turnID: "playground-turn-\(turn)", projectLabel: "Nudge",
            phase: phase,
            currentTool: phase == .toolUse ? ToolActivity(category: .edit, summary: "Writing middleware.ts", symbol: "pencil") : nil,
            activityLabel: phase == .toolUse ? "Writing middleware.ts" : phase.title,
            detail: phase.detail
        )
    }
}
