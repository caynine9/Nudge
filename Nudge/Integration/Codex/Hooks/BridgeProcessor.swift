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

    static func forwardPermission(_ input: Data, request: PermissionRequestMessage,
                                  socketPath: String = Self.socketPath,
                                  timeout: TimeInterval = 0.25) -> Bool {
        do {
            var envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: .permissionRequest)
            let interaction = WireInteraction(id: request.interactionID, kind: .permission,
                                              toolCallID: request.toolCallID, toolName: request.toolName,
                                              preview: request.summary)
            envelope = WireEnvelope(schemaVersion: envelope.schemaVersion, source: envelope.source,
                                    event: envelope.event, sessionID: envelope.sessionID, turnID: envelope.turnID,
                                    observedAtMilliseconds: envelope.observedAtMilliseconds,
                                    projectLabel: envelope.projectLabel, toolCallID: envelope.toolCallID,
                                    tool: envelope.tool, toolName: envelope.toolName, interaction: interaction)
            try envelope.validate()
            try UnixSocketTransport.send(envelope, to: socketPath, timeout: timeout)
            return true
        } catch {
            return false
        }
    }

    static func hookOutput(for decision: PermissionDecision) -> Data? {
        let output: [String: Any]
        switch decision {
        case .allowOnce:
            output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                             "decision": ["behavior": "allow"]]]
        case .deny:
            output = ["hookSpecificOutput": ["hookEventName": "PermissionRequest",
                                             "decision": ["behavior": "deny", "message": "Denied in Nudge."]]]
        }
        return try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    }
}
