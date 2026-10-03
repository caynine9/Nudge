import Foundation

struct ActivityProjectGroup: Equatable, Sendable {
    let label: String
    var sessions: [ActivitySnapshot]
}

enum ActivityProjectGroups {
    // The input already carries attention and turn-start priority. A group's
    // first session gives it its position; members keep their original order.
    static func make(from orderedSessions: [ActivitySnapshot]) -> [ActivityProjectGroup] {
        var groups: [ActivityProjectGroup] = []
        var indexes: [String: Int] = [:]
        for session in orderedSessions {
            let label = session.projectLabel == "Codex" ? "Unknown project" : session.projectLabel
            if let index = indexes[label] {
                groups[index].sessions.append(session)
            } else {
                indexes[label] = groups.count
                groups.append(ActivityProjectGroup(label: label, sessions: [session]))
            }
        }
        return groups
    }
}
