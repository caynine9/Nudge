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
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private let spaceTransition = SpaceTransition()
    private var spaceObserver: NSObjectProtocol?
    private var motionSubscription: AnyCancellable?
    private var visibleSize: CGSize = .zero
    private var hostingGeneration = 0
    private var screenID: CGDirectDisplayID?
    private var currentGeometry: NotchGeometry?

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
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true

        refreshScreen(animated: false)
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.activeSpaceChanged() }
        }
        motionSubscription = appState.$reduceMotion.removeDuplicates().dropFirst().sink { [weak self] enabled in
            guard enabled, let self, self.spaceTransition.isTransitioning else { return }
            self.spaceTransition.cancel()
            self.fadePanel(to: 1, duration: 0)
            self.reconcilePointer()
        }
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            Task { @MainActor in self?.reconcilePointer() }
            return event
        }
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            Task { @MainActor in self?.reconcilePointer() }
        }
    }

    func show() {
        guard !appState.presentation.isSleeping else { return }
        if !spaceTransition.isTransitioning { fadePanel(to: 1, duration: 0) }
        panel.orderFrontRegardless()
        reconcilePointer()
    }

    func hide() {
        spaceTransition.cancel()
        panel.orderOut(nil)
        fadePanel(to: 1, duration: 0)
    }

    func shutdown() {
        hide()
        motionSubscription?.cancel()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        localPointerMonitor = nil
        globalPointerMonitor = nil
    }

    func hideForSleep() {
        hide()
    }

    func wake() {
        refreshScreen(animated: false)
        if appState.wantsPanelVisible { show() }
    }

    func refreshScreen(animated: Bool = true) {
        guard let screen = preferredScreen else { return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
        let newScreenID = displayID
        let screenChanged = screenID != newScreenID
        screenID = newScreenID

        let geometry = NotchGeometry(screen: screen)
        let rebuild = panel.contentView == nil || screenChanged || currentGeometry != geometry || !animated
        if rebuild {
            hostingGeneration += 1
            visibleSize = geometry.size(for: appState.presentation.mode, phase: appState.presentation.snapshot.phase)
        }
        currentGeometry = geometry
        let generation = hostingGeneration
        if panel.frame != geometry.canvasFrame { panel.setFrame(geometry.canvasFrame, display: true) }
        let root = NotchRootView(
            displayKind: geometry.kind,
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight,
            compactWidth: geometry.compactWidth,
            availableWidth: geometry.availableWidth,
            availableHeight: max(0, geometry.screenFrame.height - 32),
            visibleSizeChanged: { [weak self] size in
                guard let self, self.hostingGeneration == generation else { return }
                self.visibleSize = size
                // Geometry callbacks can run during a SwiftUI update. Reconcile semantic
                // hover on the next main-actor turn rather than publishing inside layout.
                Task { @MainActor [weak self] in
                    guard let self, self.hostingGeneration == generation else { return }
                    self.reconcilePointer()
                }
            },
            hoverChanged: { [weak self] _ in
                Task { @MainActor [weak self] in self?.reconcilePointer() }
            }
        ).environmentObject(appState)
        if rebuild {
            let hostingView = NSHostingView(rootView: root)
            // The window is a stable canvas; SwiftUI alone animates the visible shell.
            hostingView.sizingOptions = []
            panel.contentView = hostingView
        }
        reconcilePointer()
    }

    private func activeSpaceChanged() {
        guard panel.isVisible, appState.wantsPanelVisible, !appState.presentation.isSleeping else { return }
        panel.ignoresMouseEvents = true
        // This notification identifies a changed Space, not the exact end of the
        // system animation. A short quiet interval absorbs consecutive switches.
        spaceTransition.begin(reduceMotion: appState.reduceMotion, fade: { [weak self] opacity, duration in
            guard let self, self.appState.wantsPanelVisible, !self.appState.presentation.isSleeping else { return }
            if opacity == 1 { self.refreshScreen() }
            self.fadePanel(to: opacity, duration: duration)
        }, completed: { [weak self] in
            self?.reconcilePointer()
        })
    }

    private func fadePanel(to opacity: Double, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = opacity
        }
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

    private func reconcilePointer() {
        guard panel.isVisible, !appState.presentation.isSleeping, let geometry = currentGeometry else { return }
        guard !spaceTransition.isTransitioning else {
            panel.ignoresMouseEvents = true
            return
        }
        let frame = geometry.frame(forVisibleSize: visibleSize)
        let inside = geometry.containsInteractionPoint(NSEvent.mouseLocation, panelFrame: frame)
        // Transparent canvas must not swallow clicks meant for menu items or other apps.
        panel.ignoresMouseEvents = !inside
        guard inside != appState.presentation.pointerInside else { return }
        appState.dispatch(.pointerChanged(inside))
    }

}
