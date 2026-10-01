import SwiftUI

enum NotchMotion {
    // One retargetable spring drives size, contour and reveal. Critical damping avoids
    // overshooting the camera anchor while preserving velocity when direction changes.
    static func shell(collapsing: Bool) -> Animation {
        .spring(response: collapsing ? 0.34 : 0.42, dampingFraction: 1, blendDuration: 0)
    }

    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }

}

enum NotchPalette {
    static let secondary = Color(white: 0.60)
    static let muted = Color(white: 0.48)
    static let blue = Color(red: 0.22, green: 0.58, blue: 1)
    static let orange = Color(red: 1, green: 0.57, blue: 0.20)
    static let cyan = Color(red: 0.20, green: 0.78, blue: 0.87)
    static let green = Color(red: 0.24, green: 0.82, blue: 0.48)
    static let red = Color(red: 1, green: 0.43, blue: 0.43)
}

enum NotchType {
    static func readable(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func code(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }
}

struct NotchBadge: View {
    let title: String
    var body: some View {
        Text(title)
            .font(NotchType.readable(10))
            .foregroundStyle(NotchPalette.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color(white: 0.10), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct NotchButtonStyle: ButtonStyle {
    enum Tone { case row, neutral, primary, choice }
    var tone: Tone = .neutral
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(focused ? Color.white.opacity(0.75) : Color.clear, lineWidth: 1)
            }
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovered = $0 }
    }

    private func background(pressed: Bool) -> Color {
        let active = enabled && (pressed || hovered)
        switch tone {
        case .row: return Color(white: active ? 0.08 : 0)
        case .neutral: return Color(white: active ? 0.22 : 0.15)
        case .primary: return Color(white: pressed ? 0.72 : (active ? 1 : 0.90))
        case .choice: return NotchPalette.cyan.opacity(active ? 0.22 : 0.12)
        }
    }
}
