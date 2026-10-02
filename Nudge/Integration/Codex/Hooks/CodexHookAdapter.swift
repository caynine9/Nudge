import Foundation

struct CodexHookAdapter {
    func envelope(from data: Data, expectedEvent: CodexHookEvent, now: Date = Date()) throws -> WireEnvelope {
        guard data.count <= 1024 * 1024 else { throw HookPayloadError.inputTooLarge }
        guard try !StrictJSONValidator.hasDuplicateObjectKeys(data) else { throw HookPayloadError.invalidShape }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookPayloadError.invalidShape
        }
        guard object["hook_event_name"] as? String == expectedEvent.rawValue,
              let sessionID = boundedString(object["session_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes) else {
            throw HookPayloadError.missingIdentity
        }

        let turnID = boundedString(object["turn_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes)
        let cwd = object["cwd"] as? String
        let projectLabel = cwd.flatMap(Self.safeProjectLabel)
        var toolCallID: String?
        var tool: ToolActivity?

        switch expectedEvent {
        case .sessionStart:
            break
        case .userPromptSubmit, .stop, .interrupt:
            guard turnID != nil else { throw HookPayloadError.missingIdentity }
            if expectedEvent == .stop, object["stop_hook_active"] as? Bool == true {
                throw HookPayloadError.nonTerminalStop
            }
        case .preToolUse, .postToolUse:
            guard turnID != nil,
                  let identifier = boundedString(object["tool_use_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes),
                  let rawToolName = object["tool_name"] as? String,
                  rawToolName.utf8.count <= 128 else { throw HookPayloadError.missingIdentity }
            toolCallID = identifier
            if expectedEvent == .preToolUse { tool = Self.activity(for: rawToolName) }
        }

        let envelope = WireEnvelope(
            schemaVersion: WireEnvelope.currentVersion,
            source: "codex",
            event: expectedEvent,
            sessionID: sessionID,
            turnID: turnID,
            observedAtMilliseconds: Int64(now.timeIntervalSince1970 * 1_000),
            projectLabel: projectLabel,
            toolCallID: toolCallID,
            tool: tool
        )
        try envelope.validate()
        return envelope
    }

    private func boundedString(_ value: Any?, maximumBytes: Int) -> String? {
        guard let value = value as? String, !value.isEmpty,
              value.utf8.count <= maximumBytes,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return value
    }

    private static func safeProjectLabel(_ path: String) -> String? {
        guard path.hasPrefix("/"), path.utf8.count <= 4_096 else { return nil }
        let last = URL(fileURLWithPath: path).lastPathComponent
        let safe = String(last.unicodeScalars.filter {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-" )).contains($0)
        }.prefix(64))
        return safe.isEmpty ? nil : safe
    }

    private static func activity(for toolName: String) -> ToolActivity {
        let lower = toolName.lowercased()
        if toolName == "Bash" {
            return ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        }
        if ["apply_patch", "Edit", "Write"].contains(toolName) {
            return ToolActivity(category: .edit, summary: "Editing files", symbol: "pencil")
        }
        if lower.contains("read") || lower.contains("list") {
            return ToolActivity(category: .read, summary: "Reading project files", symbol: "doc.text")
        }
        if lower.contains("search") || lower.contains("find") {
            return ToolActivity(category: .other, summary: "Searching project files", symbol: "magnifyingglass")
        }
        return ToolActivity(category: .other, summary: "Using Codex tool", symbol: "sparkles")
    }
}

enum HookPayloadError: Error, Equatable {
    case inputTooLarge
    case invalidShape
    case missingIdentity
    case nonTerminalStop
}
