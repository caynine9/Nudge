import Foundation

enum PermissionDecision: String, Codable, Sendable {
    case allowOnce
    case deny
}

struct PermissionRequestMessage: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumFrameSize = 4_096
    static let maximumBudgetMilliseconds = 10_000

    let schema: Int
    let requestID: String
    let interactionID: String
    let sessionID: String
    let turnID: String
    let toolCallID: String?
    let toolName: String
    let summary: String?
    let budgetMilliseconds: Int

    enum CodingKeys: String, CodingKey {
        case schema
        case requestID = "request_id"
        case interactionID = "interaction_id"
        case sessionID = "session_id"
        case turnID = "turn_id"
        case toolCallID = "tool_call_id"
        case toolName = "tool_name"
        case summary
        case budgetMilliseconds = "budget_ms"
    }

    init(requestID: String, interactionID: String, sessionID: String, turnID: String, toolCallID: String?,
         toolName: String, summary: String?, budgetMilliseconds: Int = Self.maximumBudgetMilliseconds) {
        schema = Self.schemaVersion
        self.requestID = requestID
        self.interactionID = interactionID
        self.sessionID = sessionID
        self.turnID = turnID
        self.toolCallID = toolCallID
        self.toolName = toolName
        self.summary = summary
        self.budgetMilliseconds = budgetMilliseconds
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: PermissionJSONKey.self)
        let allowed: Set<String> = ["schema", "request_id", "interaction_id", "session_id", "turn_id", "tool_call_id",
                                    "tool_name", "summary", "budget_ms"]
        let keys = Set(dynamic.allKeys.map(\.stringValue))
        let required: Set<String> = ["schema", "request_id", "interaction_id", "session_id", "turn_id",
                                     "tool_name", "budget_ms"]
        guard keys.isSubset(of: allowed), required.isSubset(of: keys) else { throw WireError.malformedPayload }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        requestID = try container.decode(String.self, forKey: .requestID)
        interactionID = try container.decode(String.self, forKey: .interactionID)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        turnID = try container.decode(String.self, forKey: .turnID)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        toolName = try container.decode(String.self, forKey: .toolName)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        budgetMilliseconds = try container.decode(Int.self, forKey: .budgetMilliseconds)
    }

    func validate() throws {
        guard schema == Self.schemaVersion,
              UUID(uuidString: requestID)?.uuidString.lowercased() == requestID.lowercased(),
              requestID == interactionID,
              Self.validIdentifier(interactionID),
              Self.validIdentifier(sessionID), Self.validIdentifier(turnID),
              toolCallID.map(Self.validIdentifier) ?? true,
              !toolName.isEmpty, toolName.utf8.count <= 128,
              !toolName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (1...Self.maximumBudgetMilliseconds).contains(budgetMilliseconds) else {
            throw WireError.malformedPayload
        }
        if let summary {
            guard PermissionRequestSanitizer.isSafe(summary), summary.utf8.count <= 160 else {
                throw WireError.malformedPayload
            }
        }
        let encoder = JSONEncoder()
        guard try encoder.encode(self).count <= Self.maximumFrameSize else { throw WireError.frameTooLarge }
    }

    var isActionable: Bool { toolName == "Bash" && summary != nil }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= WireEnvelope.maximumIdentifierBytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

struct PermissionResponseMessage: Codable, Equatable, Sendable {
    let schema: Int
    let requestID: String
    let decision: PermissionDecision

    enum CodingKeys: String, CodingKey { case schema, requestID = "request_id", decision }

    init(requestID: String, decision: PermissionDecision) {
        schema = PermissionRequestMessage.schemaVersion
        self.requestID = requestID
        self.decision = decision
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: PermissionJSONKey.self)
        guard Set(dynamic.allKeys.map(\.stringValue)) == ["schema", "request_id", "decision"] else {
            throw WireError.malformedPayload
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        requestID = try container.decode(String.self, forKey: .requestID)
        decision = try container.decode(PermissionDecision.self, forKey: .decision)
    }

    func validate(expectedRequestID: String) throws {
        guard schema == PermissionRequestMessage.schemaVersion, requestID == expectedRequestID,
              UUID(uuidString: requestID) != nil else { throw WireError.malformedPayload }
    }
}

enum PermissionMessageCodec {
    static func decodeRequest(_ data: Data) throws -> PermissionRequestMessage {
        guard try !StrictJSONValidator.hasDuplicateObjectKeys(data) else { throw WireError.malformedPayload }
        return try JSONDecoder().decode(PermissionRequestMessage.self, from: data)
    }

    static func decodeResponse(_ data: Data) throws -> PermissionResponseMessage {
        guard try !StrictJSONValidator.hasDuplicateObjectKeys(data) else { throw WireError.malformedPayload }
        return try JSONDecoder().decode(PermissionResponseMessage.self, from: data)
    }
}

enum PermissionRequestSanitizer {
    static func summary(from value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafe(candidate), candidate.utf8.count <= 160 else { return nil }
        return candidate
    }

    static func isSafe(_ value: String) -> Bool {
        guard (8...160).contains(value.utf8.count),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !value.contains("/") && !value.contains("\\"),
              !value.contains("@"), !value.contains("://") else { return false }
        let lowered = value.lowercased()
        let sensitiveMarkers = ["api key", "apikey", "password", "secret", "token", "bearer", "sk-", "ghp_"]
        return !sensitiveMarkers.contains(where: lowered.contains)
    }
}

private struct PermissionJSONKey: CodingKey {
    let stringValue: String
    let intValue: Int?
    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}
