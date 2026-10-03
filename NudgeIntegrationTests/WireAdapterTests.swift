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
                     projectLabel: project, toolCallID: toolID, tool: tool)
    }

    private func edgeCaseLines(_ name: String) throws -> [Data] {
        let url = Bundle(for: Self.self).resourceURL!
            .appendingPathComponent("Codex/edge-cases/\(name)")
        return try Data(contentsOf: url).split(separator: 0x0A).map(Data.init)
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
        case .stop: kind = .turnFinished
        case .interrupt: kind = .interrupted
        }
        return NudgeEvent(sessionID: envelope.sessionID, turnID: envelope.turnID, observedAt: observedAt,
                          kind: kind, projectLabel: envelope.projectLabel)
    }
}
