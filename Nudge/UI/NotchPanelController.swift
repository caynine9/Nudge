import AppKit
import Combine
import QuartzCore
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
    private var localPointerMonitor: Any?
    private var globalPointerMonitor: Any?
    private struct Layout: Equatable {
        let mode: NotchPresentation
        let phase: SessionPhase
    }
    private var currentLayout: Layout?
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

        stateSubscription = appState.$presentation
            .map { Layout(mode: $0.mode, phase: $0.snapshot.phase) }
            .removeDuplicates()
            .sink { [weak self] layout in self?.setLayout(layout) }
        motionSubscription = appState.$reduceMotion
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] enabled in
                if enabled { self?.refreshScreen(animated: false) }
            }

        refreshScreen(animated: false)
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
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func shutdown() {
        hide()
        stateSubscription?.cancel()
        motionSubscription?.cancel()
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        if let globalPointerMonitor { NSEvent.removeMonitor(globalPointerMonitor) }
        localPointerMonitor = nil
        globalPointerMonitor = nil
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
            notchWidth: geometry.notchWidth,
            notchHeight: geometry.notchHeight,
            compactWidth: geometry.compactWidth,
            availableWidth: geometry.availableWidth,
            hoverChanged: { [weak self] _ in self?.reconcilePointer() }
        ).environmentObject(appState)
        if panel.contentView == nil || screenChanged || currentGeometry != geometry {
            let hostingView = NSHostingView(rootView: root)
            // Window geometry owns resize; intrinsic content constraints must not fight the animation.
            hostingView.sizingOptions = []
            panel.contentView = hostingView
        }
        currentGeometry = geometry
        currentLayout = Layout(mode: appState.presentation.mode, phase: appState.presentation.snapshot.phase)
        place(geometry.frame(for: appState.presentation.mode, phase: appState.presentation.snapshot.phase), animated: animated && !screenChanged)
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

    private func setLayout(_ layout: Layout) {
        guard layout != currentLayout, let screen = preferredScreen else { return }
        currentLayout = layout
        place(NotchGeometry(screen: screen).frame(for: layout.mode, phase: layout.phase), animated: true)
    }

    private func reconcilePointer() {
        guard panel.isVisible, !appState.presentation.isSleeping, let geometry = currentGeometry else { return }
        let inside = geometry.containsInteractionPoint(NSEvent.mouseLocation, panelFrame: panel.frame)
        guard inside != appState.presentation.pointerInside else { return }
        appState.dispatch(.pointerChanged(inside))
    }

    private func place(_ frame: CGRect, animated: Bool) {
        guard panel.frame != frame else { return }
        if animated && !appState.reduceMotion {
            let shrinking = frame.width <= panel.frame.width && frame.height <= panel.frame.height
            NSAnimationContext.runAnimationGroup { context in
                context.duration = shrinking ? NotchMotion.collapseDuration : NotchMotion.expandDuration
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }
}
