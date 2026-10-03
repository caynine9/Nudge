import AppKit
import Combine

@MainActor
final class NudgeAppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var visibilitySubscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var socketServer: NudgeSocketServer?
    private var permissionSocketServer: NudgePermissionSocketServer?
    private var eventIngress: CodexEventIngress?
    private var permissionBroker: PermissionBroker?
    private let eventMonitor = CodexEventMonitor()
    private let workspaceCenter = NSWorkspace.shared.notificationCenter

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let state = AppState.shared
        panelController = NotchPanelController(appState: state)
        let broker = PermissionBroker(
            onStatus: { request, status in
                await MainActor.run { AppState.shared.updatePermissionActionStatus(status, for: request) }
            },
            validateContext: { request in
                await MainActor.run { AppState.shared.isCurrentPermissionRequest(request) }
            }
        )
        permissionBroker = broker
        state.configurePermissionBroker(broker)
        let monitor = eventMonitor
        let metadataReader = CodexThreadMetadataReader(codexAppURL: NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: CodexHost.desktop.bundleIdentifier))
        state.configureCodexMetadataReader(metadataReader)
        let ingress = CodexEventIngress(monitor: monitor, preprocess: { envelope in
            await broker.reconcile(envelope)
        }) { snapshot, event, sessionID in
            let homePaths = await MainActor.run { () -> [String] in
                AppState.shared.updateLiveSnapshot(snapshot, observedEvent: event)
                return AppState.shared.codexHomePathsForMetadata()
            }
            guard snapshot.activeSessions.contains(where: { $0.sessionID == sessionID }) else { return }
            Task.detached(priority: .utility) {
                let homes = homePaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
                if let title = await metadataReader.title(for: sessionID, codexHomes: homes) {
                    await MainActor.run { AppState.shared.setSessionTitle(title, for: sessionID) }
                } else if event == .userPromptSubmit {
                    try? await Task.sleep(for: .seconds(2))
                    if let title = await metadataReader.title(for: sessionID, codexHomes: homes, forceRefresh: true) {
                        await MainActor.run { AppState.shared.setSessionTitle(title, for: sessionID) }
                    }
                }
            }
        }
        eventIngress = ingress
        let server = NudgeSocketServer { envelope in ingress.submit(envelope) }
        socketServer = server
        let permissionServer = NudgePermissionSocketServer { request in
            let enabled = await MainActor.run { AppState.shared.permissionActionsEnabled }
            return await broker.waitForDecision(request, enabled: enabled)
        }
        permissionSocketServer = permissionServer
        Task.detached(priority: .userInitiated) {
            do {
                try server.start()
                await MainActor.run { AppState.shared.setSocketStatus("Local event listener ready.") }
            } catch {
                await MainActor.run { AppState.shared.setSocketStatus("Local event listener unavailable. Codex can continue normally.") }
            }
            do {
                try permissionServer.start()
            } catch {
                await MainActor.run { AppState.shared.setPermissionListenerUnavailable() }
            }
        }
        visibilitySubscription = state.$wantsPanelVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                if visible { self?.panelController?.show() }
                else { self?.panelController?.hide() }
            }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panelController?.refreshScreen() }
        }

        sleepObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                AppState.shared.dispatch(.sleep)
                Task { await broker.cancelAll() }
                self?.panelController?.hideForSleep()
            }
        }
        wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if let snapshot = await self?.snapshotAfterDrainingSocketEvents() {
                    AppState.shared.reconcileLiveSnapshotAfterWake(snapshot)
                }
                AppState.shared.dispatch(.wake)
                self?.panelController?.wake()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibilitySubscription?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        [sleepObserver, wakeObserver].compactMap { $0 }.forEach { workspaceCenter.removeObserver($0) }
        socketServer?.stop()
        socketServer = nil
        permissionSocketServer?.stop()
        permissionSocketServer = nil
        if let permissionBroker { Task { await permissionBroker.cancelAll() } }
        permissionBroker = nil
        eventIngress?.finish()
        eventIngress = nil
        panelController?.shutdown()
        panelController = nil
    }

    private func snapshotAfterDrainingSocketEvents() async -> ActivityMonitorSnapshot? {
        let server = socketServer
        let ingress = eventIngress
        return await Task.detached(priority: .userInitiated) {
            server?.flushEvents()
            guard let ingress else { return nil }
            return await ingress.snapshotAfterPendingEvents()
        }.value
    }
}
