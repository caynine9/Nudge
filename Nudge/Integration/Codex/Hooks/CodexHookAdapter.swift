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
        case .preToolUse, .postToolUse:
            guard turnID != nil,
                  let identifier = boundedString(object["tool_use_id"], maximumBytes: WireEnvelope.maximumIdentifierBytes),
                  let rawToolName = object["tool_name"] as? String,
                  rawToolName.utf8.count <= 128 else { throw HookPayloadError.missingIdentity }
            toolCallID = identifier
            if expectedEvent == .preToolUse {
                tool = Self.activity(for: rawToolName, input: object["tool_input"])
            }
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
