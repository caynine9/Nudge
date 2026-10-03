import AppKit
import Foundation
import OSLog

enum CodexThreadDeepLink {
    static func url(threadID: String) -> URL? {
        guard !threadID.isEmpty,
              threadID != "new",
              threadID != ".",
              threadID != "..",
              threadID.utf8.count <= 256,
              !threadID.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let encodedID = threadID.addingPercentEncoding(withAllowedCharacters: .codexPathSegment)
        else { return nil }

        return URL(string: "codex://threads/\(encodedID)")
    }
}

private extension CharacterSet {
    static let codexPathSegment = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

enum CodexNavigationFallbackReason: String, Equatable, Sendable {
    case preciseNavigationDisabled
    case threadIdentityUnavailable
    case invalidThreadIdentifier
    case targetApplicationUnavailable
    case routeRejected
    case routeTimedOut
    case activationOnlyRecovery
}

enum CodexNavigationOutcome: Equatable, Sendable {
    /// The native workspace accepted the URL for delivery. This does not prove
    /// that the target thread exists or that Codex displayed it.
    case threadRouteDispatched
    case desktopActivated(CodexNavigationFallbackReason)
}

struct CodexNavigationContext: Equatable, Sendable {
    let sessionID: String
    let turnID: String
    let interactionID: String?

    init(sessionID: String, turnID: String, interactionID: String?) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.interactionID = interactionID
    }

    func matches(sessionID: String, turnID: String, interactionID: String?) -> Bool {
        self.sessionID == sessionID && self.turnID == turnID && self.interactionID == interactionID
    }
}

@MainActor
final class CodexNavigationSettings {
    static let preciseNavigationKey = "usePreciseCodexThreadNavigation"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var usePreciseThreadNavigation: Bool {
        get { defaults.object(forKey: Self.preciseNavigationKey) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Self.preciseNavigationKey) }
    }
}

@MainActor
protocol CodexWorkspaceClient {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
    func open(_ url: URL, in applicationURL: URL) async throws
    func activate(bundleIdentifier: String) async throws
}

@MainActor
struct SystemCodexWorkspaceClient: CodexWorkspaceClient {
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    func open(_ url: URL, in applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: applicationURL,
                                              configuration: configuration)
    }

    func activate(bundleIdentifier: String) async throws {
        let workspace = NSWorkspace.shared
        if let application = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }), application.activate(options: []) {
            return
        }

        guard let applicationURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw CodexNavigator.NavigationError.notInstalled
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await workspace.openApplication(at: applicationURL, configuration: configuration)
    }
}

private enum WorkspaceOperationResult: Sendable {
    case succeeded
    case failed
    case timedOut
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resolve(_ value: Value) {
        lock.lock()
        let continuation = self.continuation
        let timeoutTask = self.timeoutTask
        self.continuation = nil
        self.timeoutTask = nil
        lock.unlock()
        timeoutTask?.cancel()
        continuation?.resume(returning: value)
    }

    func install(timeoutTask: Task<Void, Never>) {
        lock.lock()
        let alreadyResolved = continuation == nil
        if !alreadyResolved { self.timeoutTask = timeoutTask }
        lock.unlock()
        if alreadyResolved { timeoutTask.cancel() }
    }
}

@MainActor
struct CodexNavigator {
    static let bundleIdentifier = "com.openai.codex"
    static let routeTimeoutNanoseconds: UInt64 = 2_000_000_000
    static let activationTimeoutNanoseconds: UInt64 = 5_000_000_000
    static let totalNavigationBudgetNanoseconds: UInt64 = 5_000_000_000

    private let workspace: any CodexWorkspaceClient
    private let logger = Logger(subsystem: "com.nudge.Nudge", category: "navigation")
    private let routeTimeoutNanoseconds: UInt64
    private let activationTimeoutNanoseconds: UInt64

    init(workspace: (any CodexWorkspaceClient)? = nil,
         routeTimeoutNanoseconds: UInt64 = 2_000_000_000,
         activationTimeoutNanoseconds: UInt64 = 5_000_000_000) {
        self.workspace = workspace ?? SystemCodexWorkspaceClient()
        self.routeTimeoutNanoseconds = max(1, routeTimeoutNanoseconds)
        self.activationTimeoutNanoseconds = max(1, activationTimeoutNanoseconds)
    }

    func openDesktop(threadID: String?, preciseNavigationEnabled: Bool,
                     activationOnly: Bool = false) async throws -> CodexNavigationOutcome {
        var fallbackReason: CodexNavigationFallbackReason
        let navigationStartedAt = DispatchTime.now().uptimeNanoseconds

        if activationOnly {
            fallbackReason = .activationOnlyRecovery
        } else if !preciseNavigationEnabled {
            fallbackReason = .preciseNavigationDisabled
        } else if let threadID {
            guard let url = CodexThreadDeepLink.url(threadID: threadID) else {
                fallbackReason = .invalidThreadIdentifier
                return try await activateDesktop(reason: fallbackReason,
                                                  timeout: remainingActivationBudget(since: navigationStartedAt))
            }

            guard let applicationURL = workspace.applicationURL(forBundleIdentifier: Self.bundleIdentifier) else {
                fallbackReason = .targetApplicationUnavailable
                return try await activateDesktop(reason: fallbackReason,
                                                  timeout: remainingActivationBudget(since: navigationStartedAt))
            }

            let startedAt = DispatchTime.now().uptimeNanoseconds
            switch await withDeadline(routeTimeoutNanoseconds, operation: {
                try await workspace.open(url, in: applicationURL)
            }) {
            case .succeeded:
                log("thread_route_dispatched", startedAt: startedAt)
                return .threadRouteDispatched
            case .failed:
                fallbackReason = .routeRejected
            case .timedOut:
                fallbackReason = .routeTimedOut
            }
        } else {
            fallbackReason = .threadIdentityUnavailable
        }

        return try await activateDesktop(reason: fallbackReason,
                                         timeout: remainingActivationBudget(since: navigationStartedAt))
    }

    private func activateDesktop(reason: CodexNavigationFallbackReason,
                                 timeout: UInt64) async throws -> CodexNavigationOutcome {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        switch await withDeadline(timeout, operation: {
            try await workspace.activate(bundleIdentifier: Self.bundleIdentifier)
        }) {
        case .succeeded:
            logger.info("Desktop activated; fallback=\(reason.rawValue, privacy: .public)")
            log("desktop_activated", startedAt: startedAt)
            return .desktopActivated(reason)
        case .failed, .timedOut:
            logger.error("Desktop activation failed; fallback=\(reason.rawValue, privacy: .public)")
            throw NavigationError.activationFailed
        }
    }

    private func remainingActivationBudget(since startedAt: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= startedAt ? now - startedAt : 0
        let remaining = elapsed < Self.totalNavigationBudgetNanoseconds
            ? Self.totalNavigationBudgetNanoseconds - elapsed
            : 1
        return max(1, min(activationTimeoutNanoseconds, remaining))
    }

    private func withDeadline(
        _ timeout: UInt64,
        operation: @escaping @MainActor () async throws -> Void
    ) async -> WorkspaceOperationResult {
        await withCheckedContinuation { continuation in
            let gate = ContinuationGate(continuation)

            Task { @MainActor in
                do {
                    try await operation()
                    gate.resolve(.succeeded)
                } catch {
                    gate.resolve(.failed)
                }
            }

            let timeoutTask = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: timeout)
                    gate.resolve(.timedOut)
                } catch {
                    // The operation or deadline already won the race.
                }
            }
            gate.install(timeoutTask: timeoutTask)
        }
    }

    private func log(_ event: String, startedAt: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsedMilliseconds = now >= startedAt ? (now - startedAt) / 1_000_000 : 0
        logger.info("\(event, privacy: .public); elapsed_ms=\(elapsedMilliseconds, privacy: .public)")
    }

    enum NavigationError: LocalizedError {
        case notInstalled
        case activationFailed

        var errorDescription: String? {
            switch self {
            case .notInstalled: "Codex Desktop is unavailable. Open the app, then try again."
            case .activationFailed: "Could not open Codex Desktop. Open it, then try again."
            }
        }
    }
}
