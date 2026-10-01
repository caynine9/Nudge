import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let displayKind: DisplayKind
    let contentTopInset: CGFloat

    private var mode: NotchPresentation { appState.presentation.mode }
    private var phase: SessionPhase { appState.presentation.snapshot.phase }
    private var isNotched: Bool { displayKind == .notch }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 42)
                .contentShape(Rectangle())
                .onTapGesture { appState.dispatch(.togglePinned) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(appState.presentation.snapshot.projectLabel), \(phase.title)")
                .accessibilityHint("Activate to expand or collapse the Nudge playground")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { appState.dispatch(.togglePinned) }

            if mode == .peek {
                peekContent
                    .padding(.top, 2)
                    .transition(.opacity)
            } else if mode == .expanded || mode == .attention {
                expandedContent
                    .padding(.top, 9)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, isNotched ? 21 : 18)
        .padding(.top, contentTopInset)
        .padding(.bottom, isNotched ? 12 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            shell
        }
        .overlay {
            shell
                .strokeBorder(.white.opacity(isNotched ? 0.075 : 0.11), lineWidth: 0.8)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .contentShape(shell)
        .onHover { appState.dispatch(.pointerChanged($0)) }
        .onChange(of: accessibilityReduceMotion) { _, value in appState.setReduceMotion(value) }
        .onAppear { appState.setReduceMotion(accessibilityReduceMotion) }
        .accessibilityIdentifier("nudge.notch-playground")
    }

    private var shell: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isNotched ? 24 : 23,
            bottomLeadingRadius: 25,
            bottomTrailingRadius: 25,
            topTrailingRadius: isNotched ? 24 : 23,
            style: .continuous
        )
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: phase.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 16)

            Text(appState.presentation.snapshot.projectLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.96))

            Circle()
                .fill(.white.opacity(0.2))
                .frame(width: 3, height: 3)

            Text(appState.presentation.snapshot.activityLabel)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.white.opacity(0.68))

            Spacer(minLength: 1)

            Nudgie(
                pose: MascotPose(phase: phase),
                celebrationPulse: appState.celebrationPulse,
                reduceMotion: appState.reduceMotion
            )
            .frame(width: 34, height: 32)
        }
        .padding(.leading, isNotched ? 2 : 0)
        .padding(.trailing, 1)
    }

    private var peekContent: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 1)
                .fill(accent)
                .frame(width: 3, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(phase == .toolUse ? "CURRENT ACTIVITY" : "CODEX PLAYGROUND")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.42))
                Text(appState.presentation.snapshot.detail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.84))
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 4)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 8) {
                Text(phase == .waitingPermission || phase == .waitingInput ? "NEEDS YOU" : "SIMULATED SESSION")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.25)
                    .foregroundStyle(accent)
                Spacer()
                Text("M0 PLAYGROUND")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.34))
            }

            Text(appState.presentation.snapshot.detail)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .lineSpacing(2)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)

            HStack(spacing: 7) {
                Label(appState.presentation.snapshot.projectLabel, systemImage: "folder")
                Text("·").foregroundStyle(.white.opacity(0.25))
                Text("Turn \(appState.presentation.snapshot.turnID.split(separator: "-").last ?? "1")")
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.5))

            if phase.isAttention {
                Button {
                    appState.choose(.thinking)
                } label: {
                    HStack(spacing: 7) {
                        Text("Simulate progress")
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.14, blue: 0.17))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Changes the simulated session back to working")
            } else {
                Text("Choose a phase from the Nudge menu bar icon to preview another state.")
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.075), .white.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 0.7)
        }
        .padding(.horizontal, 1)
    }

    private var accent: Color {
        switch phase {
        case .waitingPermission, .waitingInput: Color(red: 1, green: 0.71, blue: 0.36)
        case .completed: Color(red: 0.44, green: 0.88, blue: 0.68)
        case .failed: Color(red: 1, green: 0.47, blue: 0.46)
        case .interrupted: Color(red: 0.69, green: 0.72, blue: 0.79)
        default: Color(red: 0.48, green: 0.79, blue: 1)
        }
    }
}
