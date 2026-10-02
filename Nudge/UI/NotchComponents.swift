import SwiftUI

enum NotchMotion {
    // Both dimensions share one spring: a small overshoot then a quick settle,
    // preserving velocity when a user reverses direction before it finishes.
    static func shellSpring(collapsing: Bool) -> Spring {
        Spring(response: 0.44, dampingRatio: 0.78)
    }

    static func shell(collapsing: Bool) -> Animation {
        .spring(shellSpring(collapsing: collapsing))
    }

    static let contentBlur: CGFloat = 5

    static func pageTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        let dissolve = AnyTransition.modifier(
            active: NotchPageDissolve(amount: 1),
            identity: NotchPageDissolve(amount: 0)
        )
        return .asymmetric(
            insertion: dissolve.animation(.easeInOut(duration: 0.28)),
            removal: dissolve.animation(.easeOut(duration: 0.14))
        )
    }

    static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : .opacity
    }

}

// The reference softens page changes without moving the shell. Blur is bounded
// to this small content layer and disappears completely at rest.
struct NotchPageDissolve: ViewModifier {
    var amount: CGFloat
    var reduceMotion = false

    func body(content: Content) -> some View {
        let amount = min(1, max(0, amount))
        content
            .blur(radius: reduceMotion ? 0 : NotchMotion.contentBlur * amount)
            .opacity(1 - amount)
            .scaleEffect(reduceMotion ? 1 : 1 - 0.015 * amount, anchor: .top)
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
