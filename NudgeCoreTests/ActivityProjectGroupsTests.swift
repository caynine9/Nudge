import XCTest

final class ActivityProjectGroupsTests: XCTestCase {
    func testGroupsPreservePriorityAndEverySessionIdentity() {
        let ordered = [
            session("attention", project: "Nudge", phase: .waitingPermission),
            session("latest-other", project: "Invoice", phase: .toolUse),
            session("older-nudge", project: "Nudge", phase: .thinking),
            session("older-other", project: "Invoice", phase: .thinking)
        ]

        let groups = ActivityProjectGroups.make(from: ordered)
        XCTAssertEqual(groups.map(\.label), ["Nudge", "Invoice"])
        XCTAssertEqual(groups[0].sessions.map(\.sessionID), ["attention", "older-nudge"])
        XCTAssertEqual(groups[1].sessions.map(\.sessionID), ["latest-other", "older-other"])
        XCTAssertEqual(groups.flatMap(\.sessions).map(\.sessionID).sorted(), ordered.map(\.sessionID).sorted())
    }

    func testUnknownProjectGetsAnHonestHeader() {
        let groups = ActivityProjectGroups.make(from: [session("unknown", project: "Codex", phase: .thinking)])
        XCTAssertEqual(groups.map(\.label), ["Unknown project"])
    }

    private func session(_ id: String, project: String, phase: SessionPhase) -> ActivitySnapshot {
        ActivitySnapshot(sessionID: id, turnID: id, projectLabel: project, phase: phase,
                         currentTool: nil, activityLabel: phase.title, detail: phase.detail)
    }
}
