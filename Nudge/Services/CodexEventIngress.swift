import Foundation

final class CodexEventIngress: @unchecked Sendable {
    typealias SnapshotHandler = @Sendable (ActivityMonitorSnapshot, CodexHookEvent, String) async -> Void

    private enum Message: Sendable {
        case event(WireEnvelope)
        case snapshot(CheckedContinuation<ActivityMonitorSnapshot, Never>)
    }

    private let continuation: AsyncStream<Message>.Continuation
    private let consumer: Task<Void, Never>

    init(monitor: CodexEventMonitor, onSnapshot: @escaping SnapshotHandler) {
        let (stream, continuation) = AsyncStream<Message>.makeStream()
        self.continuation = continuation
        consumer = Task.detached(priority: .userInitiated) {
            for await message in stream {
                switch message {
                case let .event(envelope):
                    let snapshot = await monitor.consume(envelope)
                    await onSnapshot(snapshot, envelope.event, envelope.sessionID)
                case let .snapshot(reply):
                    reply.resume(returning: await monitor.currentSnapshot())
                }
            }
        }
    }

    func submit(_ envelope: WireEnvelope) {
        continuation.yield(.event(envelope))
    }

    func snapshotAfterPendingEvents() async -> ActivityMonitorSnapshot {
        await withCheckedContinuation { reply in
            continuation.yield(.snapshot(reply))
        }
    }

    func finish() {
        continuation.finish()
    }

    deinit {
        continuation.finish()
        consumer.cancel()
    }
}
