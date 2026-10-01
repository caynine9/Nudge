import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var presentation = PresentationState()
    @Published private(set) var celebrationPulse = 0
    @Published private(set) var reduceMotion = false
    @Published var wantsPanelVisible = true
    @Published var host: CodexHost = .desktop
    @Published private(set) var isOpeningHost = false
    @Published private(set) var navigationIssue: String?

    private let reducer = PresentationReducer()
    private var scheduled: [PresentationTimer: Task<Void, Never>] = [:]
    private var turnNumber = 1

    init(presentation: PresentationState? = nil, navigationIssue: String? = nil) {
        if let presentation { self.presentation = presentation }
        else { self.presentation.snapshot = PlaygroundScenario.snapshot(turn: 1, phase: .thinking) }
        self.navigationIssue = navigationIssue
    }

    func choose(_ phase: SessionPhase) {
        navigationIssue = nil
        dispatch(.snapshotChanged(PlaygroundScenario.snapshot(turn: turnNumber, phase: phase)))
    }

    func beginNewTurn() {
        turnNumber += 1
        navigationIssue = nil
        dispatch(.snapshotChanged(PlaygroundScenario.snapshot(turn: turnNumber, phase: .thinking)))
    }

    func resolvePreview(_ feedback: InteractionFeedback) {
        guard presentation.snapshot.phase.isAttention else { return }
        let phase: SessionPhase = feedback.kind == .denied ? .interrupted : .toolUse
        dispatch(.previewInteractionResolved(PlaygroundScenario.snapshot(turn: turnNumber, phase: phase), feedback))
    }

    func openFocusedHost() {
        guard !isOpeningHost else { return }
        isOpeningHost = true
        navigationIssue = nil
        let destination = host
        Task { @MainActor in
            defer { isOpeningHost = false }
            do {
                try await CodexNavigator().open(destination)
                dispatch(.collapse)
            } catch {
                navigationIssue = (error as? CodexNavigator.NavigationError)?.localizedDescription
                    ?? "Could not open \(destination.title). Open the app, then try again."
            }
        }
    }

    func dispatch(_ input: PresentationInput) {
        let transition = reducer.reduce(presentation, input)
        presentation = transition.state
        for effect in transition.effects {
            run(effect)
        }
    }

    func setReduceMotion(_ value: Bool) {
        guard reduceMotion != value else { return }
        reduceMotion = value
    }

    func togglePanel() {
        wantsPanelVisible.toggle()
    }

    func showPanel() {
        wantsPanelVisible = true
        if !presentation.pinnedOpen {
            dispatch(.togglePinned)
        }
    }

    private func run(_ effect: PresentationEffect) {
        switch effect {
        case let .schedule(timer, duration, generation):
            scheduled[timer]?.cancel()
            scheduled[timer] = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return
                }
                guard let self else { return }
                self.scheduled[timer] = nil
                self.dispatch(.timerElapsed(timer, generation: generation))
            }
        case let .cancel(timer):
            scheduled[timer]?.cancel()
            scheduled[timer] = nil
        case .celebrate:
            guard !reduceMotion else { return }
            celebrationPulse &+= 1
        }
    }
}
