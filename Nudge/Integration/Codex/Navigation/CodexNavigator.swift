import AppKit

enum CodexHost: String, CaseIterable, Identifiable {
    case desktop, terminal
    var id: String { rawValue }
    var title: String { self == .desktop ? "Desktop" : "Terminal" }
    var bundleIdentifier: String { self == .desktop ? "com.openai.codex" : "com.apple.Terminal" }
}

// M0 activation only. No fabricated thread URL or terminal tab identity.
@MainActor
struct CodexNavigator {
    func open(_ host: CodexHost) async throws {
        let workspace = NSWorkspace.shared
        if let running = workspace.runningApplications.first(where: { $0.bundleIdentifier == host.bundleIdentifier }),
           running.activate(options: [.activateAllWindows]) {
            return
        }
        guard let url = workspace.urlForApplication(withBundleIdentifier: host.bundleIdentifier) else {
            throw NavigationError.notInstalled(host.title)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await workspace.openApplication(at: url, configuration: configuration)
    }

    enum NavigationError: LocalizedError {
        case notInstalled(String)
        var errorDescription: String? {
            switch self {
            case let .notInstalled(name): "\(name) is unavailable. Open the app, then try again."
            }
        }
    }
}
