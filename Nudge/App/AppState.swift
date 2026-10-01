import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published private(set) var presentation = PresentationState()
    @Published private(set) var celebrationPulse = 0
    @Published private(set) var reduceMotion = false
    @Published var wantsPanelVisible = true

    private let reducer = PresentationReducer()
    private var scheduled: [PresentationTimer: Task<Void, Never>] = [:]
    private var turnNumber = 1

    private init() {}

    func choose(_ phase: SessionPhase) {
        let old = presentation.snapshot
        dispatch(.snapshotChanged(ActivitySnapshot(
            sessionID: old.sessionID,
            turnID: old.turnID,
            projectLabel: old.projectLabel,
            phase: phase,
            currentTool: phase == .toolUse
                ? ToolActivity(category: .test, summary: "Running tests", symbol: "checkmark.circle")
                : nil,
            activityLabel: phase == .toolUse ? "Running tests" : phase.title,
            detail: phase.detail
        )))
    }

    func beginNewTurn() {
        turnNumber += 1
        dispatch(.snapshotChanged(.demo(turn: turnNumber, phase: .thinking)))
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
