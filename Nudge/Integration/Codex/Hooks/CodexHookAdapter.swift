import Foundation
import CryptoKit

struct CodexHookAdapter {
    func permissionRequest(from data: Data, budgetMilliseconds: Int = PermissionRequestMessage.maximumBudgetMilliseconds) throws -> PermissionRequestMessage {
        guard data.count <= 1_048_576, try !StrictJSONValidator.hasDuplicateObjectKeys(data),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["hook_event_name"] as? String == CodexHookEvent.permissionRequest.rawValue,
              let sessionID = boundedString(object["session_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes),
              let turnID = boundedString(object["turn_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes),
              let toolName = boundedString(object["tool_name"], maximumBytes: 128) else {
            throw HookPayloadError.missingIdentity
        }
        let input = object["tool_input"] as? [String: Any]
        let invocationID = UUID().uuidString.lowercased()
        let request = PermissionRequestMessage(
            requestID: invocationID,
            interactionID: invocationID,
            sessionID: sessionID,
            turnID: turnID,
            toolCallID: boundedString(object["tool_use_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes),
            toolName: toolName,
            summary: PermissionRequestSanitizer.summary(from: input?["description"]),
            budgetMilliseconds: budgetMilliseconds
        )
        try request.validate()
        return request
    }

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
        var toolName: String?
        var interaction: WireInteraction?

        switch expectedEvent {
        case .sessionStart:
            break
        case .userPromptSubmit, .stop, .interrupt:
            guard turnID != nil else { throw HookPayloadError.missingIdentity }
        case .preToolUse, .postToolUse:
            guard turnID != nil,
                  let identifier = boundedString(object["tool_use_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes),
                  let rawToolName = object["tool_name"] as? String,
                  rawToolName.utf8.count <= 128 else { throw HookPayloadError.missingIdentity }
            toolCallID = identifier
            toolName = rawToolName
            if expectedEvent == .preToolUse {
                tool = Self.activity(for: rawToolName, input: object["tool_input"])
                if rawToolName == "request_user_input" {
                    interaction = WireInteraction(
                        id: Self.interactionID(kind: .question, sessionID: sessionID, turnID: turnID!,
                                               toolCallID: identifier, toolName: rawToolName),
                        kind: .question,
                        toolCallID: identifier,
                        toolName: rawToolName,
                        preview: Self.questionPreview(from: object["tool_input"])
                    )
                }
            }
        case .permissionRequest:
            guard let activeTurnID = turnID,
                  let rawToolName = boundedString(object["tool_name"], maximumBytes: 128) else {
                throw HookPayloadError.missingIdentity
            }
            toolName = rawToolName
            toolCallID = boundedString(object["tool_use_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes)
            interaction = WireInteraction(
                id: Self.interactionID(kind: .permission, sessionID: sessionID, turnID: activeTurnID,
                                       toolCallID: toolCallID, toolName: rawToolName),
                kind: .permission,
                toolCallID: toolCallID,
                toolName: rawToolName,
                preview: nil
            )
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
            tool: tool,
            toolName: toolName,
            interaction: interaction
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

    private static func interactionID(kind: WireInteraction.Kind, sessionID: String, turnID: String,
                                      toolCallID: String?, toolName: String) -> String {
        let identity = [kind.rawValue, sessionID, turnID, toolCallID ?? toolName].joined(separator: "\u{0}")
        let digest = SHA256.hash(data: Data(identity.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(32))
    }

    private static func questionPreview(from input: Any?) -> String? {
        guard let object = input as? [String: Any] else { return nil }
        let candidate: String?
        if let questions = object["questions"] as? [[String: Any]] {
            candidate = questions.first?["question"] as? String
        } else {
            candidate = object["question"] as? String
        }
        guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        let normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let lower = normalized.lowercased()
        let sensitiveMarkers = ["/users/", "/home/", "api_key", "api-key", "token=", "secret", "password", "bearer "]
        guard !sensitiveMarkers.contains(where: lower.contains) else { return nil }
        return String(normalized.prefix(240))
    }

    private static func activity(for toolName: String, input: Any?) -> ToolActivity {
        let lower = toolName.lowercased()
        if toolName == "Bash" || lower == "shell_command" {
            return shellActivity(command: (input as? [String: Any])?["command"] as? String)
        }
        if ["apply_patch", "edit", "write"].contains(lower) {
            return ToolActivity(category: .edit, summary: "Editing files", symbol: "pencil")
        }
        if lower.contains("read") || lower.contains("list") {
            return ToolActivity(category: .read, summary: "Reading project files", symbol: "doc.text")
        }
        if lower.contains("search") || lower.contains("find") || lower == "grep" || lower == "glob" {
            return ToolActivity(category: .other, summary: "Searching project files", symbol: "magnifyingglass")
        }
        return ToolActivity(category: .other, summary: "Using Codex tool", symbol: "sparkles")
    }

    private static func shellActivity(command: String?) -> ToolActivity {
        guard let command, command.utf8.count <= 4_096,
              !command.contains(where: { ";|&<>$`\n\r".contains($0) }) else {
            return ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        }
        let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else {
            return ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        }
        let executable = URL(fileURLWithPath: first).lastPathComponent.lowercased()
        let arguments = words.dropFirst().map { $0.lowercased() }
        let argSet = Set(arguments)

        func activity(_ category: ToolCategory, _ summary: String, _ symbol: String) -> ToolActivity {
            ToolActivity(category: category, summary: summary, symbol: symbol)
        }
        if executable == "xcodebuild" {
            if argSet.contains("test") { return activity(.test, "Running Xcode tests", "checkmark.circle") }
            if argSet.contains("build") { return activity(.shell, "Building project", "terminal") }
        }
        if executable == "swift" {
            if arguments.first == "test" { return activity(.test, "Running Swift tests", "checkmark.circle") }
            if arguments.first == "build" { return activity(.shell, "Building project", "terminal") }
        }
        let isJavaScriptTest = arguments.first == "test"
            || (arguments.count > 1 && arguments[0] == "run" && arguments[1] == "test")
        if ["npm", "pnpm", "yarn", "bun"].contains(executable), isJavaScriptTest {
            return activity(.test, "Running JavaScript tests", "checkmark.circle")
        }
        if ["pytest", "tox"].contains(executable) || (executable == "python" || executable == "python3") && argSet.contains("pytest") {
            return activity(.test, "Running Python tests", "checkmark.circle")
        }
        if (executable == "cargo" && arguments.first == "test")
            || (executable == "go" && arguments.first == "test")
            || (executable == "make" && arguments.contains("test")) {
            return activity(.test, "Running project tests", "checkmark.circle")
        }
        if executable == "git", let subcommand = arguments.first {
            if ["status", "diff"].contains(subcommand) {
                return activity(.shell, "Checking Git changes", "terminal")
            }
            if ["show", "log"].contains(subcommand) {
                return activity(.shell, "Reading project files", "terminal")
            }
        }
        if ["rg", "grep", "fd", "find"].contains(executable) {
            return activity(.shell, "Searching project files", "terminal")
        }
        if ["cat", "sed", "head", "tail", "ls", "pwd"].contains(executable) {
            return activity(.shell, "Reading project files", "terminal")
        }
        if ["mkdir", "cp", "mv", "touch", "rm"].contains(executable) {
            return activity(.shell, "Updating project files", "terminal")
        }
        return activity(.shell, "Running command", "terminal")
    }
}

enum HookPayloadError: Error, Equatable {
    case inputTooLarge
    case invalidShape
    case missingIdentity
}
