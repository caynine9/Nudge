import XCTest

final class WireAdapterTests: XCTestCase {
    private let hooks: [CodexHookEvent] = [.sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .stop, .interrupt]

    func testSyntheticDesktopAndCLIFixturesSanitizePayloadBeforeWire() throws {
        for host in ["desktop", "cli"] {
            for hook in hooks {
                let fixture = Bundle(for: Self.self).resourceURL!
                    .appendingPathComponent("Codex/\(host)/\(hook.rawValue).json")
                let input = try Data(contentsOf: fixture)
                let envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: hook,
                    now: Date(timeIntervalSince1970: 1_700_000_000))
                try envelope.validate()
                let wire = try WireCodec.encode(envelope)
                let wireString = String(decoding: wire.dropFirst(4), as: UTF8.self)
                XCTAssertFalse(wireString.contains("SYNTHETIC_SECRET"), "\(host) \(hook)")
                XCTAssertFalse(wireString.contains("tool_input"))
                XCTAssertFalse(wireString.contains("tool_response"))
                XCTAssertEqual(envelope.event, hook)
                if hook == .preToolUse { XCTAssertEqual(envelope.tool?.summary, "Running command") }
            }
        }
    }

    func testUnexpectedEventAndOversizedIdentityAreRejected() {
        let unexpected = Data(#"{"hook_event_name":"PermissionRequest","session_id":"s"}"#.utf8)
        XCTAssertThrowsError(try CodexHookAdapter().envelope(from: unexpected, expectedEvent: .sessionStart))

        let longID = String(repeating: "x", count: 300)
        let oversized = Data(#"{"hook_event_name":"SessionStart","session_id":"\#(longID)"}"#.utf8)
        XCTAssertThrowsError(try CodexHookAdapter().envelope(from: oversized, expectedEvent: .sessionStart))
    }

    func testStopAfterContinuationIsDeliveredWithoutMisclassifyingFlag() throws {
        let continued = Data(#"{"hook_event_name":"Stop","session_id":"s","turn_id":"t","stop_hook_active":true}"#.utf8)
        let envelope = try CodexHookAdapter().envelope(from: continued, expectedEvent: .stop)
        XCTAssertEqual(envelope.event, .stop)
        XCTAssertEqual(envelope.turnID, "t")
    }

    func testLongRunningToolSurvivesQuietIntervalAndDuplicateEnrichesProject() async {
        let monitor = CodexEventMonitor()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let tool = ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        let first = makeEnvelope(.preToolUse, session: "long", turn: "opaque-turn", at: startedAt,
                                 toolID: "tool", tool: tool)
        let initial = await monitor.consume(first, now: startedAt, monotonicNow: 1_000)
        XCTAssertEqual(initial.focused.phase, .toolUse)

        // Identical normalized tool identity is a duplicate, but a newly valid
        // project label still enriches the placeholder session.
        let enriched = makeEnvelope(.preToolUse, session: "long", turn: "opaque-turn",
                                    at: startedAt.addingTimeInterval(0.1), project: "Sandbox", toolID: "tool", tool: tool)
        let afterDuplicate = await monitor.consume(enriched, now: startedAt.addingTimeInterval(0.1), monotonicNow: 1_100)
        XCTAssertEqual(afterDuplicate.focused.projectLabel, "Sandbox")
        XCTAssertEqual(afterDuplicate.focused.phase, .toolUse)

        let afterQuietInterval = await monitor.currentSnapshot(now: startedAt.addingTimeInterval(24 * 60 * 60))
        XCTAssertEqual(afterQuietInterval.focused.sessionID, "long")
        XCTAssertEqual(afterQuietInterval.focused.phase, .toolUse)
        XCTAssertEqual(afterQuietInterval.activeSessions.map(\.sessionID), ["long"])
    }

    func testActiveSessionProjectionUsesMostRecentTurnAndToolUpdatesDoNotReorder() async {
        let monitor = CodexEventMonitor()
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        _ = await monitor.consume(makeEnvelope(.userPromptSubmit, session: "older", turn: "old-turn", at: origin), now: origin)
        _ = await monitor.consume(makeEnvelope(.userPromptSubmit, session: "newer", turn: "new-turn", at: origin.addingTimeInterval(1)), now: origin.addingTimeInterval(1))
        let snapshot = await monitor.currentSnapshot(now: origin.addingTimeInterval(2))
        XCTAssertEqual(snapshot.activeSessions.map(\.sessionID), ["newer", "older"])
        let tool = ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        let afterTool = await monitor.consume(
            makeEnvelope(.preToolUse, session: "older", turn: "old-turn", at: origin.addingTimeInterval(3),
                         toolID: "old-tool", tool: tool), now: origin.addingTimeInterval(3)
        )
        XCTAssertEqual(afterTool.activeSessions.map(\.sessionID), ["newer", "older"])
    }

    func testHookSummarizesKnownCommandsWithoutForwardingCommandText() throws {
        let input = Data(#"{"session_id":"s","turn_id":"t","cwd":"/tmp/project","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"tool","tool_input":{"command":"swift test --filter SecretSuite"}}"#.utf8)
        let envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: .preToolUse)
        XCTAssertEqual(envelope.tool?.category, .test)
        XCTAssertEqual(envelope.tool?.summary, "Running Swift tests")
        let frame = try WireCodec.encode(envelope)
        let wire = String(decoding: frame.dropFirst(4), as: UTF8.self)
        XCTAssertFalse(wire.contains("SecretSuite"))
        XCTAssertFalse(wire.contains("swift test"))

        let compound = Data(#"{"session_id":"s","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"Bash","tool_use_id":"tool","tool_input":{"command":"swift test && echo TOKEN"}}"#.utf8)
        let fallback = try CodexHookAdapter().envelope(from: compound, expectedEvent: .preToolUse)
        XCTAssertEqual(fallback.tool?.summary, "Running command")
    }

    func testCandidateQuestionPayloadForwardsOnlyTheBoundedQuestionPreview() throws {
        let input = try attentionFixture("request-user-input.json")
        let envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: .preToolUse)

        XCTAssertEqual(envelope.interaction?.kind, .question)
        XCTAssertEqual(envelope.interaction?.toolCallID, "synthetic-question-call")
        XCTAssertEqual(envelope.interaction?.preview, "Which migration strategy should be used?")
        let frame = try WireCodec.encode(envelope)
        let wire = String(decoding: frame.dropFirst(4), as: UTF8.self)
        XCTAssertTrue(wire.contains("Which migration strategy should be used?"))
        XCTAssertFalse(wire.contains("Keep compatibility"))
        XCTAssertFalse(wire.contains("SYNTHETIC_SECRET"))
        XCTAssertFalse(wire.contains("tool_input"))
    }

    func testPermissionRequestWithoutPublishedToolIDStaysDecisionFreeAndSanitized() throws {
        let input = try attentionFixture("permission-request.json")
        let envelope = try CodexHookAdapter().envelope(from: input, expectedEvent: .permissionRequest)

        XCTAssertEqual(envelope.interaction?.kind, .permission)
        XCTAssertNil(envelope.interaction?.toolCallID)
        XCTAssertNil(envelope.interaction?.preview)
        let frame = try WireCodec.encode(envelope)
        let wire = String(decoding: frame.dropFirst(4), as: UTF8.self)
        XCTAssertFalse(wire.contains("rm -rf"))
        XCTAssertFalse(wire.contains("SYNTHETIC_SECRET"))
        XCTAssertFalse(wire.contains("description"))
    }

    func testQuestionRemainsPendingUntilItsOwnToolCallFinishes() async throws {
        let monitor = CodexEventMonitor()
        let adapter = CodexHookAdapter()
        let origin = Date(timeIntervalSince1970: 1_700_000_100)
        let question = try adapter.envelope(from: attentionFixture("request-user-input.json"),
                                            expectedEvent: .preToolUse, now: origin)
        let waiting = await monitor.consume(question, now: origin, monotonicNow: 1)
        XCTAssertEqual(waiting.focused.phase, .waitingInput)
        XCTAssertEqual(waiting.focused.pendingInteraction?.preview, "Which migration strategy should be used?")

        let unrelated = makeEnvelope(.postToolUse, session: question.sessionID, turn: question.turnID,
                                     at: origin.addingTimeInterval(1), toolID: "other-tool")
        let afterUnrelated = await monitor.consume(unrelated, now: origin.addingTimeInterval(1), monotonicNow: 2)
        XCTAssertEqual(afterUnrelated.focused.phase, .waitingInput)

        let matching = makeEnvelope(.postToolUse, session: question.sessionID, turn: question.turnID,
                                    at: origin.addingTimeInterval(2), toolID: question.toolCallID)
        let resolved = await monitor.consume(matching, now: origin.addingTimeInterval(2), monotonicNow: 3)
        XCTAssertFalse(resolved.focused.phase.isAttention)
        XCTAssertTrue(resolved.focused.pendingInteractions.isEmpty)
    }

    func testPermissionWithoutRequestIDBindsToTheOnlyActiveMatchingTool() async throws {
        let monitor = CodexEventMonitor()
        let adapter = CodexHookAdapter()
        let origin = Date(timeIntervalSince1970: 1_700_000_200)
        let permission = try adapter.envelope(from: attentionFixture("permission-request.json"),
                                              expectedEvent: .permissionRequest, now: origin)
        let waiting = await monitor.consume(permission, now: origin, monotonicNow: 1)
        XCTAssertEqual(waiting.focused.phase, .waitingPermission)

        let activity = ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        let toolStarted = makeEnvelope(.preToolUse, session: permission.sessionID, turn: permission.turnID,
                                       at: origin.addingTimeInterval(1), toolID: "permission-tool", tool: activity)
        let afterStart = await monitor.consume(toolStarted, now: origin.addingTimeInterval(1), monotonicNow: 2)
        XCTAssertEqual(afterStart.focused.pendingInteraction?.toolCallID, "permission-tool")

        let unrelated = makeEnvelope(.postToolUse, session: permission.sessionID, turn: permission.turnID,
                                     at: origin.addingTimeInterval(2), toolID: "other-tool")
        let afterUnrelated = await monitor.consume(unrelated, now: origin.addingTimeInterval(2), monotonicNow: 3)
        XCTAssertEqual(afterUnrelated.focused.phase, .waitingPermission)

        let matching = makeEnvelope(.postToolUse, session: permission.sessionID, turn: permission.turnID,
                                    at: origin.addingTimeInterval(3), toolID: "permission-tool")
        let resolved = await monitor.consume(matching, now: origin.addingTimeInterval(3), monotonicNow: 4)
        XCTAssertFalse(resolved.focused.phase.isAttention)
        XCTAssertTrue(resolved.focused.pendingInteractions.isEmpty)
    }

    func testAmbiguousPermissionWithoutRequestIDStaysPendingThroughSameNameToolFinishes() async throws {
        let monitor = CodexEventMonitor()
        let adapter = CodexHookAdapter()
        let origin = Date(timeIntervalSince1970: 1_700_000_300)
        let activity = ToolActivity(category: .shell, summary: "Running command", symbol: "terminal")
        let permission = try adapter.envelope(from: attentionFixture("permission-request.json"),
            expectedEvent: .permissionRequest, now: origin.addingTimeInterval(2))
        let firstStart = makeEnvelope(.preToolUse, session: permission.sessionID, turn: permission.turnID,
                                      at: origin, toolID: "first-tool", tool: activity)
        _ = await monitor.consume(firstStart, now: origin, monotonicNow: 1)
        let secondStart = makeEnvelope(.preToolUse, session: permission.sessionID, turn: permission.turnID,
                                       at: origin.addingTimeInterval(1), toolID: "second-tool", tool: activity)
        _ = await monitor.consume(secondStart, now: origin.addingTimeInterval(1), monotonicNow: 2)

        let waiting = await monitor.consume(permission, now: origin.addingTimeInterval(2), monotonicNow: 3)
        XCTAssertEqual(waiting.focused.phase, .waitingPermission)
        XCTAssertNil(waiting.focused.pendingInteraction?.toolCallID)

        let firstFinish = makeEnvelope(.postToolUse, session: permission.sessionID, turn: permission.turnID,
                                       at: origin.addingTimeInterval(3), toolID: "first-tool")
        let afterFirst = await monitor.consume(firstFinish, now: origin.addingTimeInterval(3), monotonicNow: 4)
        XCTAssertEqual(afterFirst.focused.phase, .waitingPermission)

        let secondFinish = makeEnvelope(.postToolUse, session: permission.sessionID, turn: permission.turnID,
                                        at: origin.addingTimeInterval(4), toolID: "second-tool")
        let afterSecond = await monitor.consume(secondFinish, now: origin.addingTimeInterval(4), monotonicNow: 5)
        XCTAssertEqual(afterSecond.focused.phase, .waitingPermission)

        let stopped = makeEnvelope(.stop, session: permission.sessionID, turn: permission.turnID,
                                   at: origin.addingTimeInterval(5))
        let afterStop = await monitor.consume(stopped, now: origin.addingTimeInterval(5), monotonicNow: 6)
        XCTAssertFalse(afterStop.focused.phase.isAttention)
    }

    func testDuplicateStopAfterShortTTLDoesNotCreateSecondCompletion() async {
        let monitor = CodexEventMonitor()
        let origin = Date(timeIntervalSince1970: 1_700_000_000)
        _ = await monitor.consume(makeEnvelope(.userPromptSubmit, session: "s", turn: "turn-z", at: origin),
                                  now: origin, monotonicNow: 10)
        let stop = makeEnvelope(.stop, session: "s", turn: "turn-z", at: origin.addingTimeInterval(1))
        let first = await monitor.consume(stop, now: origin.addingTimeInterval(1), monotonicNow: 1_000)
        let duplicate = await monitor.consume(
            makeEnvelope(.stop, session: "s", turn: "turn-z", at: origin.addingTimeInterval(4)),
            now: origin.addingTimeInterval(4), monotonicNow: 3_000_001_001
        )
        XCTAssertEqual(first.focused.phase, .completed)
        XCTAssertEqual(duplicate.focused.phase, .completed)
        XCTAssertEqual(first.focused.turnID, duplicate.focused.turnID)
    }

    func testEdgeCaseJSONLFixturesDriveExpectedReducerTransitions() throws {
        let reducer = SessionReducer()
        let adapter = CodexHookAdapter()

        let stops = try edgeCaseLines("stop-after-continuation.jsonl")
        var stopState: CodexSessionState?
        var completionCount = 0
        for (index, line) in stops.enumerated() {
            let envelope = try adapt(line, adapter: adapter, at: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)))
            let transition = reducer.reduce(stopState, event: canonicalEvent(envelope))
            stopState = transition.session
            if transition.didCompleteTurn { completionCount += 1 }
        }
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(stopState?.phase, .completed)

        let resumeLine = try XCTUnwrap(edgeCaseLines("resume-without-session-start.jsonl").first)
        let resume = try adapt(resumeLine, adapter: adapter, at: Date(timeIntervalSince1970: 1_700_000_010))
        let resumed = reducer.reduce(nil, event: canonicalEvent(resume)).session
        XCTAssertEqual(resumed?.phase, .toolUse)
        XCTAssertEqual(resumed?.turnID, "opaque:turn/resumed")

        let longToolLines = try edgeCaseLines("long-tool-duplicate-enrichment.jsonl")
        var longTool: CodexSessionState?
        for (index, line) in longToolLines.enumerated() {
            let envelope = try adapt(line, adapter: adapter, at: Date(timeIntervalSince1970: 1_700_000_020 + Double(index)))
            longTool = reducer.reduce(longTool, event: canonicalEvent(envelope)).session
        }
        XCTAssertEqual(longTool?.phase, .toolUse)
        XCTAssertEqual(longTool?.projectLabel, "renamed-project")
        XCTAssertEqual(longTool?.activeTools.count, 1)
    }

    private func makeEnvelope(_ event: CodexHookEvent, session: String, turn: String?, at date: Date,
                              project: String? = nil, toolID: String? = nil, tool: ToolActivity? = nil) -> WireEnvelope {
        WireEnvelope(schemaVersion: WireEnvelope.currentVersion, source: "codex", event: event,
                     sessionID: session, turnID: turn,
                     observedAtMilliseconds: Int64(date.timeIntervalSince1970 * 1_000),
                     projectLabel: project, toolCallID: toolID, tool: tool,
                     toolName: event == .preToolUse || event == .postToolUse ? "Bash" : nil)
    }

    private func edgeCaseLines(_ name: String) throws -> [Data] {
        let url = Bundle(for: Self.self).resourceURL!
            .appendingPathComponent("Codex/edge-cases/\(name)")
        return try Data(contentsOf: url).split(separator: 0x0A).map(Data.init)
    }

    private func attentionFixture(_ name: String) throws -> Data {
        let url = Bundle(for: Self.self).resourceURL!
            .appendingPathComponent("Codex/attention/\(name)")
        return try Data(contentsOf: url)
    }

    private func adapt(_ data: Data, adapter: CodexHookAdapter, at date: Date) throws -> WireEnvelope {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let eventName = try XCTUnwrap(object["hook_event_name"] as? String)
        let expected = try XCTUnwrap(CodexHookEvent(rawValue: eventName))
        return try adapter.envelope(from: data, expectedEvent: expected, now: date)
    }

    private func canonicalEvent(_ envelope: WireEnvelope) -> NudgeEvent {
        let observedAt = Date(timeIntervalSince1970: Double(envelope.observedAtMilliseconds) / 1_000)
        let kind: NudgeEvent.Kind
        switch envelope.event {
        case .sessionStart: kind = .sessionStarted(projectLabel: envelope.projectLabel ?? "Codex")
        case .userPromptSubmit: kind = .promptSubmitted
        case .preToolUse:
            kind = .toolStarted(id: envelope.toolCallID!, activity: envelope.tool!)
        case .postToolUse: kind = .toolFinished(id: envelope.toolCallID!)
        case .permissionRequest:
            kind = .pendingInteraction(PendingInteraction(id: envelope.interaction!.id, kind: .permission,
                toolCallID: envelope.interaction!.toolCallID, toolName: envelope.interaction!.toolName,
                preview: envelope.interaction!.preview))
        case .stop: kind = .turnFinished
        case .interrupt: kind = .interrupted
        }
        return NudgeEvent(sessionID: envelope.sessionID, turnID: envelope.turnID, observedAt: observedAt,
                          kind: kind, projectLabel: envelope.projectLabel, toolName: envelope.toolName,
                          interaction: envelope.event == .preToolUse
                            ? envelope.interaction.map {
                                PendingInteraction(id: $0.id, kind: .question, toolCallID: $0.toolCallID,
                                                   toolName: $0.toolName, preview: $0.preview)
                            }
                            : nil)
    }
}
