import Combine
import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var presentation = PresentationState()
    @Published private(set) var celebrationPulse = 0
    @Published private(set) var reduceMotion = false
    @Published private(set) var isDemoMode = false
    @Published var wantsPanelVisible = true
    @Published var host: CodexHost = .desktop
    @Published var integrationHost: CodexHost = .desktop
    @Published private(set) var isOpeningHost = false
    @Published private(set) var navigationIssue: String?
    @Published private(set) var integrationStatus = "Waiting for Codex hooks."
    @Published private(set) var socketStatus = "Starting local event listener…"
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var observedHookEvents: Set<CodexHookEvent> = []
    @Published private(set) var activeSessions: [ActivitySnapshot] = []
    @Published private(set) var selectedLiveSessionID: String?

    private let reducer = PresentationReducer()
    private var scheduled: [PresentationTimer: Task<Void, Never>] = [:]
    private var turnNumber = 1
    private var latestLiveSnapshot = ActivityMonitorSnapshot.empty
    private var selectedCodexHomes: [String: String] =
        UserDefaults.standard.dictionary(forKey: "selectedCodexHomes") as? [String: String] ?? [:]

    init(presentation: PresentationState? = nil, navigationIssue: String? = nil,
         activeSessions: [ActivitySnapshot] = []) {
        if let presentation { self.presentation = presentation }
        else { self.presentation.snapshot = .empty }
        self.navigationIssue = navigationIssue
        self.activeSessions = activeSessions
    }

    func choose(_ phase: SessionPhase) {
        guard isDemoMode else { return }
        navigationIssue = nil
        dispatch(.snapshotChanged(PlaygroundScenario.snapshot(turn: turnNumber, phase: phase)))
    }

    func beginNewTurn() {
        guard isDemoMode else { return }
        turnNumber += 1
        navigationIssue = nil
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
        if let observedEvent { observedHookEvents.insert(observedEvent) }
        if let selectedLiveSessionID,
           !snapshot.activeSessions.contains(where: { $0.sessionID == selectedLiveSessionID }) {
            self.selectedLiveSessionID = nil
        }
        lastEventAt = Date()
        if !isDemoMode { dispatch(.snapshotChanged(presentationSnapshot(from: snapshot))) }
    }

    func reconcileLiveSnapshotAfterWake(_ snapshot: ActivityMonitorSnapshot) {
        latestLiveSnapshot = snapshot
        activeSessions = snapshot.activeSessions
        if let selectedLiveSessionID,
           !snapshot.activeSessions.contains(where: { $0.sessionID == selectedLiveSessionID }) {
            self.selectedLiveSessionID = nil
        }
        if !isDemoMode { dispatch(.snapshotChanged(presentationSnapshot(from: snapshot))) }
    }

    func selectLiveSession(_ sessionID: String) {
        guard activeSessions.contains(where: { $0.sessionID == sessionID }) else { return }
        selectedLiveSessionID = sessionID
        if !isDemoMode { dispatch(.snapshotChanged(presentationSnapshot(from: latestLiveSnapshot))) }
    }

    func openLiveSession(_ sessionID: String) {
        guard !isDemoMode, !isOpeningHost,
              activeSessions.contains(where: { $0.sessionID == sessionID }) else { return }
        selectedLiveSessionID = sessionID
        dispatch(.snapshotChanged(presentationSnapshot(from: latestLiveSnapshot)))
        isOpeningHost = true
        navigationIssue = nil
        Task { @MainActor in
            defer { isOpeningHost = false }
            do {
                switch try await CodexNavigator().openSession(sessionID) {
                case .threadRouteAcceptedByOS:
                    dispatch(.collapse)
                case .desktopActivatedFallback:
                    navigationIssue = "Codex Desktop opened, but it did not accept the exact session link."
                }
            } catch {
                navigationIssue = (error as? CodexNavigator.NavigationError)?.localizedDescription
                    ?? "Could not open this Codex chat. Open Codex Desktop, then try again."
            }
        }
    }

    private func presentationSnapshot(from monitor: ActivityMonitorSnapshot) -> ActivitySnapshot {
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
            message: "Nudge will refresh its local bridge helper, then ensure six lifecycle hooks are registered in:\n\(target.hooksFile.path)\n\nExisting handlers will be preserved. An existing file is backed up before it changes. Review and trust Nudge's hooks in Codex, especially PreToolUse and PostToolUse, so tool activity can appear. In Codex CLI, inspect them with /hooks."
        ) else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: HookInstallResult
            do {
                let helper = try BridgeHelperInstaller().install()
                result = CodexHookInstaller(target: target, helperPath: helper).install()
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
            "Six hooks registered for \(host.title). Review and trust Nudge's hooks in Codex, especially PreToolUse and PostToolUse; host coverage remains unverified. Backup: \(backup.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "new file")."
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
        isOpeningHost = true
        navigationIssue = nil
        let destination = host
        Task { @MainActor in
            defer { isOpeningHost = false }
            do {
                try await CodexNavigator().open(destination)
                dispatch(.collapse)
            } catch {
                navigationIssue = (error as? CodexNavigator.NavigationError)?.localizedDescription
                    ?? "Could not open \(destination.title). Open the app, then try again."
            }
        }
    }

    func dispatch(_ input: PresentationInput) {
        let transition = reducer.reduce(presentation, input)
        presentation = transition.state
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
        if !presentation.pinnedOpen {
            dispatch(.togglePinned)
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
