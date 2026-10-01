import AppKit
import Combine

@MainActor
final class NudgeAppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: NotchPanelController?
    private var visibilitySubscription: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private let workspaceCenter = NSWorkspace.shared.notificationCenter

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let state = AppState.shared
        panelController = NotchPanelController(appState: state)
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
                AppState.shared.dispatch(.wake)
                self?.panelController?.wake()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibilitySubscription?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        [sleepObserver, wakeObserver].compactMap { $0 }.forEach { workspaceCenter.removeObserver($0) }
        panelController?.hide()
        panelController = nil
    }
}
