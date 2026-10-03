import Foundation

enum PermissionActionStatus: Equatable, Sendable {
    case available
    case sending
    case sentToCodex
    case queued
    case returnedToCodex
    case expired
    case unavailable
}

actor PermissionBroker {
    typealias StatusHandler = @Sendable (PermissionRequestMessage, PermissionActionStatus) async -> Void
    typealias ContextValidator = @Sendable (PermissionRequestMessage) async -> Bool

    private struct Entry {
        let request: PermissionRequestMessage
        let continuation: CheckedContinuation<PermissionDecision?, Never>
        var state: ChannelState
        let sequence: UInt64
        let deadline: ContinuousClock.Instant
    }
    private enum ChannelState: Equatable { case active, queued }

    private let onStatus: StatusHandler
    private let validateContext: ContextValidator
    private var entries: [String: Entry] = [:]
    private var expiryTasks: [String: Task<Void, Never>] = [:]
    private let maximumActiveChannels = 8
    private var nextSequence: UInt64 = 0

    init(onStatus: @escaping StatusHandler, validateContext: @escaping ContextValidator) {
        self.onStatus = onStatus
        self.validateContext = validateContext
    }

    func waitForDecision(_ request: PermissionRequestMessage, enabled: Bool) async -> PermissionDecision? {
        guard enabled, request.isActionable else {
            await onStatus(request, .unavailable)
            return nil
        }
        guard (try? request.validate()) != nil else { return nil }

        return await withCheckedContinuation { continuation in
            if entries.values.contains(where: { $0.request.interactionID == request.interactionID }) {
                continuation.resume(returning: nil)
                Task { await onStatus(request, .unavailable) }
                return
            }
            guard entries.count < maximumActiveChannels else {
                continuation.resume(returning: nil)
                Task { await onStatus(request, .unavailable) }
                return
            }

            let hasActiveChannel = entries.values.contains {
                $0.request.sessionID == request.sessionID && $0.state == .active
            }
            let state: ChannelState = hasActiveChannel ? .queued : .active
            let deadline = ContinuousClock.now.advanced(by: .milliseconds(request.budgetMilliseconds))
            nextSequence &+= 1
            entries[request.requestID] = Entry(request: request, continuation: continuation,
                                               state: state, sequence: nextSequence, deadline: deadline)
            let requestID = request.requestID
            expiryTasks[requestID] = Task.detached { [weak self] in
                do { try await ContinuousClock().sleep(until: deadline) } catch { return }
                await self?.expire(requestID)
            }
            Task { await onStatus(request, state == .active ? .available : .queued) }
        }
    }

    @discardableResult
    func decide(interactionID: String, sessionID: String, turnID: String,
                decision: PermissionDecision) async -> Bool {
        guard let candidate = entries.values.first(where: {
            $0.request.interactionID == interactionID && $0.request.sessionID == sessionID
                && $0.request.turnID == turnID && $0.state == .active
        }) else { return false }
        guard ContinuousClock.now < candidate.deadline else {
            remove(candidate.request.requestID, status: .expired)
            return false
        }
        guard await validateContext(candidate.request) else {
            remove(candidate.request.requestID, status: .returnedToCodex)
            return false
        }
        guard let entry = entries[candidate.request.requestID], entry.request == candidate.request else { return false }
        guard ContinuousClock.now < entry.deadline else {
            remove(candidate.request.requestID, status: .expired)
            return false
        }
        entries.removeValue(forKey: candidate.request.requestID)
        expiryTasks.removeValue(forKey: candidate.request.requestID)?.cancel()
        await onStatus(entry.request, .sentToCodex)
        entry.continuation.resume(returning: decision)
        promoteNext(for: sessionID)
        return true
    }

    func returnToCodex(interactionID: String) {
        guard let requestID = entries.values.first(where: { $0.request.interactionID == interactionID })?.request.requestID else {
            return
        }
        remove(requestID, status: .returnedToCodex)
    }

    func cancel(sessionID: String, turnID: String?) {
        let requestIDs = entries.values.filter {
            $0.request.sessionID == sessionID && (turnID == nil || $0.request.turnID == turnID)
        }.map { $0.request.requestID }
        for requestID in requestIDs { remove(requestID, status: .returnedToCodex, promote: false) }
    }

    func cancelAll() {
        for requestID in Array(entries.keys) { remove(requestID, status: .returnedToCodex, promote: false) }
    }

    func reconcile(_ envelope: WireEnvelope) {
        let requestIDs: [String]
        switch envelope.event {
        case .userPromptSubmit:
            requestIDs = entries.values.filter {
                $0.request.sessionID == envelope.sessionID && $0.request.turnID != envelope.turnID
            }.map { $0.request.requestID }
        case .interrupt:
            requestIDs = entries.values.filter {
                $0.request.sessionID == envelope.sessionID && $0.request.turnID == envelope.turnID
            }.map { $0.request.requestID }
        case .postToolUse:
            requestIDs = entries.values.filter {
                $0.request.sessionID == envelope.sessionID && $0.request.turnID == envelope.turnID
                    && $0.request.toolCallID != nil && $0.request.toolCallID == envelope.toolCallID
            }.map { $0.request.requestID }
        default:
            requestIDs = []
        }
        let sessionsToPromote: Set<String>
        if envelope.event == .postToolUse {
            sessionsToPromote = Set(entries.values.filter {
                $0.state == .active && requestIDs.contains($0.request.requestID)
            }.map { $0.request.sessionID })
        } else {
            sessionsToPromote = []
        }
        for requestID in requestIDs { remove(requestID, status: .returnedToCodex, promote: false) }
        for sessionID in sessionsToPromote { promoteNext(for: sessionID) }
    }

    private func expire(_ requestID: String) {
        remove(requestID, status: .expired)
    }

    private func remove(_ requestID: String, status: PermissionActionStatus, promote: Bool = true) {
        guard let entry = entries.removeValue(forKey: requestID) else { return }
        expiryTasks.removeValue(forKey: requestID)?.cancel()
        Task { await onStatus(entry.request, status) }
        entry.continuation.resume(returning: nil)
        if promote, entry.state == .active { promoteNext(for: entry.request.sessionID) }
    }

    private func promoteNext(for sessionID: String) {
        guard !entries.values.contains(where: { $0.request.sessionID == sessionID && $0.state == .active }),
              let next = entries.values.filter({ $0.request.sessionID == sessionID && $0.state == .queued })
                .min(by: { $0.sequence < $1.sequence }) else { return }
        entries[next.request.requestID]?.state = .active
        Task { await onStatus(next.request, .available) }
    }
}
