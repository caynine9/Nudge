import AppKit
import SwiftUI

// Standalone fixtures until the shared test target is available; compile with production sources.
@main
struct NotchGeometryChecks {
    static func main() {
        let screen = CGRect(x: -1512, y: 100, width: 1512, height: 982)
        let visible = CGRect(x: -1512, y: 150, width: 1512, height: 894)
        // Deliberately off-center cutout and nonzero origin catch accidental screen.midX anchoring.
        let left = CGRect(x: -1512, y: 1050, width: 700, height: 32)
        let right = CGRect(x: -632, y: 1050, width: 632, height: 32)
        let geometry = NotchGeometry(screenFrame: screen, visibleFrame: visible, safeAreaTop: 32,
                                     auxiliaryLeft: left, auxiliaryRight: right)
        precondition(geometry.kind == .notch)
        let compact = geometry.frame(for: .collapsed)
        precondition(compact.width < 300 && compact.height <= 38, "Compact must fit the notch band")
        precondition(compact.midX == -722 && compact.maxY == screen.maxY, "Anchor must follow the actual cutout")
        precondition(compact.minX >= screen.minX && compact.maxX <= screen.maxX)
        let pointerOnTrigger = CGPoint(x: compact.minX + 27, y: compact.midY)
        let openFrame = geometry.frame(for: .peek)
        precondition(openFrame.maxY == compact.maxY)
        precondition(geometry.containsInteractionPoint(pointerOnTrigger, panelFrame: openFrame),
                     "Expand must retain the original compact hover trigger")
        precondition(geometry.containsInteractionPoint(CGPoint(x: openFrame.midX, y: openFrame.midY), panelFrame: openFrame))
        precondition(!geometry.containsInteractionPoint(CGPoint(x: screen.minX + 10, y: screen.minY + 10), panelFrame: openFrame))

        for mode: NotchPresentation in NotchPresentation.allCases {
            let frame = geometry.frame(for: mode)
            precondition(frame.midX == compact.midX)
            precondition(frame.maxY == compact.maxY, "Expand must grow from the notch with a stable top edge")
            let bounds = CGRect(origin: .zero, size: frame.size)
            let path = NotchShell(attachedToScreenEdge: true, compactWidth: geometry.compactWidth,
                                  neckHeight: geometry.notchHeight + 2, fullWidth: mode != .collapsed).path(in: bounds)
            if mode == .collapsed {
                precondition(path.contains(CGPoint(x: 27, y: 16)), "Status wing must remain visible")
                precondition(path.contains(CGPoint(x: bounds.maxX - 27, y: 16)), "Mascot wing must remain visible")
            } else {
                precondition(frame.height > geometry.notchHeight, "Expanded content must reserve camera height")
                precondition(path.contains(CGPoint(x: 24, y: 16)), "Expanded must have a full-width top, not a stepped neck")
                precondition(path.contains(CGPoint(x: bounds.maxX - 24, y: 16)))
            }
        }

        // Missing/inconsistent notch metadata must use the fallback below the visible menu bar.
        for auxiliaryLeft in [CGRect.zero, left.offsetBy(dx: 0, dy: -20)] {
            let fallback = NotchGeometry(screenFrame: screen, visibleFrame: visible, safeAreaTop: 32,
                                         auxiliaryLeft: auxiliaryLeft, auxiliaryRight: right)
            precondition(fallback.kind == .standard)
            for mode: NotchPresentation in NotchPresentation.allCases {
                let frame = fallback.frame(for: mode)
                precondition(frame.maxY < visible.maxY && frame.midX == screen.midX)
            }
        }

        let narrowScreen = CGRect(x: 0, y: 0, width: 320, height: 600)
        let fallback = NotchGeometry(screenFrame: narrowScreen, visibleFrame: narrowScreen,
                                     safeAreaTop: 0, auxiliaryLeft: .zero, auxiliaryRight: .zero)
        precondition(fallback.frame(for: .attention).width <= narrowScreen.width - 24)
        let approval = geometry.size(for: .attention, phase: .waitingPermission)
        let question = geometry.size(for: .attention, phase: .waitingInput)
        precondition(question.width < approval.width && question.height < approval.height)
        precondition(geometry.size(for: .collapsed, phase: .waitingInput) == geometry.size(for: .collapsed))
        print("Notch geometry and shell fixture checks passed")
    }
}
