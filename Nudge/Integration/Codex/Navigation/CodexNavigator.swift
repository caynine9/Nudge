import AppKit

// M0 activation only. No fabricated thread URL or terminal tab identity.
@MainActor
struct CodexNavigator {
    func open(_ host: CodexHost) async throws {
        guard host == .desktop else { throw NavigationError.unsupportedHost(host.title) }
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
        case unsupportedHost(String)
        var errorDescription: String? {
            switch self {
            case let .notInstalled(name): "\(name) is unavailable. Open the app, then try again."
            case let .unsupportedHost(name): "Nudge cannot route to a \(name) terminal session yet."
            }
        }
    }
}
