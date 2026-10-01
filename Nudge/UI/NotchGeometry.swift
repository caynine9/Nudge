import AppKit
import CoreGraphics

enum DisplayKind: Equatable {
    case notch
    case standard
}

struct NotchGeometry: Equatable {
    let kind: DisplayKind
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let compactWidth: CGFloat
    let anchorX: CGFloat
    let screenFrame: CGRect
    let visibleFrame: CGRect

    @MainActor
    init(screen: NSScreen) {
        self.init(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeft: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryRight: screen.auxiliaryTopRightArea ?? .zero
        )
    }

    init(screenFrame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat,
         auxiliaryLeft left: CGRect, auxiliaryRight right: CGRect) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        let hasTopCutout = !left.isEmpty && !right.isEmpty
            && abs(left.maxY - screenFrame.maxY) < 3
            && abs(right.maxY - screenFrame.maxY) < 3
            && right.minX > left.maxX
        if hasTopCutout {
            kind = .notch
            notchWidth = right.minX - left.maxX
            notchHeight = max(safeAreaTop, max(left.height, right.height))
            compactWidth = notchWidth + 84
            anchorX = (left.maxX + right.minX) / 2
        } else {
            kind = .standard
            notchWidth = 0
            notchHeight = 0
            compactWidth = 200
            anchorX = screenFrame.midX
        }
    }

    func size(for mode: NotchPresentation, phase: SessionPhase = .thinking) -> CGSize {
        let desired = Self.preferredSize(kind: kind, compactWidth: compactWidth, notchHeight: notchHeight,
                                         mode: mode, phase: phase)
        return CGSize(width: min(desired.width, availableWidth),
                      height: min(desired.height, max(0, screenFrame.height - 32)))
    }

    var availableWidth: CGFloat {
        max(0, 2 * min(anchorX - screenFrame.minX, screenFrame.maxX - anchorX) - 24)
    }

    static func preferredSize(kind: DisplayKind, compactWidth: CGFloat, notchHeight: CGFloat,
                              mode: NotchPresentation, phase: SessionPhase) -> CGSize {
        let bandHeight = notchHeight + 2
        let desired: CGSize
        switch (kind, mode) {
        case (.notch, .collapsed): desired = CGSize(width: compactWidth, height: bandHeight)
        case (.notch, .peek): desired = CGSize(width: max(compactWidth, 380), height: notchHeight + 132)
        case (.notch, .expanded): desired = CGSize(width: max(compactWidth, 380), height: notchHeight + 160)
        case (.notch, .attention):
            desired = CGSize(width: max(compactWidth, phase == .waitingInput ? 340 : 380),
                             height: notchHeight + (phase == .waitingInput ? 192 : 224))
        case (.notch, .confirmation): desired = CGSize(width: max(compactWidth, 260), height: notchHeight + 46)
        case (.standard, .collapsed): desired = CGSize(width: compactWidth, height: 38)
        case (.standard, .peek): desired = CGSize(width: 380, height: 132)
        case (.standard, .expanded): desired = CGSize(width: 380, height: 160)
        case (.standard, .attention):
            desired = CGSize(width: phase == .waitingInput ? 340 : 380, height: phase == .waitingInput ? 192 : 224)
        case (.standard, .confirmation): desired = CGSize(width: 260, height: 46)
        }
        return desired
    }

    func frame(for mode: NotchPresentation, phase: SessionPhase = .thinking) -> CGRect {
        let size = size(for: mode, phase: phase)
        // The non-notch fallback lives below the menu bar rather than covering its items.
        let anchorY: CGFloat
        if kind == .notch {
            anchorY = screenFrame.maxY
        } else {
            anchorY = visibleFrame.maxY - 6
        }
        return CGRect(
            x: anchorX - size.width / 2,
            y: anchorY - size.height,
            width: size.width,
            height: size.height
        )
    }

    func containsInteractionPoint(_ point: CGPoint, panelFrame: CGRect) -> Bool {
        // Retain the original compact trigger throughout frame animation and display fallback.
        frame(for: .collapsed).contains(point) || panelFrame.contains(point)
    }
}
