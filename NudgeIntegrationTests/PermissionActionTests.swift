import Foundation
import XCTest

final class PermissionActionTests: XCTestCase {
    func testPermissionFrameRejectsUnknownFieldsAndUnsafeSummaries() throws {
        let safe = request(summary: "Run the unit tests")
        try safe.validate()
        XCTAssertTrue(safe.isActionable)
        XCTAssertNil(PermissionRequestSanitizer.summary(from: "Read /Users/me/private.txt"))
        XCTAssertNil(PermissionRequestSanitizer.summary(from: "Use the API key from settings"))

        let extraField = Data(#"{"schema":1,"request_id":"00000000-0000-0000-0000-000000000001","interaction_id":"00000000-0000-0000-0000-000000000001","session_id":"s","turn_id":"t","tool_call_id":null,"tool_name":"Bash","summary":"Run the unit tests","budget_ms":1000,"command":"echo unsafe"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PermissionRequestMessage.self, from: extraField))
        let duplicateField = Data(#"{"schema":1,"schema":1}"#.utf8)
        XCTAssertThrowsError(try PermissionMessageCodec.decodeRequest(duplicateField))
        XCTAssertThrowsError(try PermissionMessageCodec.decodeResponse(duplicateField))
    }

    func testPermissionSocketRoundTripsOneInvocationDecision() throws {
        let path = "/tmp/nudge-test-\(UUID().uuidString.lowercased()).sock"
        let server = NudgePermissionSocketServer(path: path) { request in
            request.requestID == request.interactionID ? .allowOnce : .deny
        }
        try server.start()
        defer { server.stop() }

        let request = request(summary: "Run the unit tests")
        XCTAssertEqual(try PermissionSocketTransport.exchange(request, path: path, timeout: 2), .allowOnce)
    }

    func testBrokerClaimsARequestOnceAndKeepsDecisionInvocationScoped() async {
        let sink = PermissionStatusSink()
        let request = request(summary: "Run the unit tests")
        let broker = PermissionBroker(
            onStatus: { request, status in await sink.record(status, for: request.requestID) },
            validateContext: { _ in true }
        )
        let waiting = Task { await broker.waitForDecision(request, enabled: true) }

        for _ in 0..<100 {
            if await sink.status(for: request.requestID) == .available { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        let first = await broker.decide(interactionID: request.interactionID,
                                        sessionID: request.sessionID, turnID: request.turnID,
                                        decision: .allowOnce)
        let duplicate = await broker.decide(interactionID: request.interactionID,
                                            sessionID: request.sessionID, turnID: request.turnID,
                                            decision: .deny)
        let received = await waiting.value

        XCTAssertTrue(first)
        XCTAssertFalse(duplicate)
        XCTAssertEqual(received, .allowOnce)
        let finalStatus = await sink.status(for: request.requestID)
        XCTAssertEqual(finalStatus, .sentToCodex)
    }

    func testExpiredOrDisabledBrokerReturnsToNativeApprovalWithoutDecision() async {
        let sink = PermissionStatusSink()
        let disabled = request(summary: "Run the unit tests", budgetMilliseconds: 50)
        let broker = PermissionBroker(
            onStatus: { request, status in await sink.record(status, for: request.requestID) },
            validateContext: { _ in true }
        )

        let disabledDecision = await broker.waitForDecision(disabled, enabled: false)
        let expiredDecision = await broker.waitForDecision(disabled, enabled: true)
        XCTAssertNil(disabledDecision)
        XCTAssertNil(expiredDecision)
        for _ in 0..<100 {
            if await sink.status(for: disabled.requestID) == .expired { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let finalStatus = await sink.status(for: disabled.requestID)
        XCTAssertEqual(finalStatus, .expired)
    }

    func testBrokerQueuesRequestsInOrderWithinOneSession() async {
        let sink = PermissionStatusSink()
        let firstRequest = request(summary: "Run the unit tests")
        let secondRequest = request(summary: "Run the build")
        let broker = PermissionBroker(
            onStatus: { request, status in await sink.record(status, for: request.requestID) },
            validateContext: { _ in true }
        )
        let firstWaiting = Task { await broker.waitForDecision(firstRequest, enabled: true) }
        for _ in 0..<100 {
            if await sink.status(for: firstRequest.requestID) == .available { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let secondWaiting = Task { await broker.waitForDecision(secondRequest, enabled: true) }
        for _ in 0..<100 {
            if await sink.status(for: secondRequest.requestID) == .queued { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        let firstStatus = await sink.status(for: firstRequest.requestID)
        let secondStatus = await sink.status(for: secondRequest.requestID)
        XCTAssertEqual(firstStatus, .available)
        XCTAssertEqual(secondStatus, .queued)
        let firstClaim = await broker.decide(interactionID: firstRequest.interactionID,
                                             sessionID: firstRequest.sessionID, turnID: firstRequest.turnID,
                                             decision: .deny)
        let firstResult = await firstWaiting.value
        for _ in 0..<100 {
            if await sink.status(for: secondRequest.requestID) == .available { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let secondClaim = await broker.decide(interactionID: secondRequest.interactionID,
                                              sessionID: secondRequest.sessionID, turnID: secondRequest.turnID,
                                              decision: .allowOnce)
        let secondResult = await secondWaiting.value

        XCTAssertTrue(firstClaim)
        XCTAssertEqual(firstResult, .deny)
        XCTAssertTrue(secondClaim)
        XCTAssertEqual(secondResult, .allowOnce)
    }

    func testBrokerRejectsStaleContextAndReconcilesOnlyTheMatchingTool() async {
        let sink = PermissionStatusSink()
        let permissionRequest = request(summary: "Run the unit tests")
        let broker = PermissionBroker(
            onStatus: { request, status in await sink.record(status, for: request.requestID) },
            validateContext: { _ in true }
        )
        let waiting = Task { await broker.waitForDecision(permissionRequest, enabled: true) }
        for _ in 0..<100 {
            if await sink.status(for: permissionRequest.requestID) == .available { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        let unrelated = WireEnvelope(schemaVersion: 1, source: "codex", event: .postToolUse,
                                     sessionID: permissionRequest.sessionID, turnID: permissionRequest.turnID,
                                     observedAtMilliseconds: 2, projectLabel: nil, toolCallID: "another-tool",
                                     tool: nil)
        await broker.reconcile(unrelated)
        let matching = WireEnvelope(schemaVersion: 1, source: "codex", event: .postToolUse,
                                    sessionID: permissionRequest.sessionID, turnID: permissionRequest.turnID,
                                    observedAtMilliseconds: 3, projectLabel: nil, toolCallID: permissionRequest.toolCallID,
                                    tool: nil)
        await broker.reconcile(matching)
        let result = await waiting.value
        let finalStatus = await sink.status(for: permissionRequest.requestID)
        XCTAssertNil(result)
        XCTAssertEqual(finalStatus, .returnedToCodex)

        let staleSink = PermissionStatusSink()
        let staleRequest = request(summary: "Run the unit tests")
        let staleBroker = PermissionBroker(
            onStatus: { request, status in await staleSink.record(status, for: request.requestID) },
            validateContext: { _ in false }
        )
        let staleWaiting = Task { await staleBroker.waitForDecision(staleRequest, enabled: true) }
        for _ in 0..<100 {
            if await staleSink.status(for: staleRequest.requestID) == .available { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        let staleClaim = await staleBroker.decide(interactionID: staleRequest.interactionID,
                                                  sessionID: staleRequest.sessionID, turnID: staleRequest.turnID,
                                                  decision: .allowOnce)
        let staleResult = await staleWaiting.value
        XCTAssertFalse(staleClaim)
        XCTAssertNil(staleResult)
    }

    func testOfficialHookOutputIsOneShotAndContainsNoPersistentGrant() throws {
        let allow = try XCTUnwrap(BridgeProcessor.hookOutput(for: .allowOnce))
        let allowObject = try JSONSerialization.jsonObject(with: allow) as! [String: Any]
        let allowHook = allowObject["hookSpecificOutput"] as! [String: Any]
        let allowDecision = allowHook["decision"] as! [String: Any]
        XCTAssertEqual(allowHook["hookEventName"] as? String, "PermissionRequest")
        XCTAssertEqual(allowDecision["behavior"] as? String, "allow")
        XCTAssertEqual(Set(allowDecision.keys), ["behavior"])

        let deny = try XCTUnwrap(BridgeProcessor.hookOutput(for: .deny))
        let denyObject = try JSONSerialization.jsonObject(with: deny) as! [String: Any]
        let denyHook = denyObject["hookSpecificOutput"] as! [String: Any]
        let denyDecision = denyHook["decision"] as! [String: Any]
        XCTAssertEqual(denyDecision["behavior"] as? String, "deny")
        XCTAssertNotNil(denyDecision["message"] as? String)
    }

    private func request(summary: String?, budgetMilliseconds: Int = 1_000) -> PermissionRequestMessage {
        let id = UUID().uuidString.lowercased()
        return PermissionRequestMessage(requestID: id, interactionID: id, sessionID: "session-1",
                                        turnID: "turn-1", toolCallID: "tool-1", toolName: "Bash",
                                        summary: summary, budgetMilliseconds: budgetMilliseconds)
    }

}

private actor PermissionStatusSink {
    private var statuses: [String: PermissionActionStatus] = [:]
    func record(_ status: PermissionActionStatus, for id: String) { statuses[id] = status }
    func status(for id: String) -> PermissionActionStatus? { statuses[id] }
}
