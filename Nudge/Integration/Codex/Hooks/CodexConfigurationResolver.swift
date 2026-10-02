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
    var resolutionIssue: String? = nil

    var hooksFile: URL { codexHome.appendingPathComponent("hooks.json", isDirectory: false) }
}

struct CodexConfigurationResolver {
    func target(for host: CodexHost, environment: [String: String] = ProcessInfo.processInfo.environment,
                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                explicitCodexHome: URL? = nil) -> CodexConfigurationTarget {
        let root: URL
        let confidence: String
        var issue: String?
        if let explicitCodexHome {
            root = explicitCodexHome.standardizedFileURL
            confidence = "user-selected"
            if !isExistingDirectory(root) {
                issue = "The selected Codex configuration folder is unavailable. Choose an existing folder before continuing."
            }
        } else if let custom = environment["CODEX_HOME"], !custom.isEmpty {
            if custom.hasPrefix("/") {
                root = URL(fileURLWithPath: custom, isDirectory: true).standardizedFileURL
                confidence = host == .cli ? "CODEX_HOME environment candidate" : "Nudge CODEX_HOME; Desktop unverified"
                if !isExistingDirectory(root) {
                    issue = "CODEX_HOME points to a folder that does not exist. Create or select the intended Codex folder before continuing."
                }
            } else {
                root = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
                confidence = "invalid CODEX_HOME"
                issue = "CODEX_HOME must be an absolute path. Nudge will not fall back to the default Codex folder."
            }
        } else {
            root = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
            confidence = "default candidate"
        }
        return CodexConfigurationTarget(host: host, codexHome: root, confidence: confidence, resolutionIssue: issue)
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
