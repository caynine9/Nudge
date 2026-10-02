import Foundation

/// Owns only the temporary visibility sequence, not session or presentation mode.
@MainActor
final class SpaceTransition {
    typealias Wait = @MainActor (Duration) async throws -> Void
    private let wait: Wait
    private var task: Task<Void, Never>?
    private(set) var isTransitioning = false

    init(wait: @escaping Wait = { try await Task.sleep(for: $0) }) {
        self.wait = wait
    }

    @discardableResult
    func begin(reduceMotion: Bool,
               fade: @escaping @MainActor (_ opacity: Double, _ duration: TimeInterval) -> Void,
               completed: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        cancel()
        isTransitioning = true
        fade(0, reduceMotion ? 0 : 0.10)
        let wait = self.wait
        let work = Task { @MainActor [weak self] in
            do { try await wait(.milliseconds(350)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            fade(1, reduceMotion ? 0 : 0.18)
            do { try await wait(reduceMotion ? .zero : .milliseconds(180)) } catch { return }
            guard !Task.isCancelled else { return }
            self.task = nil
            self.isTransitioning = false
            completed()
        }
        task = work
        return work
    }

    func cancel() {
        task?.cancel()
        task = nil
        isTransitioning = false
    }

    deinit { task?.cancel() }
}
