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
        // A stable hosting canvas encloses every endpoint; its transparent remainder
        // must never be used as the interactive frame, including mid-transition.
        for display in [geometry, fallback] {
            let canvas = display.canvasFrame
            let compact = display.frame(for: .collapsed)
            precondition(canvas.midX == compact.midX && canvas.maxY == compact.maxY)
            for mode in NotchPresentation.allCases {
                for phase in [SessionPhase.waitingPermission, .waitingInput, .thinking] {
                    let target = display.frame(for: mode, phase: phase)
                    precondition(canvas.contains(target), "Every state must fit the fixed canvas")
                    for fraction in [CGFloat(0), 0.15, 0.5, 0.85, 1] {
                        let size = CGSize(width: compact.width + (target.width - compact.width) * fraction,
                                          height: compact.height + (target.height - compact.height) * fraction)
                        let visible = display.frame(forVisibleSize: size)
                        precondition(visible.midX == compact.midX && visible.maxY == compact.maxY)
                        precondition(display.containsInteractionPoint(CGPoint(x: visible.midX, y: visible.midY),
                                                                      panelFrame: visible))
                        let belowShell = CGPoint(x: canvas.midX, y: visible.minY - 1)
                        precondition(!display.containsInteractionPoint(belowShell, panelFrame: visible),
                                     "Invisible canvas must pass pointer events through while opening or closing")
                    }
                }
            }
        }
        // Sample the same native springs used by the view, including their
        // overshoot. The transparent canvas must contain the visible rebound.
        for collapsing in [false, true] {
            let spring = NotchMotion.shellSpring(collapsing: collapsing)
            let samples = (0...240).map { spring.value(target: 1.0, time: Double($0) / 240) }
            precondition(samples.max()! > 1.005 && samples.max()! < 1.04,
                         "Use a visible but restrained settling bounce")
            precondition(abs(samples.last! - 1) < 0.001, "Spring must settle without an idle loop")
            for display in [geometry, fallback] {
                let compact = display.size(for: .collapsed)
                for mode in NotchPresentation.allCases {
                    for phase in [SessionPhase.thinking, .waitingPermission, .waitingInput] {
                        let open = display.size(for: mode, phase: phase)
                        let start = collapsing ? open : compact
                        let end = collapsing ? compact : open
                        for progress in samples {
                            let size = CGSize(width: start.width + (end.width - start.width) * progress,
                                              height: start.height + (end.height - start.height) * progress)
                            let frame = display.frame(forVisibleSize: size)
                            precondition(size.width > 0 && size.height > 0)
                            precondition(display.canvasFrame.contains(frame),
                                         "The native canvas must not clip the spring overshoot")
                            precondition(frame.maxY == display.canvasFrame.maxY,
                                         "The top anchor must stay fixed during the bounce")
                        }
                    }
                }
            }
        }
        print("Notch geometry and shell fixture checks passed")
    }
}
