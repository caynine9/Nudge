import Foundation

enum CodexHookEvent: String, CaseIterable, Codable, Sendable {
    case sessionStart = "SessionStart"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case stop = "Stop"
    case interrupt = "Interrupt"
}

struct WireEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 2
    static let legacyVersion = 1
    static let maximumFrameSize = 64 * 1024
    static let maximumIdentifierBytes = 256
    static let maximumSummaryCharacters = 120

    let schemaVersion: Int
    let source: String
    let event: CodexHookEvent
    let sessionID: String
    let turnID: String?
    let observedAtMilliseconds: Int64
    let projectLabel: String?
    let toolCallID: String?
    let tool: ToolActivity?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case source, event
        case sessionID = "session_id"
        case turnID = "turn_id"
        case observedAtMilliseconds = "observed_at_ms"
        case projectLabel = "project_label"
        case toolCallID = "tool_call_id"
        case tool
    }

    init(schemaVersion: Int, source: String, event: CodexHookEvent, sessionID: String, turnID: String?,
         observedAtMilliseconds: Int64, projectLabel: String?, toolCallID: String?, tool: ToolActivity?) {
        self.schemaVersion = schemaVersion
        self.source = source
        self.event = event
        self.sessionID = sessionID
        self.turnID = turnID
        self.observedAtMilliseconds = observedAtMilliseconds
        self.projectLabel = projectLabel
        self.toolCallID = toolCallID
        self.tool = tool
    }

    init(from decoder: Decoder) throws {
        let dynamic = try decoder.container(keyedBy: JSONDynamicCodingKey.self)
        let allowed: Set<String> = ["schema_version", "source", "event", "session_id", "turn_id",
                                    "observed_at_ms", "project_label", "tool_call_id", "tool"]
        guard Set(dynamic.allKeys.map(\.stringValue)).isSubset(of: allowed) else {
            throw WireError.malformedPayload
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        source = try container.decode(String.self, forKey: .source)
        event = try container.decode(CodexHookEvent.self, forKey: .event)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
        observedAtMilliseconds = try container.decode(Int64.self, forKey: .observedAtMilliseconds)
        projectLabel = try container.decodeIfPresent(String.self, forKey: .projectLabel)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
        tool = try container.decodeIfPresent(ToolActivity.self, forKey: .tool)
    }

    func validate() throws {
        guard schemaVersion == Self.currentVersion || schemaVersion == Self.legacyVersion else {
            throw WireError.unsupportedVersion
        }
        guard source == "codex" else { throw WireError.invalidSource }
        guard observedAtMilliseconds >= 0 else { throw WireError.malformedPayload }
        try Self.validateIdentifier(sessionID)
        if let turnID { try Self.validateIdentifier(turnID) }
        if let toolCallID { try Self.validateIdentifier(toolCallID) }
        if let projectLabel {
            guard !projectLabel.isEmpty, projectLabel.count <= Self.maximumSummaryCharacters,
                  !projectLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw WireError.fieldTooLarge
            }
        }
        if let tool {
            guard Self.validatedToolActivity(tool, version: schemaVersion) else { throw WireError.malformedPayload }
        }
        switch event {
        case .preToolUse, .postToolUse:
            guard turnID != nil, toolCallID != nil else { throw WireError.missingRequiredField }
            if event == .preToolUse, tool == nil { throw WireError.missingRequiredField }
        case .userPromptSubmit, .stop, .interrupt:
            guard turnID != nil else { throw WireError.missingRequiredField }
        case .sessionStart:
            break
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(self).count <= Self.maximumFrameSize else { throw WireError.frameTooLarge }
    }

    private static func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty else { throw WireError.missingRequiredField }
        guard value.utf8.count <= maximumIdentifierBytes,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw WireError.fieldTooLarge
        }
    }

    private static func validatedToolActivity(_ tool: ToolActivity, version: Int) -> Bool {
        if version == Self.legacyVersion {
            return legacyToolActivity(tool)
        }
        guard !tool.summary.isEmpty, tool.summary.count <= Self.maximumSummaryCharacters,
              !tool.summary.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return switch (tool.category, tool.summary, tool.symbol) {
        case (.shell, "Running command", "terminal"),
             (.shell, "Running tests", "terminal"),
             (.shell, "Building project", "terminal"),
             (.shell, "Checking Git changes", "terminal"),
             (.shell, "Reading project files", "terminal"),
             (.shell, "Searching project files", "terminal"),
             (.shell, "Updating project files", "terminal"),
             (.test, "Running project tests", "checkmark.circle"),
             (.test, "Running Swift tests", "checkmark.circle"),
             (.test, "Running Xcode tests", "checkmark.circle"),
             (.test, "Running JavaScript tests", "checkmark.circle"),
             (.test, "Running Python tests", "checkmark.circle"),
             (.edit, "Editing files", "pencil"),
             (.edit, "Updating project files", "pencil"),
             (.read, "Reading project files", "doc.text"),
             (.read, "Inspecting project files", "doc.text"),
             (.other, "Searching project files", "magnifyingglass"),
             (.other, "Searching project files", "sparkles"),
             (.other, "Using Codex tool", "sparkles"):
            true
        default:
            false
        }
    }

    private static func legacyToolActivity(_ tool: ToolActivity) -> Bool {
        switch (tool.category, tool.summary, tool.symbol) {
        case (.shell, "Running command", "terminal"),
             (.edit, "Editing files", "pencil"),
             (.read, "Reading project files", "doc.text"),
             (.other, "Searching project files", "magnifyingglass"),
             (.other, "Using Codex tool", "sparkles"):
            true
        default:
            false
        }
    }
}

enum WireError: Error, Equatable {
    case unsupportedVersion
    case invalidSource
    case invalidEvent
    case missingRequiredField
    case fieldTooLarge
    case frameTooLarge
    case malformedPayload
    case invalidPeer
    case unavailable
    case timedOut

    var diagnosticCode: String {
        switch self {
        case .unsupportedVersion: "unsupported-version"
        case .invalidSource: "invalid-source"
        case .invalidEvent: "invalid-event"
        case .missingRequiredField: "missing-field"
        case .fieldTooLarge: "field-too-large"
        case .frameTooLarge: "frame-too-large"
        case .malformedPayload: "malformed-payload"
        case .invalidPeer: "invalid-peer"
        case .unavailable: "unavailable"
        case .timedOut: "timed-out"
        }
    }
}

enum WireCodec {
    static func encode(_ envelope: WireEnvelope) throws -> Data {
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(envelope)
        guard payload.count <= WireEnvelope.maximumFrameSize else { throw WireError.frameTooLarge }
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    static func decode(_ payload: Data) throws -> WireEnvelope {
        guard payload.count <= WireEnvelope.maximumFrameSize else { throw WireError.frameTooLarge }
        do {
            guard try !StrictJSONValidator.hasDuplicateObjectKeys(payload) else {
                throw WireError.malformedPayload
            }
            let envelope = try JSONDecoder().decode(WireEnvelope.self, from: payload)
            try envelope.validate()
            return envelope
        } catch let error as WireError {
            throw error
        } catch {
            throw WireError.malformedPayload
        }
    }
}

struct JSONDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

enum StrictJSONValidator {
    static func hasDuplicateObjectKeys(_ data: Data) throws -> Bool {
        let scanner = JSONDuplicateKeyScanner(bytes: Array(data))
        return try scanner.hasDuplicates()
    }
}

private enum JSONScanError: Error { case malformed }

private struct JSONDuplicateKeyScanner {
    let bytes: [UInt8]
    private(set) var index = 0
    private(set) var duplicateFound = false

    func hasDuplicates() throws -> Bool {
        var scanner = self
        try scanner.scanValue(depth: 0)
        scanner.skipWhitespace()
        guard scanner.index == scanner.bytes.count else { throw JSONScanError.malformed }
        return scanner.duplicateFound
    }

    private mutating func scanValue(depth: Int) throws {
        guard depth <= 32 else { throw JSONScanError.malformed }
        skipWhitespace()
        guard index < bytes.count else { throw JSONScanError.malformed }
        switch bytes[index] {
        case 0x7B: try scanObject(depth: depth + 1)
        case 0x5B: try scanArray(depth: depth + 1)
        case 0x22: _ = try scanString()
        default: try scanPrimitive()
        }
    }

    private mutating func scanObject(depth: Int) throws {
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }
        var keys = Set<String>()
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else { throw JSONScanError.malformed }
            let key = try scanString()
            if !keys.insert(key).inserted { duplicateFound = true }
            skipWhitespace()
            guard consume(0x3A) else { throw JSONScanError.malformed }
            try scanValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw JSONScanError.malformed }
        }
    }

    private mutating func scanArray(depth: Int) throws {
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }
        while true {
            try scanValue(depth: depth)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw JSONScanError.malformed }
        }
    }

    private mutating func scanString() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x5C {
                guard index < bytes.count else { throw JSONScanError.malformed }
                index += 1
            } else if byte == 0x22 {
                let token = Data(bytes[start..<index])
                guard let strings = try JSONSerialization.jsonObject(with: Data("[".utf8) + token + Data("]".utf8)) as? [String],
                      let value = strings.first else { throw JSONScanError.malformed }
                return value
            } else if byte < 0x20 {
                throw JSONScanError.malformed
            }
        }
        throw JSONScanError.malformed
    }

    private mutating func scanPrimitive() throws {
        let start = index
        while index < bytes.count, ![0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x5D, 0x7D].contains(bytes[index]) { index += 1 }
        guard index > start else { throw JSONScanError.malformed }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }
}
