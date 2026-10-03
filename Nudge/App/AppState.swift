import Combine
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var presentation = PresentationState()
    @Published private(set) var celebrationPulse = 0
    @Published private(set) var attentionPulse = 0
    @Published private(set) var reduceMotion = false
    @Published private(set) var isDemoMode = false
    @Published var wantsPanelVisible = true
    @Published var host: CodexHost = .desktop
    @Published var integrationHost: CodexHost = .desktop
    @Published private(set) var isOpeningHost = false
    @Published private(set) var navigationIssue: String?
    @Published private(set) var navigationFailed = false
    @Published private(set) var navigationRecoveryAvailable = false
    @Published private(set) var usePreciseThreadNavigation = false
    @Published var permissionActionsEnabled = UserDefaults.standard.bool(forKey: "permissionActionsEnabled")
    @Published private(set) var integrationStatus = "Waiting for Codex hooks."
    @Published private(set) var socketStatus = "Starting local event listener…"
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var observedHookEvents: Set<CodexHookEvent> = []
    @Published private(set) var activeSessions: [ActivitySnapshot] = []
    @Published private(set) var sessionTitles: [String: String] = [:]
    @Published private(set) var codexUsage: CodexUsageSnapshot?
    @Published private(set) var isCodexUsageLoading = false
    @Published private(set) var isCodexUsageUnavailable = false
    @Published private(set) var selectedLiveSessionID: String?
    @Published private(set) var permissionActionStatuses: [String: PermissionActionStatus] = [:]
    @Published private(set) var permissionActionRequests: [String: PermissionRequestMessage] = [:]

    private let reducer = PresentationReducer()
    private let codexNavigator: CodexNavigator
    private var permissionBroker: PermissionBroker?
    private let navigationSettings: CodexNavigationSettings
    private var scheduled: [PresentationTimer: Task<Void, Never>] = [:]
    private var activeNavigationID: UUID?
    private var navigationFeedbackContext: CodexNavigationContext?
    private var turnNumber = 1
    private var lastAttentionIdentity: String?
    private var latestLiveSnapshot = ActivityMonitorSnapshot.empty
    private var codexMetadataReader: CodexThreadMetadataReader?
    private var lastCodexUsageRefreshAt: Date?
    private var selectedCodexHomes: [String: String] =
        UserDefaults.standard.dictionary(forKey: "selectedCodexHomes") as? [String: String] ?? [:]

    init(presentation: PresentationState? = nil, navigationIssue: String? = nil,
         activeSessions: [ActivitySnapshot] = [], sessionTitles: [String: String] = [:],
         codexNavigator: CodexNavigator? = nil,
         navigationSettings: CodexNavigationSettings? = nil) {
        let settings = navigationSettings ?? CodexNavigationSettings()
        self.navigationSettings = settings
        self.codexNavigator = codexNavigator ?? CodexNavigator()
        self.usePreciseThreadNavigation = settings.usePreciseThreadNavigation
        if let presentation { self.presentation = presentation }
        else { self.presentation.snapshot = .empty }
        self.navigationIssue = navigationIssue
        self.activeSessions = activeSessions
        self.sessionTitles = sessionTitles
    }

    func choose(_ phase: SessionPhase) {
        guard isDemoMode else { return }
        navigationIssue = nil
        navigationFailed = false
        navigationRecoveryAvailable = false
        navigationFeedbackContext = nil
        dispatch(.snapshotChanged(PlaygroundScenario.snapshot(turn: turnNumber, phase: phase)))
    }

    func beginNewTurn() {
        guard isDemoMode else { return }
        turnNumber += 1
        navigationIssue = nil
        navigationFailed = false
        navigationRecoveryAvailable = false
        navigationFeedbackContext = nil
        dispatch(.snapshotChanged(PlaygroundScenario.snapshot(turn: turnNumber, phase: .thinking)))
    }

    func resolvePreview(_ feedback: InteractionFeedback) {
        guard isDemoMode, presentation.snapshot.phase.isAttention else { return }
        let phase: SessionPhase = feedback.kind == .denied ? .interrupted : .toolUse
        dispatch(.previewInteractionResolved(PlaygroundScenario.snapshot(turn: turnNumber, phase: phase), feedback))
    }

    func setDemoMode(_ enabled: Bool) {
        guard isDemoMode != enabled else { return }
        isDemoMode = enabled
        navigationIssue = nil
        navigationFailed = false
        navigationRecoveryAvailable = false
        navigationFeedbackContext = nil
        if enabled {
            activeNavigationID = nil
            isOpeningHost = false
        }
        if enabled {
            dispatch(.snapshotChanged(PlaygroundScenario.snapshot(turn: turnNumber, phase: .thinking)))
        } else {
            dispatch(.snapshotChanged(presentationSnapshot(from: latestLiveSnapshot)))
        }
    }

    func updateLiveSnapshot(_ snapshot: ActivitySnapshot) {
        updateLiveSnapshot(ActivityMonitorSnapshot(
            focused: snapshot,
            activeSessions: snapshot.phase.isActive ? [snapshot] : []
        ))
    }

    func updateLiveSnapshot(_ snapshot: ActivityMonitorSnapshot, observedEvent: CodexHookEvent? = nil) {
        latestLiveSnapshot = snapshot
        activeSessions = snapshot.activeSessions
        let pendingPermissionIDs = Set(snapshot.activeSessions.flatMap(\.pendingInteractions)
            .filter { $0.kind == .permission }.map(\.id))
        permissionActionStatuses = permissionActionStatuses.filter { pendingPermissionIDs.contains($0.key) }
        permissionActionRequests = permissionActionRequests.filter { pendingPermissionIDs.contains($0.key) }
        sessionTitles = sessionTitles.filter { id, _ in snapshot.activeSessions.contains { $0.sessionID == id } }
        if let observedEvent { observedHookEvents.insert(observedEvent) }
        if let selectedLiveSessionID,
           !snapshot.activeSessions.contains(where: { $0.sessionID == selectedLiveSessionID }) {
            self.selectedLiveSessionID = nil
        }
        lastEventAt = Date()
        if !isDemoMode {
            dispatch(.snapshotChanged(presentationSnapshot(from: snapshot)))
            clearStaleNavigationFeedback()
        }
    }

    func reconcileLiveSnapshotAfterWake(_ snapshot: ActivityMonitorSnapshot) {
        latestLiveSnapshot = snapshot
        activeSessions = snapshot.activeSessions
        let pendingPermissionIDs = Set(snapshot.activeSessions.flatMap(\.pendingInteractions)
            .filter { $0.kind == .permission }.map(\.id))
        permissionActionStatuses = permissionActionStatuses.filter { pendingPermissionIDs.contains($0.key) }
        permissionActionRequests = permissionActionRequests.filter { pendingPermissionIDs.contains($0.key) }
        sessionTitles = sessionTitles.filter { id, _ in snapshot.activeSessions.contains { $0.sessionID == id } }
        if let selectedLiveSessionID,
           !snapshot.activeSessions.contains(where: { $0.sessionID == selectedLiveSessionID }) {
            self.selectedLiveSessionID = nil
        }
        if !isDemoMode {
            dispatch(.snapshotChanged(presentationSnapshot(from: snapshot)))
            clearStaleNavigationFeedback()
        }
    }

    func selectLiveSession(_ sessionID: String) {
        guard activeSessions.contains(where: { $0.sessionID == sessionID }) else { return }
        selectedLiveSessionID = sessionID
        if !isDemoMode { dispatch(.snapshotChanged(presentationSnapshot(from: latestLiveSnapshot))) }
    }

    func setSessionTitle(_ title: String, for sessionID: String) {
        guard activeSessions.contains(where: { $0.sessionID == sessionID }),
              sessionTitles[sessionID] != title else { return }
        sessionTitles[sessionID] = title
    }

    func configureCodexMetadataReader(_ reader: CodexThreadMetadataReader) {
        codexMetadataReader = reader
    }

    func refreshCodexUsageIfNeeded() {
        guard !isDemoMode, !isCodexUsageLoading, let codexMetadataReader else { return }
        let cooldown: TimeInterval = codexUsage == nil ? 60 : 300
        if let lastCodexUsageRefreshAt,
           Date().timeIntervalSince(lastCodexUsageRefreshAt) < cooldown { return }

        let selectedPath = selectedCodexHomes[CodexHost.desktop.rawValue]
            ?? ProcessInfo.processInfo.environment["CODEX_HOME"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        guard selectedPath.hasPrefix("/") else {
            codexUsage = nil
            isCodexUsageUnavailable = true
            lastCodexUsageRefreshAt = Date()
            return
        }

        isCodexUsageLoading = true
        isCodexUsageUnavailable = false
        let home = URL(fileURLWithPath: selectedPath, isDirectory: true)
        Task { [weak self] in
            let snapshot = await codexMetadataReader.usage(for: home)
            guard let self else { return }
            self.codexUsage = snapshot
            self.isCodexUsageUnavailable = snapshot == nil
            self.isCodexUsageLoading = false
            self.lastCodexUsageRefreshAt = Date()
        }
    }

    func toggleAttentionSessionList() {
        guard !isDemoMode, presentation.snapshot.phase.isAttention else { return }
        dispatch(.toggleSessionList)
    }

    func openAttentionInCodex() {
        guard !isDemoMode, presentation.snapshot.phase.isAttention else { return }
        if let interactionID = presentation.snapshot.pendingInteraction?.id {
            Task { await permissionBroker?.returnToCodex(interactionID: interactionID) }
        }
        navigate(to: presentation.snapshot, activationOnly: false, collapseOnSuccess: false)
    }

    func configurePermissionBroker(_ broker: PermissionBroker) {
        permissionBroker = broker
    }

    func permissionActionStatus(for interactionID: String?) -> PermissionActionStatus? {
        guard let interactionID else { return nil }
        return permissionActionStatuses[interactionID]
    }

    func permissionSummary(for interactionID: String?) -> String? {
        guard let interactionID else { return nil }
        return permissionActionRequests[interactionID]?.summary
    }

    func decidePermission(interactionID: String, decision: PermissionDecision) {
        guard !isDemoMode, permissionActionsEnabled, let broker = permissionBroker,
              presentation.snapshot.phase == .waitingPermission,
              let interaction = presentation.snapshot.pendingInteraction,
              interaction.id == interactionID else { return }
        if let request = permissionActionRequests[interactionID] {
            updatePermissionActionStatus(.sending, for: request)
        }
        let sessionID = presentation.snapshot.sessionID
        let turnID = presentation.snapshot.turnID
        Task {
            _ = await broker.decide(interactionID: interactionID, sessionID: sessionID,
                                    turnID: turnID, decision: decision)
        }
    }

    func isCurrentPermissionRequest(_ request: PermissionRequestMessage) -> Bool {
        guard permissionActionsEnabled, !isDemoMode,
              presentation.snapshot.phase == .waitingPermission,
              presentation.snapshot.sessionID == request.sessionID,
              presentation.snapshot.turnID == request.turnID,
              let interaction = presentation.snapshot.pendingInteraction else { return false }
        return interaction.kind == .permission && interaction.id == request.interactionID
    }

    func updatePermissionActionStatus(_ status: PermissionActionStatus, for request: PermissionRequestMessage) {
        if let previous = permissionActionStatuses[request.interactionID],
           !Self.canTransitionPermissionStatus(from: previous, to: status) { return }
        permissionActionStatuses[request.interactionID] = status
        permissionActionRequests[request.interactionID] = request
    }

    private static func canTransitionPermissionStatus(from previous: PermissionActionStatus,
                                                      to next: PermissionActionStatus) -> Bool {
        switch previous {
        case .queued: return next != .queued
        case .available: return next != .queued && next != .available
        case .sending: return next != .queued && next != .available
        case .sentToCodex, .returnedToCodex, .expired, .unavailable: return false
        }
    }

    func setPermissionListenerUnavailable() {
        integrationStatus = "Permission response listener unavailable. Codex native approval remains available."
    }

    func openLiveSession(_ sessionID: String) {
        guard !isDemoMode, !isOpeningHost,
              let session = activeSessions.first(where: { $0.sessionID == sessionID }) else { return }
        selectedLiveSessionID = sessionID
        dispatch(.snapshotChanged(presentationSnapshot(from: latestLiveSnapshot)))
        let target = activeSessions.first(where: { $0.sessionID == sessionID }) ?? session
        navigate(to: target, activationOnly: false, collapseOnSuccess: !target.phase.isAttention)
    }

    func setPreciseThreadNavigation(_ enabled: Bool) {
        guard usePreciseThreadNavigation != enabled else { return }
        usePreciseThreadNavigation = enabled
        navigationSettings.usePreciseThreadNavigation = enabled
    }

    func setPermissionActionsEnabled(_ enabled: Bool) {
        guard permissionActionsEnabled != enabled else { return }
        permissionActionsEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "permissionActionsEnabled")
        integrationStatus = enabled
            ? "Permission actions preference enabled. Refresh hooks after verifying both host contracts."
            : "Permission actions disabled. Refresh hooks to restore mirror-only mode."
        if !enabled { Task { await permissionBroker?.cancelAll() } }
    }

    func retryCodexActivation() {
        guard !isDemoMode, !isOpeningHost, navigationRecoveryAvailable else { return }
        navigate(to: presentation.snapshot, activationOnly: true, collapseOnSuccess: false)
    }

    private func navigate(to snapshot: ActivitySnapshot, activationOnly: Bool, collapseOnSuccess: Bool) {
        guard !isOpeningHost, !isDemoMode else { return }
        let context = CodexNavigationContext(sessionID: snapshot.sessionID, turnID: snapshot.turnID,
                                             interactionID: snapshot.pendingInteraction?.id)
        let requestID = UUID()
        activeNavigationID = requestID
        isOpeningHost = true
        navigationIssue = nil
        navigationFailed = false
        navigationRecoveryAvailable = false
        navigationFeedbackContext = nil

        let candidateThreadID = snapshot.sessionID.isEmpty ? nil : snapshot.sessionID
        let usePreciseRoute = usePreciseThreadNavigation
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await codexNavigator.openDesktop(
                    threadID: candidateThreadID,
                    preciseNavigationEnabled: usePreciseRoute,
                    activationOnly: activationOnly
                )
                finishNavigation(requestID: requestID, context: context) {
                    navigationFeedbackContext = context
                    navigationRecoveryAvailable = true
                    navigationFailed = false
                    switch outcome {
                    case .threadRouteDispatched:
                        navigationIssue = "Codex Desktop accepted the chat link. Select it manually if it isn't visible."
                    case .desktopActivated:
                        navigationIssue = "Codex Desktop opened. Select the chat if it isn't visible."
                    }
                    if collapseOnSuccess && !presentation.snapshot.phase.isAttention {
                        dispatch(.collapse)
                    }
                }
            } catch {
                finishNavigation(requestID: requestID, context: context) {
                    navigationFeedbackContext = context
                    navigationRecoveryAvailable = true
                    navigationFailed = true
                    navigationIssue = (error as? CodexNavigator.NavigationError)?.localizedDescription
                        ?? "Could not open Codex Desktop. Open it, then try again."
                }
            }
        }
    }

    private func finishNavigation(requestID: UUID, context: CodexNavigationContext, apply: () -> Void) {
        guard activeNavigationID == requestID else { return }
        activeNavigationID = nil
        isOpeningHost = false
        guard !isDemoMode, context.matches(sessionID: presentation.snapshot.sessionID,
                                           turnID: presentation.snapshot.turnID,
                                           interactionID: presentation.snapshot.pendingInteraction?.id) else { return }
        apply()
    }

    private func clearStaleNavigationFeedback() {
        guard let context = navigationFeedbackContext,
              !context.matches(sessionID: presentation.snapshot.sessionID,
                               turnID: presentation.snapshot.turnID,
                               interactionID: presentation.snapshot.pendingInteraction?.id) else { return }
        navigationFeedbackContext = nil
        navigationIssue = nil
        navigationFailed = false
        navigationRecoveryAvailable = false
    }

    private func presentationSnapshot(from monitor: ActivityMonitorSnapshot) -> ActivitySnapshot {
        if let selectedLiveSessionID,
           let selected = monitor.activeSessions.first(where: { $0.sessionID == selectedLiveSessionID }),
           selected.phase.isAttention { return selected }
        if let waiting = monitor.activeSessions.first(where: { $0.phase.isAttention }) { return waiting }
        if let selectedLiveSessionID,
           let selected = monitor.activeSessions.first(where: { $0.sessionID == selectedLiveSessionID }) {
            return selected
        }
        return monitor.focused
    }

    func setSocketStatus(_ status: String) { socketStatus = status }
    func setIntegrationStatus(_ status: String) { integrationStatus = status }
    var hookObservationStatus: String {
        guard let lastEventAt else { return "No hook observed yet; trust and host coverage are unverified." }
        let observed = CodexHookEvent.allCases.filter(observedHookEvents.contains).map(\.rawValue).joined(separator: ", ")
        return "Observed hooks: \(observed). Last event at \(lastEventAt.formatted(date: .omitted, time: .shortened)); host coverage is unverified."
    }
    var toolObservationStatus: String {
        observedHookEvents.contains(.preToolUse)
            ? "PreToolUse has been observed this launch."
            : "No PreToolUse observed this launch. Check that Nudge's PreToolUse hook is reviewed and trusted in Codex (CLI: /hooks)."
    }

    func configurationTarget(for host: CodexHost) -> CodexConfigurationTarget {
        let override = selectedCodexHomes[host.rawValue].map { URL(fileURLWithPath: $0, isDirectory: true) }
        return CodexConfigurationResolver().target(for: host, explicitCodexHome: override)
    }

    func codexHomePathsForMetadata() -> [String] {
        let inherited = ProcessInfo.processInfo.environment["CODEX_HOME"]
        let fallback = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        return CodexHost.allCases.compactMap { host in
            let path = selectedCodexHomes[host.rawValue] ?? inherited ?? fallback
            return path.hasPrefix("/") ? path : nil
        }
    }

    func chooseConfigurationFolder() {
        let host = integrationHost
        let panel = NSOpenPanel()
        panel.title = "Choose \(host.title) Configuration Folder"
        panel.message = "Choose the existing CODEX_HOME folder that contains hooks.json."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.setConfigurationFolder(url, for: host) }
        }
    }

    func resetConfigurationFolder() {
        selectedCodexHomes.removeValue(forKey: integrationHost.rawValue)
        UserDefaults.standard.set(selectedCodexHomes, forKey: "selectedCodexHomes")
    }

    private func setConfigurationFolder(_ url: URL, for host: CodexHost) {
        selectedCodexHomes[host.rawValue] = url.standardizedFileURL.path
        UserDefaults.standard.set(selectedCodexHomes, forKey: "selectedCodexHomes")
        integrationStatus = "Selected config folder saved for \(host.title). Review its effective settings before installing."
    }

    func installCodexHooks() {
        let host = integrationHost
        let target = configurationTarget(for: host)
        if let issue = target.resolutionIssue {
            integrationStatus = issue
            return
        }
        guard confirmHookChange(
            title: "Install or refresh Codex hooks?",
            message: "Nudge will refresh its local bridge helper, then ensure seven lifecycle hooks are registered in:\n\(target.hooksFile.path)\n\nPermission actions are \(permissionActionsEnabled ? "ON (Allow Once/Deny, 12-second hook limit)" : "OFF (mirror only)"). Existing handlers will be preserved. An existing file is backed up before it changes. Review and trust Nudge's hooks in Codex, including PermissionRequest, PreToolUse, and PostToolUse, so activity and attention can appear. In Codex CLI, inspect them with /hooks."
        ) else { return }
        let permissionActionsEnabled = self.permissionActionsEnabled
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: HookInstallResult
            do {
                let helper = try BridgeHelperInstaller().install()
                result = CodexHookInstaller(target: target, helperPath: helper,
                                            permissionActionsEnabled: permissionActionsEnabled).install()
            } catch {
                result = .failed(error.localizedDescription)
            }
            await MainActor.run { self?.setIntegrationStatus(Self.message(for: result, host: host)) }
        }
    }

    func removeCodexHooks() {
        let host = integrationHost
        let target = configurationTarget(for: host)
        if let issue = target.resolutionIssue {
            integrationStatus = issue
            return
        }
        guard confirmHookChange(
            title: "Remove Nudge hooks?",
            message: "Nudge will remove only hook handlers owned by its exact helper command from:\n\(target.hooksFile.path)\n\nA private exact backup is created before the change. Foreign handlers and earlier backups remain."
        ) else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let helper = BridgeHelperInstaller().installedHelperURL
            let result = CodexHookInstaller(target: target, helperPath: helper).uninstall()
            await MainActor.run { self?.setIntegrationStatus(Self.message(for: result, host: host)) }
        }
    }

    private func confirmHookChange(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func message(for result: HookInstallResult, host: CodexHost) -> String {
        switch result {
        case let .installed(backup):
            "Seven hooks registered for \(host.title). Review and trust Nudge's hooks in Codex, including PermissionRequest, PreToolUse, and PostToolUse; host coverage remains unverified. Backup: \(backup.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "new file")."
        case .removed: "Nudge hooks removed from the selected config."
        case .alreadyInstalled: "The Nudge bridge helper was refreshed. Hooks were already registered, so no config rewrite was needed. Review trust and host coverage in Codex."
        case .notInstalled: "No Nudge-owned hooks were found in the selected config."
        case .malformedExistingConfig: "Config is malformed; bytes were preserved. Repair it manually before retrying."
        case let .unsupportedConfiguration(reason): reason
        case .permissionDenied: "Permission denied. Check ownership and access to the selected Codex config."
        case .conflict: "Config changed during installation; no replacement was made. Review it and retry."
        case let .failed(reason): reason
        }
    }

    func openFocusedHost() {
        guard !isOpeningHost else { return }
        let destination = host
        guard destination == .desktop else {
            navigationIssue = "Nudge cannot open a Codex CLI terminal session. Return to its terminal window."
            navigationFailed = true
            navigationRecoveryAvailable = false
            return
        }
        if !isDemoMode {
            navigate(to: presentation.snapshot, activationOnly: false,
                     collapseOnSuccess: !presentation.snapshot.phase.isAttention)
            return
        }

        isOpeningHost = true
        navigationIssue = nil
        navigationFailed = false
        navigationRecoveryAvailable = false
        navigationFeedbackContext = nil
        Task { @MainActor in
            defer { isOpeningHost = false }
            do {
                _ = try await codexNavigator.openDesktop(threadID: nil, preciseNavigationEnabled: false)
                dispatch(.collapse)
            } catch {
                navigationIssue = (error as? CodexNavigator.NavigationError)?.localizedDescription
                    ?? "Could not open Codex Desktop. Open it, then try again."
            }
        }
    }

    func dispatch(_ input: PresentationInput) {
        let transition = reducer.reduce(presentation, input)
        presentation = transition.state
        let snapshot = transition.state.snapshot
        let interaction = snapshot.pendingInteraction
        let identity = snapshot.phase.isAttention
            ? "\(snapshot.sessionID):\(snapshot.turnID):\(interaction?.id ?? "overflow"):\(snapshot.phase.rawValue)"
            : nil
        if identity != lastAttentionIdentity {
            lastAttentionIdentity = identity
            if identity != nil, !transition.state.isSleeping { attentionPulse &+= 1 }
        }
        for effect in transition.effects {
            run(effect)
        }
    }

    func setReduceMotion(_ value: Bool) {
        guard reduceMotion != value else { return }
        reduceMotion = value
    }

    func togglePanel() {
        wantsPanelVisible.toggle()
    }

    func showPanel() {
        wantsPanelVisible = true
        if !presentation.isExpanded {
            dispatch(.expand)
        }
    }

    private func run(_ effect: PresentationEffect) {
        switch effect {
        case let .schedule(timer, duration, generation):
            scheduled[timer]?.cancel()
            scheduled[timer] = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return
                }
                guard let self else { return }
                self.scheduled[timer] = nil
                self.dispatch(.timerElapsed(timer, generation: generation))
            }
        case let .cancel(timer):
            scheduled[timer]?.cancel()
            scheduled[timer] = nil
        case .celebrate:
            guard !reduceMotion else { return }
            celebrationPulse &+= 1
        }
    }
}
