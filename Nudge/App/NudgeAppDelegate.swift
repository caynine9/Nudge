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
    private var eventIngress: CodexEventIngress?
    private let eventMonitor = CodexEventMonitor()
    private let workspaceCenter = NSWorkspace.shared.notificationCenter

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let state = AppState.shared
        panelController = NotchPanelController(appState: state)
        let monitor = eventMonitor
        let ingress = CodexEventIngress(monitor: monitor) { snapshot, event in
            await MainActor.run {
                AppState.shared.updateLiveSnapshot(snapshot, observedEvent: event)
            }
        }
        eventIngress = ingress
        let server = NudgeSocketServer { envelope in ingress.submit(envelope) }
        socketServer = server
        Task.detached(priority: .userInitiated) {
            do {
                try server.start()
                await MainActor.run { AppState.shared.setSocketStatus("Local event listener ready.") }
            } catch {
                await MainActor.run { AppState.shared.setSocketStatus("Local event listener unavailable. Codex can continue normally.") }
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
