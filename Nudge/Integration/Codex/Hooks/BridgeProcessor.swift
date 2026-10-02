import Foundation

enum BridgeProcessor {
    static let socketPath = "/tmp/nudge-\(getuid()).sock"

    @discardableResult
    static func forward(_ input: Data, expectedEvent: CodexHookEvent, socketPath: String = Self.socketPath,
                        timeout: TimeInterval = 0.25, now: Date = Date()) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(max(0, timeout) * 1_000_000_000)
        do {
            let envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: expectedEvent, now: now)
            let remaining = DispatchTime.now().uptimeNanoseconds < deadline
                ? Double(deadline - DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
                : 0
            try UnixSocketTransport.send(envelope, to: socketPath, timeout: remaining)
            return true
        } catch {
            return false
        }
    }
}
