import Foundation

struct PresentationReducer {
    func reduce(_ state: PresentationState, _ input: PresentationInput, now: Date = Date()) -> PresentationTransition {
        var next = state
        var effects: [PresentationEffect] = []

        switch input {
        case let .snapshotChanged(snapshot):
            guard snapshot != state.snapshot else { return PresentationTransition(state: state) }
            next.snapshot = snapshot
            next.feedback = nil
            next.feedbackGeneration += 1
            effects.append(.cancel(.feedback))

            if snapshot.phase == .completed {
                let key = Self.completionKey(snapshot)
                if !next.consumedCompletionKeys.contains(key) {
                    Self.remember(key, in: &next.consumedCompletionKeys)
                    next.consumedCompletionTurnID = key
                    if state.isSleeping || snapshotOccurredBeforeWake(snapshot, state: state) {
                        next.transientPhase = nil
                        next.transientPresentationKey = nil
                        next.transientGeneration += 1
                        effects.append(.cancel(.transient))
                    } else {
                        next.transientPhase = .completed
                        next.transientPresentationKey = key
                        next.transientGeneration += 1
                        effects.append(.schedule(.transient, after: .seconds(3.2), generation: next.transientGeneration))
                        effects.append(.celebrate)
                    }
                } else if next.transientPresentationKey != key {
                    next.transientPhase = nil
                    next.transientPresentationKey = nil
                    next.transientGeneration += 1
                    effects.append(.cancel(.transient))
                }
            } else if snapshot.phase == .failed {
                let key = Self.completionKey(snapshot)
                if !next.consumedFailureKeys.contains(key) {
                    Self.remember(key, in: &next.consumedFailureKeys)
                    next.consumedFailureTurnID = key
                    if state.isSleeping || snapshotOccurredBeforeWake(snapshot, state: state) {
                        next.transientPhase = nil
                        next.transientPresentationKey = nil
                        next.transientGeneration += 1
                        effects.append(.cancel(.transient))
                    } else {
                        next.transientPhase = .failed
                        next.transientPresentationKey = key
                        next.transientGeneration += 1
                        effects.append(.schedule(.transient, after: .seconds(5), generation: next.transientGeneration))
                    }
                } else if next.transientPresentationKey != key {
                    next.transientPhase = nil
                    next.transientPresentationKey = nil
                    next.transientGeneration += 1
                    effects.append(.cancel(.transient))
                }
            } else if snapshot.phase != state.snapshot.phase {
                next.transientPhase = nil
                next.transientPresentationKey = nil
                next.transientGeneration += 1
                effects.append(.cancel(.transient))
            }

            if snapshot.phase.isAttention {
                next.collapseGeneration += 1
                effects.append(.cancel(.collapse))
            } else if state.snapshot.phase.isAttention && next.pointerInside {
                next.peekVisible = true
            }

        case let .previewInteractionResolved(snapshot, feedback):
            guard state.snapshot.phase.isAttention, !state.isSleeping,
                  snapshot.sessionID == state.snapshot.sessionID,
                  snapshot.turnID == state.snapshot.turnID, !snapshot.phase.isAttention
            else { return PresentationTransition(state: state) }
            let progress = reduce(state, .snapshotChanged(snapshot))
            next = progress.state
            effects = progress.effects
            next.feedback = feedback
            next.feedbackGeneration += 1
            next.pinnedOpen = false
            next.peekVisible = false
            next.transientPhase = nil
            next.transientPresentationKey = nil
            next.peekGeneration += 1
            next.collapseGeneration += 1
            next.transientGeneration += 1
            effects += [.cancel(.peek), .cancel(.collapse), .cancel(.transient),
                        .schedule(.feedback, after: .seconds(1.4), generation: next.feedbackGeneration)]

        case let .pointerChanged(isInside):
            guard !next.isSleeping, next.pointerInside != isInside else {
                return PresentationTransition(state: state)
            }
            next.pointerInside = isInside
            if isInside {
                next.peekGeneration += 1
                next.collapseGeneration += 1
                effects.append(.cancel(.collapse))
                effects.append(.schedule(.peek, after: .milliseconds(100), generation: next.peekGeneration))
            } else {
                next.peekGeneration += 1
                effects.append(.cancel(.peek))
                if next.peekVisible && !next.pinnedOpen && next.transientPhase == nil && !next.snapshot.phase.isAttention && next.feedback == nil {
                    next.collapseGeneration += 1
                    effects.append(.schedule(.collapse, after: .milliseconds(320), generation: next.collapseGeneration))
                }
            }

        case .togglePinned:
            guard !next.isSleeping, next.feedback == nil else { return PresentationTransition(state: state) }
            next.pinnedOpen.toggle()
            if next.pinnedOpen {
                next.collapseGeneration += 1
                effects.append(.cancel(.collapse))
            } else if next.pointerInside && next.transientPhase == nil && !next.snapshot.phase.isAttention && next.feedback == nil {
                next.peekVisible = true
            }

        case .collapse:
            next.pinnedOpen = false
            next.peekGeneration += 1
            next.peekVisible = false
            next.collapseGeneration += 1
            effects += [.cancel(.peek), .cancel(.collapse)]

        case let .timerElapsed(timer, generation):
            switch timer {
            case .peek:
                guard generation == next.peekGeneration, next.pointerInside, !next.pinnedOpen,
                      next.transientPhase == nil, !next.snapshot.phase.isAttention, next.feedback == nil, !next.isSleeping
                else { return PresentationTransition(state: state) }
                next.peekVisible = true
            case .collapse:
                guard generation == next.collapseGeneration, !next.pointerInside, !next.pinnedOpen,
                      next.transientPhase == nil, !next.snapshot.phase.isAttention, next.feedback == nil
                else { return PresentationTransition(state: state) }
                next.peekVisible = false
            case .feedback:
                guard generation == next.feedbackGeneration, !next.isSleeping else {
                    return PresentationTransition(state: state)
                }
                next.feedback = nil
                next.peekVisible = false
            case .transient:
                guard generation == next.transientGeneration, !next.isSleeping else {
                    return PresentationTransition(state: state)
                }
                next.transientPhase = nil
                next.transientPresentationKey = nil
                if next.pointerInside { next.peekVisible = true }
            }

        case .sleep:
            guard !next.isSleeping else { return PresentationTransition(state: state) }
            next.isSleeping = true
            next.feedback = nil
            next.feedbackGeneration += 1
            next.pointerInside = false
            next.peekVisible = false
            next.transientPhase = nil
            next.transientPresentationKey = nil
            next.peekGeneration += 1
            next.collapseGeneration += 1
            next.transientGeneration += 1
            effects = [.cancel(.peek), .cancel(.collapse), .cancel(.transient), .cancel(.feedback)]

        case .wake:
            guard next.isSleeping else { return PresentationTransition(state: state) }
            next.isSleeping = false
            next.lastWakeAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 * 1_000) / 1_000)
            next.transientPhase = nil
            next.transientPresentationKey = nil
            next.transientGeneration += 1
            effects.append(.cancel(.transient))
        }

        return PresentationTransition(state: next, effects: effects)
    }

    private static func completionKey(_ snapshot: ActivitySnapshot) -> String {
        [snapshot.sessionID, snapshot.turnID].map { "\($0.utf8.count):\($0)" }.joined()
    }

    private static func remember(_ key: String, in values: inout [String]) {
        values.append(key)
        if values.count > 128 { values.removeFirst(values.count - 128) }
    }

    private func snapshotOccurredBeforeWake(_ snapshot: ActivitySnapshot, state: PresentationState) -> Bool {
        state.lastWakeAt != .distantPast && snapshot.observedAt <= state.lastWakeAt
    }
}
