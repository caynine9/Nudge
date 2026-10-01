import AppKit
import CoreGraphics

enum DisplayKind: Equatable {
    case notch
    case standard
}

struct NotchGeometry {
    let kind: DisplayKind
    let notchWidth: CGFloat
    let contentTopInset: CGFloat
    let screenFrame: CGRect
    let visibleFrame: CGRect

    init(screen: NSScreen) {
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame

        let left = screen.auxiliaryTopLeftArea ?? .zero
        let right = screen.auxiliaryTopRightArea ?? .zero
        let hasTopCutout = !left.isEmpty && !right.isEmpty
            && abs(left.maxY - screen.frame.maxY) < 3
            && abs(right.maxY - screen.frame.maxY) < 3
            && right.minX > left.maxX
        if hasTopCutout {
            kind = .notch
            notchWidth = right.minX - left.maxX
            contentTopInset = max(42, screen.safeAreaInsets.top + 5)
        } else {
            kind = .standard
            notchWidth = 0
            contentTopInset = 5
        }
    }

    func size(for mode: NotchPresentation) -> CGSize {
        let desired: CGSize
        switch (kind, mode) {
        case (.notch, .collapsed): desired = CGSize(width: max(350, notchWidth + 180), height: contentTopInset + 54)
        case (.notch, .peek): desired = CGSize(width: max(410, notchWidth + 230), height: contentTopInset + 92)
        case (.notch, .expanded): desired = CGSize(width: 540, height: contentTopInset + 215)
        case (.notch, .attention): desired = CGSize(width: 540, height: contentTopInset + 235)
        case (.standard, .collapsed): desired = CGSize(width: 320, height: 54)
        case (.standard, .peek): desired = CGSize(width: 410, height: 112)
        case (.standard, .expanded): desired = CGSize(width: 500, height: 230)
        case (.standard, .attention): desired = CGSize(width: 500, height: 250)
        }
        return CGSize(
            width: min(desired.width, max(280, screenFrame.width - 40)),
            height: min(desired.height, max(120, screenFrame.height - 32))
        )
    }

    func frame(for mode: NotchPresentation) -> CGRect {
        let size = size(for: mode)
        let anchorY = kind == .notch ? screenFrame.maxY + 1 : visibleFrame.maxY + 2
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: anchorY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
