import XCTest

final class WireValidationTests: XCTestCase {
    func testUnsupportedVersionAndMissingTurnAreRejectedBeforeStateMutation() throws {
        let valid = envelope()
        let unsupported = WireEnvelope(schemaVersion: 99, source: valid.source, event: valid.event,
            sessionID: valid.sessionID, turnID: valid.turnID, observedAtMilliseconds: valid.observedAtMilliseconds,
            projectLabel: nil, toolCallID: nil, tool: nil)
        XCTAssertThrowsError(try unsupported.validate())

        let missingTurn = WireEnvelope(schemaVersion: 1, source: "codex", event: .stop, sessionID: "session",
            turnID: nil, observedAtMilliseconds: 1, projectLabel: nil, toolCallID: nil, tool: nil)
        XCTAssertThrowsError(try missingTurn.validate())
    }

    func testLengthPrefixRoundTripAndOversizedFrameRejection() throws {
        let frame = try WireCodec.encode(envelope())
        let length = frame.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
        XCTAssertEqual(Int(length), frame.count - 4)
        XCTAssertEqual(try WireCodec.decode(Data(frame.dropFirst(4))), envelope())
        XCTAssertThrowsError(try WireCodec.decode(Data(repeating: 0x41, count: WireEnvelope.maximumFrameSize + 1)))
    }

    func testDuplicateJSONKeysAreRejectedBeforeFoundationDecoding() {
        let duplicated = Data(#"{"schema_version":1,"schema_version":99,"source":"codex","event":"UserPromptSubmit","session_id":"session","turn_id":"turn","observed_at_ms":1,"project_label":null,"tool_call_id":null,"tool":null}"#.utf8)
        XCTAssertThrowsError(try WireCodec.decode(duplicated))
    }

    func testUnknownEnvelopeAndToolFieldsAreRejected() throws {
        let unknownEnvelope = Data(#"{"schema_version":1,"source":"codex","event":"UserPromptSubmit","session_id":"session","turn_id":"turn","observed_at_ms":1,"project_label":null,"tool_call_id":null,"tool":null,"future_field":"ignored"}"#.utf8)
        XCTAssertThrowsError(try WireCodec.decode(unknownEnvelope))

        let unknownTool = Data(#"{"schema_version":1,"source":"codex","event":"PreToolUse","session_id":"session","turn_id":"turn","observed_at_ms":1,"project_label":null,"tool_call_id":"tool-1","tool":{"category":"shell","summary":"Running command","symbol":"terminal","command":"secret"}}"#.utf8)
        XCTAssertThrowsError(try WireCodec.decode(unknownTool))
    }

    func testVersionTwoAllowsOnlyBoundedSummaryAllowlistAndVersionOneRemainsCompatible() throws {
        let legacy = WireEnvelope(schemaVersion: WireEnvelope.legacyVersion, source: "codex", event: .preToolUse,
            sessionID: "session", turnID: "turn", observedAtMilliseconds: 1, projectLabel: nil,
            toolCallID: "tool", tool: ToolActivity(category: .shell, summary: "Running command", symbol: "terminal"))
        let legacyFrame = try WireCodec.encode(legacy)
        XCTAssertEqual(try WireCodec.decode(Data(legacyFrame.dropFirst(4))), legacy)

        let current = WireEnvelope(schemaVersion: WireEnvelope.currentVersion, source: "codex", event: .preToolUse,
            sessionID: "session", turnID: "turn", observedAtMilliseconds: 1, projectLabel: nil,
            toolCallID: "tool", tool: ToolActivity(category: .test, summary: "Running Xcode tests", symbol: "checkmark.circle"))
        let currentFrame = try WireCodec.encode(current)
        XCTAssertEqual(try WireCodec.decode(Data(currentFrame.dropFirst(4))), current)

        let unapproved = WireEnvelope(schemaVersion: WireEnvelope.currentVersion, source: "codex", event: .preToolUse,
            sessionID: "session", turnID: "turn", observedAtMilliseconds: 1, projectLabel: nil,
            toolCallID: "tool", tool: ToolActivity(category: .shell, summary: "swift test --secret token", symbol: "terminal"))
        XCTAssertThrowsError(try WireCodec.encode(unapproved))
    }

    private func envelope() -> WireEnvelope {
        WireEnvelope(schemaVersion: 1, source: "codex", event: .userPromptSubmit, sessionID: "session",
                     turnID: "turn", observedAtMilliseconds: 1, projectLabel: "Fixture", toolCallID: nil, tool: nil)
    }
}
