import XCTest

final class CodexThreadMetadataReaderTests: XCTestCase {
    func testReadOnlyThreadMetadataReturnsMatchingBoundedTitle() async throws {
        let fixture = try FakeAppServer(script: """
            #!/bin/sh
            IFS= read -r first
            printf '%s\\n' '{"id":1,"result":{}}'
            IFS= read -r second
            IFS= read -r third
            printf '%s\\n' "$third" > "$CODEX_HOME/request.json"
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"test-thread","name":"  Fix widgets  "}}}'
            """)
        defer { fixture.remove() }

        let reader = CodexThreadMetadataReader(binaryCandidates: [fixture.binary], timeoutMilliseconds: 2_500)
        let title = await reader.title(for: "test-thread", codexHomes: [fixture.home])
        XCTAssertEqual(title, "Fix widgets")
        let requestData = try Data(contentsOf: fixture.home.appendingPathComponent("request.json"))
        let request = try XCTUnwrap(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        XCTAssertEqual(request["method"] as? String, "thread/read")
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        XCTAssertEqual(params["threadId"] as? String, "test-thread")
        XCTAssertEqual(params["includeTurns"] as? Bool, false)
    }

    func testWrongIdentityAndMissingNameNeverBecomeDisplayedTitle() {
        let wrong: [String: Any] = ["result": ["thread": ["id": "other", "name": "Other person's chat"]]]
        XCTAssertNil(CodexThreadMetadataReader.title(in: wrong, expectedSessionID: "wanted"))
        let absent: [String: Any] = ["result": ["thread": ["id": "wanted"]]]
        XCTAssertNil(CodexThreadMetadataReader.title(in: absent, expectedSessionID: "wanted"))
        let control: [String: Any] = ["result": ["thread": ["id": "wanted", "name": "Line\n two"]]]
        XCTAssertEqual(CodexThreadMetadataReader.title(in: control, expectedSessionID: "wanted"), "Line two")
    }

    func testUnresponsiveMetadataProcessReturnsWithinDeadline() async throws {
        let fixture = try FakeAppServer(script: "#!/bin/sh\nsleep 2\n")
        defer { fixture.remove() }
        let reader = CodexThreadMetadataReader(binaryCandidates: [fixture.binary], timeoutMilliseconds: 100)
        let start = Date()
        let title = await reader.title(for: "test-thread", codexHomes: [fixture.home])
        XCTAssertNil(title)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}

private struct FakeAppServer {
    let root: URL
    let binary: URL
    let home: URL

    init(script: String) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        binary = root.appendingPathComponent("fake-codex")
        home = root.appendingPathComponent("codex-home", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
