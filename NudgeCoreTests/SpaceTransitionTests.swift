import XCTest

@MainActor
final class SpaceTransitionTests: XCTestCase {
    @MainActor
    private final class ManualWait {
        var pending: [CheckedContinuation<Void, Never>] = []
        var durations: [Duration] = []

        func wait(_ duration: Duration) async {
            durations.append(duration)
            await withCheckedContinuation { pending.append($0) }
        }

        func untilPending(_ count: Int = 1) async throws {
            for _ in 0..<10_000 {
                if pending.count >= count { return }
                await Task.yield()
            }
            throw NSError(domain: "SpaceTransitionTests", code: 1)
        }

        func advance() { pending.removeFirst().resume() }
        func finish() {
            let remaining = pending
            pending = []
            remaining.forEach { $0.resume() }
        }
    }

    func testFadeReturnsOnlyAfterSettlingAndFinishesAfterFadeIn() async throws {
        let clock = ManualWait()
        let transition = SpaceTransition(wait: { await clock.wait($0) })
        defer { transition.cancel(); clock.finish() }
        var opacities: [Double] = []
        var durations: [Double] = []
        var completed = false
        let work = transition.begin(reduceMotion: false, fade: {
            opacities.append($0); durations.append($1)
        }, completed: { completed = true })
        XCTAssertEqual(opacities, [0])
        XCTAssertTrue(transition.isTransitioning)
        try await clock.untilPending()
        XCTAssertEqual(clock.durations, [.milliseconds(350)])
        clock.advance()
        try await clock.untilPending()
        XCTAssertEqual(opacities, [0, 1])
        XCTAssertEqual(durations, [0.10, 0.18])
        XCTAssertFalse(completed)
        clock.advance()
        await work.value
        XCTAssertTrue(completed)
        XCTAssertFalse(transition.isTransitioning)
    }

    func testNewSpaceCancelsOldReturn() async throws {
        let clock = ManualWait()
        let transition = SpaceTransition(wait: { await clock.wait($0) })
        defer { transition.cancel(); clock.finish() }
        var events: [String] = []
        let old = transition.begin(reduceMotion: false,
            fade: { alpha, _ in events.append("old-\(alpha)") }, completed: { events.append("old-done") })
        try await clock.untilPending()
        let latest = transition.begin(reduceMotion: false,
            fade: { alpha, _ in events.append("new-\(alpha)") }, completed: { events.append("new-done") })
        try await clock.untilPending(2)
        clock.advance()
        await old.value
        XCTAssertEqual(events, ["old-0.0", "new-0.0"])
        XCTAssertTrue(transition.isTransitioning)
        clock.advance()
        try await clock.untilPending()
        clock.advance()
        await latest.value
        XCTAssertEqual(events, ["old-0.0", "new-0.0", "new-1.0", "new-done"])
    }

    func testCancelDuringEitherWaitPreventsStaleCompletion() async throws {
        for cancelDuringFadeIn in [false, true] {
            let clock = ManualWait()
            let transition = SpaceTransition(wait: { await clock.wait($0) })
            defer { transition.cancel(); clock.finish() }
            var opacities: [Double] = []
            var completed = false
            let work = transition.begin(reduceMotion: false, fade: { alpha, _ in opacities.append(alpha) },
                                        completed: { completed = true })
            try await clock.untilPending()
            if cancelDuringFadeIn {
                clock.advance()
                try await clock.untilPending()
            }
            transition.cancel()
            clock.advance()
            await work.value
            XCTAssertEqual(opacities, cancelDuringFadeIn ? [0, 1] : [0])
            XCTAssertFalse(completed)
            XCTAssertFalse(transition.isTransitioning)
        }
    }

    func testReduceMotionUsesImmediateOpacityChanges() async throws {
        let clock = ManualWait()
        let transition = SpaceTransition(wait: { await clock.wait($0) })
        defer { transition.cancel(); clock.finish() }
        var durations: [Double] = []
        let work = transition.begin(reduceMotion: true, fade: { _, duration in durations.append(duration) }, completed: {})
        try await clock.untilPending()
        clock.advance()
        try await clock.untilPending()
        clock.advance()
        await work.value
        XCTAssertEqual(durations, [0, 0])
        XCTAssertFalse(transition.isTransitioning)
    }
}
