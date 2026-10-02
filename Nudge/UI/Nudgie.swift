import SwiftUI

enum MascotPose {
    case idle
    case thinking
    case working
    case attention
    case done
    case failure
    case interrupted

    init(phase: SessionPhase) {
        switch phase {
        case .discovered, .idle, .ended: self = .idle
        case .thinking: self = .thinking
        case .toolUse: self = .working
        case .waitingPermission, .waitingInput: self = .attention
        case .completed: self = .done
        case .failed: self = .failure
        case .interrupted: self = .interrupted
        }
    }

    var eyeOffset: CGFloat {
        switch self {
        case .thinking: 1
        case .attention: -1
        default: 0
        }
    }

    var bodyColor: Color {
        switch self {
        case .attention: Color(red: 1.0, green: 0.71, blue: 0.36)
        case .done: Color(red: 0.44, green: 0.88, blue: 0.68)
        case .failure: Color(red: 1.0, green: 0.47, blue: 0.46)
        case .interrupted: Color(red: 0.64, green: 0.69, blue: 0.78)
        default: Color(red: 0.48, green: 0.79, blue: 1.0)
        }
    }
}

private struct CursorCreature: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let body = CGRect(x: rect.minX, y: rect.minY + 2, width: rect.width - 3, height: rect.height - 2)
        path.addRoundedRect(in: body, cornerSize: CGSize(width: 10, height: 10))
        path.move(to: CGPoint(x: rect.maxX - 7, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - 1))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 8))
        path.closeSubpath()
        return path
    }
}

struct Nudgie: View {
    let pose: MascotPose
    let celebrationPulse: Int
    let reduceMotion: Bool
    let isSleeping: Bool

    @State private var hop = 0.0
    @State private var hopTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            CursorCreature()
                .fill(LinearGradient(
                    colors: [pose.bodyColor.opacity(0.95), pose.bodyColor.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    CursorCreature().stroke(.white.opacity(0.28), lineWidth: 0.8)
                }

            HStack(spacing: 6) {
                eye
                eye
            }
            .offset(x: -1, y: pose.eyeOffset)
        }
        .frame(width: 31, height: 28)
        .offset(y: hop)
        .onChange(of: celebrationPulse) { _, pulse in
            guard pulse > 0, !reduceMotion, !isSleeping else { return }
            hopTask?.cancel()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.48)) { hop = -6 }
            hopTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(290)) }
                catch { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { hop = 0 }
                hopTask = nil
            }
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { cancelHop() }
        }
        .onChange(of: isSleeping) { _, sleeping in
            if sleeping { cancelHop() }
        }
        .onDisappear {
            cancelHop()
        }
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Capsule()
            .fill(Color(red: 0.08, green: 0.12, blue: 0.18))
            .frame(width: 3.2, height: pose == .failure ? 2.4 : 5.4)
    }

    private func cancelHop() {
        hopTask?.cancel()
        hopTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { hop = 0 }
    }
}

extension MascotPose: Equatable {}
