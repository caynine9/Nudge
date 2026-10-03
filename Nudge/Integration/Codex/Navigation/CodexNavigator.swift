import AppKit

enum CodexThreadDeepLink {
    // Codex Desktop documents codex://threads/<thread-id> for local chats.
    static func url(sessionID: String) -> URL? {
        guard !sessionID.isEmpty, sessionID.utf8.count <= 256,
              !sessionID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let encodedID = sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathSegment) else {
            return nil
        }
        return URL(string: "codex://threads/\(encodedID)")
    }
}

enum SessionOpenOutcome: Equatable {
    case threadRouteAcceptedByOS
    case desktopActivatedFallback
}

private extension CharacterSet {
    static let urlPathSegment = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

@MainActor
struct CodexNavigator {
    func open(_ host: CodexHost) async throws {
        guard host == .desktop else { throw NavigationError.unsupportedHost(host.title) }
        try await activateDesktop()
    }

    func openSession(_ sessionID: String) async throws -> SessionOpenOutcome {
        guard let url = CodexThreadDeepLink.url(sessionID: sessionID) else {
            throw NavigationError.invalidSessionIdentifier
        }
        if NSWorkspace.shared.open(url) { return .threadRouteAcceptedByOS }
        try await activateDesktop()
        return .desktopActivatedFallback
    }

    private func activateDesktop() async throws {
        let host = CodexHost.desktop
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
        case invalidSessionIdentifier
        var errorDescription: String? {
            switch self {
            case let .notInstalled(name): "\(name) is unavailable. Open the app, then try again."
            case let .unsupportedHost(name): "Nudge cannot route to a \(name) terminal session yet."
            case .invalidSessionIdentifier: "Nudge could not open this Codex chat because its session ID is invalid."
            }
        }
    }
}
