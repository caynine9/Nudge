import AppKit
import SwiftUI

// Render every state inside the actual fixed-size hosting canvas. Cropping the
// renderer to the requested shell size hides overflow from retained content.
@main
struct NotchLayoutChecks {
    @MainActor static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for notched in [true, false] {
            let geometry = NotchGeometry(
                screenFrame: screen, visibleFrame: screen.insetBy(dx: 0, dy: 38),
                safeAreaTop: notched ? 32 : 0,
                auxiliaryLeft: notched ? CGRect(x: 0, y: 950, width: 666, height: 32) : .zero,
                auxiliaryRight: notched ? CGRect(x: 846, y: 950, width: 666, height: 32) : .zero
            )
            for mode in NotchPresentation.allCases {
                for phase in [SessionPhase.thinking, .waitingPermission, .waitingInput] {
                    var state = PresentationState()
                    state.snapshot = PlaygroundScenario.snapshot(turn: 1, phase: mode == .attention ? phase : .thinking)
                    switch mode {
                    case .collapsed: break
                    case .peek: state.peekVisible = true
                    case .expanded: state.pinnedOpen = true
                    case .attention:
                        if !phase.isAttention { continue }
                    case .confirmation: state.feedback = .init(label: "Allowed once", kind: .allowed)
                    }
                    precondition(state.mode == mode)
                    let app = AppState(presentation: state)
                    let canvas = geometry.canvasSize
                    let expected = geometry.size(for: mode, phase: state.snapshot.phase)
                    let root = NotchRootView(
                        displayKind: geometry.kind, notchWidth: geometry.notchWidth,
                        notchHeight: geometry.notchHeight, compactWidth: geometry.compactWidth,
                        availableWidth: canvas.width, availableHeight: canvas.height
                    ).environmentObject(app).frame(width: canvas.width, height: canvas.height)
                    let renderer = ImageRenderer(content: root)
                    renderer.scale = 1
                    guard let image = renderer.cgImage else { fatalError("Render failed") }
                    let actual = opaqueBounds(image)
                    // Notch shoulders curve inward immediately below the top edge, so
                    // the opaque pixel bounds are slightly narrower than layout width.
                    // Compare with an isolated shell at the domain's requested size.
                    let reference = ImageRenderer(content:
                        NotchShell(attachedToScreenEdge: notched, compactWidth: geometry.compactWidth,
                                   neckHeight: geometry.notchHeight + 2, fullWidth: mode != .collapsed)
                            .fill(Color.black)
                            .frame(width: expected.width, height: expected.height)
                            .frame(width: canvas.width, height: canvas.height, alignment: .top)
                    )
                    reference.scale = 1
                    guard let referenceImage = reference.cgImage else { fatalError("Reference render failed") }
                    let expectedBounds = opaqueBounds(referenceImage)
                    let label = "\(geometry.kind) \(mode) \(state.snapshot.phase)"
                    precondition(abs(actual.width - expectedBounds.width) <= 2 && abs(actual.height - expectedBounds.height) <= 2,
                                 "\(label): opaque shell \(actual) must match \(expectedBounds), target \(expected)")
                    precondition(actual.minY <= 1 && abs(actual.midX - canvas.width / 2) <= 1,
                                 "\(label): shell must remain top-centered")
                }
            }
        }
        print("Notch layout checks passed: every state fits its own bounds inside the full hosting canvas")
    }

    private static func opaqueBounds(_ image: CGImage) -> CGRect {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var minX = bitmap.pixelsWide, maxX = -1, minY = bitmap.pixelsHigh, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                // Ignore the soft shadow; measure the opaque shell and contents.
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.95 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        precondition(maxX >= minX && maxY >= minY, "Shell must not disappear")
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

}
