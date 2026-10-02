import Darwin
import Foundation
import XCTest

final class HookInstallerTests: XCTestCase {
    private var root: URL!
    private var target: CodexConfigurationTarget!
    private var helper: URL!
    private var backups: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-installer-\(UUID().uuidString.prefix(8))", isDirectory: true)
        target = CodexConfigurationTarget(host: .cli, codexHome: root.appendingPathComponent("codex-home", isDirectory: true),
                                          confidence: "temporary test target")
        helper = root.appendingPathComponent("Applications/Nudge's Build/NudgeBridge")
        backups = root.appendingPathComponent("backups", isDirectory: true)
        try FileManager.default.createDirectory(at: target.codexHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testInstallPreservesForeignHooksAndSecondInstallDoesNotRewrite() throws {
        let foreign: [String: Any] = ["type": "command", "command": "printf foreign", "timeout": 5, "custom": ["keep": true]]
        let initial: [String: Any] = ["description": "user owned", "other": ["preserve": true], "hooks": [
            "PreToolUse": [["matcher": "Bash", "hooks": [foreign]], ["matcher": "foreign-empty", "hooks": []]]
        ]]
        let initialBytes = try JSONSerialization.data(withJSONObject: initial, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
        try initialBytes.write(to: target.hooksFile)

        let result = installer.install()
        guard case let .installed(backupPath) = result else { return XCTFail("unexpected result: \(result)") }
        XCTAssertNotNil(backupPath)
        let backup = URL(fileURLWithPath: backupPath!)
        XCTAssertEqual(try Data(contentsOf: backup), initialBytes)
        var backupInfo = stat()
        XCTAssertEqual(lstat(backup.path, &backupInfo), 0)
        XCTAssertEqual(backupInfo.st_mode & 0o777, 0o600)

        let installedBytes = try Data(contentsOf: target.hooksFile)
        var originalIdentity = stat()
        XCTAssertEqual(lstat(target.hooksFile.path, &originalIdentity), 0)
        let parsed = try JSONSerialization.jsonObject(with: installedBytes) as! [String: Any]
        XCTAssertEqual(parsed["description"] as? String, "user owned")
        XCTAssertEqual((parsed["other"] as? [String: Bool])?["preserve"], true)
        let preToolGroups = (parsed["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        XCTAssertTrue(preToolGroups.contains { ($0["hooks"] as? [[String: Any]])?.contains(where: { $0["command"] as? String == "printf foreign" }) == true })
        XCTAssertTrue(preToolGroups.contains { ($0["matcher"] as? String) == "foreign-empty" && ($0["hooks"] as? [[String: Any]])?.isEmpty == true })

        XCTAssertEqual(installer.install(), .alreadyInstalled)
        XCTAssertEqual(try Data(contentsOf: target.hooksFile), installedBytes)
        var repeatedIdentity = stat()
        XCTAssertEqual(lstat(target.hooksFile.path, &repeatedIdentity), 0)
        XCTAssertEqual(repeatedIdentity.st_ino, originalIdentity.st_ino)
    }

    func testDuplicateOwnedEntriesCollapseAndUninstallKeepsForeignData() throws {
        XCTAssertTrue(isInstalled(installer.install()))
        var rootObject = try JSONSerialization.jsonObject(with: Data(contentsOf: target.hooksFile)) as! [String: Any]
        var hooks = rootObject["hooks"] as! [String: Any]
        var groups = hooks["PreToolUse"] as! [[String: Any]]
        let ownedIndex = try XCTUnwrap(groups.firstIndex { group in
            (group["hooks"] as? [[String: Any]])?.contains(where: { ($0["command"] as? String)?.contains("NudgeBridge") == true }) == true
        })
        var group = groups[ownedIndex]
        var handlers = group["hooks"] as! [[String: Any]]
        let ownedHandler = try XCTUnwrap(handlers.first(where: { ($0["command"] as? String)?.contains("NudgeBridge") == true }))
        handlers.append(ownedHandler)
        handlers.append(["type": "command", "command": "other-hook", "custom": true])
        group["hooks"] = handlers
        groups[ownedIndex] = group
        hooks["PreToolUse"] = groups
        rootObject["hooks"] = hooks
        try writeJSON(rootObject)

        XCTAssertTrue(isInstalled(installer.install()))
        let fixed = try JSONSerialization.jsonObject(with: Data(contentsOf: target.hooksFile)) as! [String: Any]
        let fixedGroups = (fixed["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]]
        let ownedCount = fixedGroups.reduce(0) { count, group in
            count + ((group["hooks"] as? [[String: Any]]) ?? []).filter { ($0["command"] as? String)?.contains("NudgeBridge") == true }.count
        }
        XCTAssertEqual(ownedCount, 1)
        XCTAssertTrue(fixedGroups.contains { ($0["hooks"] as? [[String: Any]])?.contains(where: { $0["command"] as? String == "other-hook" }) == true })

        XCTAssertEqual(installer.uninstall(), .removed)
        let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: target.hooksFile)) as! [String: Any]
        XCTAssertTrue(((removed["hooks"] as! [String: Any])["PreToolUse"] as! [[String: Any]])
            .contains { ($0["hooks"] as? [[String: Any]])?.contains(where: { $0["command"] as? String == "other-hook" }) == true })
    }

    func testMalformedDuplicateKeysRemainByteForByteUntouched() throws {
        let bytes = Data(#"{"hooks":{},"hooks":{}}"#.utf8)
        try bytes.write(to: target.hooksFile)
        XCTAssertEqual(installer.install(), .malformedExistingConfig)
        XCTAssertEqual(try Data(contentsOf: target.hooksFile), bytes)
    }

    func testSymlinkConfigIsRejectedWithoutChangingTargetBytes() throws {
        let external = root.appendingPathComponent("foreign-hooks.json")
        let original = Data(#"{"hooks":{"UserPromptSubmit":[]}}"#.utf8)
        try original.write(to: external)
        XCTAssertEqual(symlink(external.path, target.hooksFile.path), 0)

        XCTAssertEqual(installer.install(), .permissionDenied)
        XCTAssertEqual(try Data(contentsOf: external), original)
        var linkInfo = stat()
        XCTAssertEqual(lstat(target.hooksFile.path, &linkInfo), 0)
        XCTAssertEqual(linkInfo.st_mode & S_IFMT, S_IFLNK)
    }

    func testResolverHonorsCustomCodexHomeWithoutReadingRealUserConfig() {
        let custom = root.appendingPathComponent("custom", isDirectory: true)
        let resolved = CodexConfigurationResolver().target(for: .cli,
            environment: ["CODEX_HOME": custom.path], homeDirectory: root)
        XCTAssertEqual(resolved.hooksFile, custom.appendingPathComponent("hooks.json"))
        XCTAssertEqual(resolved.confidence, "CODEX_HOME environment candidate")
        let desktop = CodexConfigurationResolver().target(for: .desktop,
            environment: ["CODEX_HOME": custom.path], homeDirectory: root)
        XCTAssertEqual(desktop.confidence, "Nudge CODEX_HOME; Desktop unverified")
        let explicit = CodexConfigurationResolver().target(for: .cli,
            environment: ["CODEX_HOME": "/ignored"], homeDirectory: root, explicitCodexHome: custom)
        XCTAssertEqual(explicit.hooksFile, resolved.hooksFile)
        XCTAssertEqual(explicit.confidence, "user-selected")
    }

    private var installer: CodexHookInstaller {
        CodexHookInstaller(target: target, helperPath: helper, backupDirectory: backups)
    }

    private func writeJSON(_ object: [String: Any]) throws {
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) + Data("\n".utf8)
        try bytes.write(to: target.hooksFile)
    }

    private func isInstalled(_ result: HookInstallResult) -> Bool {
        if case .installed = result { return true }
        return false
    }
}
