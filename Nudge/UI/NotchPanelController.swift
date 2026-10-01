import AppKit
import Combine
import SwiftUI

@MainActor
private final class NudgePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        AppState.shared.dispatch(.collapse)
    }
}

@MainActor
final class NotchPanelController {
    private let appState: AppState
    private let panel: NudgePanel
    private var stateSubscription: AnyCancellable?
    private var motionSubscription: AnyCancellable?
    private var currentMode: NotchPresentation?
    private var screenID: CGDirectDisplayID?

    init(appState: AppState) {
        self.appState = appState
        panel = NudgePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .utilityWindow

        stateSubscription = appState.$presentation
            .map(\.mode)
            .removeDuplicates()
            .sink { [weak self] mode in self?.setMode(mode) }
        motionSubscription = appState.$reduceMotion
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled { self?.refreshScreen(animated: false) }
            }

        refreshScreen(animated: false)
    }

    func show() {
        guard !appState.presentation.isSleeping else { return }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func hideForSleep() {
        panel.orderOut(nil)
    }

    func wake() {
        refreshScreen(animated: false)
        if appState.wantsPanelVisible { panel.orderFrontRegardless() }
    }

    func refreshScreen(animated: Bool = true) {
        guard let screen = preferredScreen else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
        let newScreenID = displayID
        let screenChanged = screenID != newScreenID
        screenID = newScreenID

        let geometry = NotchGeometry(screen: screen)
        let root = NotchRootView(
            displayKind: geometry.kind,
            contentTopInset: geometry.contentTopInset
        ).environmentObject(appState)
        if panel.contentView == nil || screenChanged {
            panel.contentView = NSHostingView(rootView: root)
        }
        currentMode = appState.presentation.mode
        place(geometry.frame(for: appState.presentation.mode), animated: animated && !screenChanged)
    }

    private var preferredScreen: NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }
        if let builtIn = screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtIn
        }
        return NSScreen.main ?? screens.first
    }

    private func setMode(_ mode: NotchPresentation) {
        guard mode != currentMode, let screen = preferredScreen else { return }
        currentMode = mode
        place(NotchGeometry(screen: screen).frame(for: mode), animated: true)
    }

    private func place(_ frame: CGRect, animated: Bool) {
        guard panel.frame != frame else { return }
        if animated && !appState.reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.32
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
