import Foundation

enum CodexHost: String, CaseIterable, Identifiable, Sendable {
    case desktop
    case cli

    var id: String { rawValue }
    var title: String { self == .desktop ? "Codex Desktop" : "Codex CLI" }
    var bundleIdentifier: String { "com.openai.codex" }
}

struct CodexConfigurationTarget: Equatable, Sendable {
    let host: CodexHost
    let codexHome: URL
    let confidence: String

    var hooksFile: URL { codexHome.appendingPathComponent("hooks.json", isDirectory: false) }
}

struct CodexConfigurationResolver {
    func target(for host: CodexHost, environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                explicitCodexHome: URL? = nil) -> CodexConfigurationTarget {
        let root: URL
        let confidence: String
        if let explicitCodexHome {
            root = explicitCodexHome.standardizedFileURL
            confidence = "user-selected"
        } else if let custom = environment["CODEX_HOME"], !custom.isEmpty, custom.hasPrefix("/") {
            root = URL(fileURLWithPath: custom, isDirectory: true).standardizedFileURL
            confidence = host == .cli ? "CODEX_HOME environment candidate" : "Nudge CODEX_HOME; Desktop unverified"
        } else {
            root = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
            confidence = "default candidate"
        }
        return CodexConfigurationTarget(host: host, codexHome: root, confidence: confidence)
    }
}
