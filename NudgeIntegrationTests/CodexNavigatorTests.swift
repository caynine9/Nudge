import XCTest

@MainActor
final class CodexNavigatorTests: XCTestCase {
    func testThreadIDsBecomeOneEncodedLocalChatPathSegment() throws {
        let ordinary = try XCTUnwrap(CodexThreadDeepLink.url(
            threadID: "01a0fcb0-0000-4000-8000-aabbccddeeff"
        ))
        XCTAssertEqual(ordinary.absoluteString,
                       "codex://threads/01a0fcb0-0000-4000-8000-aabbccddeeff")

        let opaque = try XCTUnwrap(CodexThreadDeepLink.url(threadID: "session:part/with space"))
        XCTAssertEqual(opaque.absoluteString, "codex://threads/session%3Apart%2Fwith%20space")
    }

    func testReservedOrMalformedThreadIDsAreRejected() {
        XCTAssertNil(CodexThreadDeepLink.url(threadID: ""))
        XCTAssertNil(CodexThreadDeepLink.url(threadID: "new"))
        XCTAssertNil(CodexThreadDeepLink.url(threadID: "."))
        XCTAssertNil(CodexThreadDeepLink.url(threadID: ".."))
        XCTAssertNil(CodexThreadDeepLink.url(threadID: "thread\nid"))
        XCTAssertNil(CodexThreadDeepLink.url(threadID: String(repeating: "x", count: 257)))
    }

    func testPreciseNavigationOffOnlyActivatesDesktop() async throws {
        let workspace = FakeCodexWorkspaceClient()
        let navigator = CodexNavigator(workspace: workspace)

        let result = try await navigator.openDesktop(threadID: "thread-id", preciseNavigationEnabled: false)

        XCTAssertEqual(result, .desktopActivated(.preciseNavigationDisabled))
        XCTAssertTrue(workspace.openedURLs.isEmpty)
        XCTAssertEqual(workspace.activatedBundleIdentifiers, [CodexNavigator.bundleIdentifier])
    }

    func testMissingIdentityUsesActivationFallback() async throws {
        let workspace = FakeCodexWorkspaceClient()
        let navigator = CodexNavigator(workspace: workspace)

        let result = try await navigator.openDesktop(threadID: nil, preciseNavigationEnabled: true)

        XCTAssertEqual(result, .desktopActivated(.threadIdentityUnavailable))
        XCTAssertTrue(workspace.openedURLs.isEmpty)
        XCTAssertEqual(workspace.activatedBundleIdentifiers.count, 1)
    }

    func testReservedIdentityNeverDispatchesANewThreadRoute() async throws {
        let workspace = FakeCodexWorkspaceClient()
        let navigator = CodexNavigator(workspace: workspace)

        let result = try await navigator.openDesktop(threadID: "new", preciseNavigationEnabled: true)

        XCTAssertEqual(result, .desktopActivated(.invalidThreadIdentifier))
        XCTAssertTrue(workspace.openedURLs.isEmpty)
        XCTAssertEqual(workspace.activatedBundleIdentifiers.count, 1)
    }

    func testAcceptedRouteIsTargetedAndDoesNotClaimTheThreadWasDisplayed() async throws {
        let workspace = FakeCodexWorkspaceClient()
        let navigator = CodexNavigator(workspace: workspace)

        let result = try await navigator.openDesktop(threadID: "thread-id", preciseNavigationEnabled: true)

        XCTAssertEqual(result, .threadRouteDispatched)
        XCTAssertEqual(workspace.openedURLs.map(\.absoluteString), ["codex://threads/thread-id"])
        XCTAssertEqual(workspace.targetApplicationURLs, [FakeCodexWorkspaceClient.applicationURL])
        XCTAssertTrue(workspace.activatedBundleIdentifiers.isEmpty)
    }

    func testRouteRejectionFallsBackToOneDesktopActivation() async throws {
        let workspace = FakeCodexWorkspaceClient()
        workspace.rejectsRoute = true
        let navigator = CodexNavigator(workspace: workspace)

        let result = try await navigator.openDesktop(threadID: "thread-id", preciseNavigationEnabled: true)

        XCTAssertEqual(result, .desktopActivated(.routeRejected))
        XCTAssertEqual(workspace.openedURLs.count, 1)
        XCTAssertEqual(workspace.activatedBundleIdentifiers.count, 1)
    }

    func testRouteTimeoutFallsBackAndLateRouteCompletionDoesNotChangeTheOutcome() async throws {
        let workspace = FakeCodexWorkspaceClient()
        workspace.routeDelayNanoseconds = 80_000_000
        let navigator = CodexNavigator(workspace: workspace, routeTimeoutNanoseconds: 1_000_000,
                                       activationTimeoutNanoseconds: 100_000_000)

        let result = try await navigator.openDesktop(threadID: "thread-id", preciseNavigationEnabled: true)

        XCTAssertEqual(result, .desktopActivated(.routeTimedOut))
        XCTAssertEqual(workspace.openedURLs.count, 1)
        XCTAssertEqual(workspace.activatedBundleIdentifiers.count, 1)
    }

    func testActivationFailureReturnsAFiniteError() async {
        let workspace = FakeCodexWorkspaceClient()
        workspace.activationFails = true
        let navigator = CodexNavigator(workspace: workspace)

        do {
            _ = try await navigator.openDesktop(threadID: nil, preciseNavigationEnabled: false)
            XCTFail("Expected an activation error")
        } catch let error as CodexNavigator.NavigationError {
            XCTAssertEqual(error.localizedDescription,
                           "Could not open Codex Desktop. Open it, then try again.")
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testPreciseNavigationPreferenceDefaultsOffAndPersistsInItsStore() {
        let suiteName = "NudgeNavigationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = CodexNavigationSettings(defaults: defaults)

        XCTAssertFalse(settings.usePreciseThreadNavigation)
        settings.usePreciseThreadNavigation = true

        XCTAssertTrue(CodexNavigationSettings(defaults: defaults).usePreciseThreadNavigation)
    }

    func testNavigationFeedbackBelongsOnlyToTheCapturedSessionTurnAndInteraction() {
        let context = CodexNavigationContext(sessionID: "session-a", turnID: "turn-a", interactionID: "question-a")

        XCTAssertTrue(context.matches(sessionID: "session-a", turnID: "turn-a", interactionID: "question-a"))
        XCTAssertFalse(context.matches(sessionID: "session-b", turnID: "turn-a", interactionID: "question-a"))
        XCTAssertFalse(context.matches(sessionID: "session-a", turnID: "turn-b", interactionID: "question-a"))
        XCTAssertFalse(context.matches(sessionID: "session-a", turnID: "turn-a", interactionID: nil))
    }
}

@MainActor
private final class FakeCodexWorkspaceClient: CodexWorkspaceClient {
    static let applicationURL = URL(fileURLWithPath: "/Applications/Codex.app")

    var resolvedApplicationURL: URL? = applicationURL
    var rejectsRoute = false
    var activationFails = false
    var routeDelayNanoseconds: UInt64 = 0
    var activationDelayNanoseconds: UInt64 = 0
    private(set) var openedURLs: [URL] = []
    private(set) var targetApplicationURLs: [URL] = []
    private(set) var activatedBundleIdentifiers: [String] = []

    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        XCTAssertEqual(bundleIdentifier, CodexNavigator.bundleIdentifier)
        return resolvedApplicationURL
    }

    func open(_ url: URL, in applicationURL: URL) async throws {
        openedURLs.append(url)
        targetApplicationURLs.append(applicationURL)
        if routeDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: routeDelayNanoseconds)
        }
        if rejectsRoute { throw FakeError.operationFailed }
    }

    func activate(bundleIdentifier: String) async throws {
        activatedBundleIdentifiers.append(bundleIdentifier)
        if activationDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: activationDelayNanoseconds)
        }
        if activationFails { throw FakeError.operationFailed }
    }

    private enum FakeError: Error {
        case operationFailed
    }
}
