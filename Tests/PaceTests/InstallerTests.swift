import XCTest
@testable import Pace

/// The installer edits a file the user owns. These tests try to make it lose data.
final class InstallerTests: XCTestCase {
    var dir: URL!
    var saved: URL!

    override func setUpWithError() throws {
        saved = StatusLineInstaller.claudeDirectory
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pace-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        StatusLineInstaller.claudeDirectory = dir
    }

    override func tearDownWithError() throws {
        StatusLineInstaller.claudeDirectory = saved
        try? FileManager.default.removeItem(at: dir)
    }

    func settings() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: StatusLineInstaller.settingsURL)) as! [String: Any]
    }

    func write(_ text: String) throws {
        try text.write(to: StatusLineInstaller.settingsURL, atomically: true, encoding: .utf8)
    }

    func testFreshInstallCreatesSettings() throws {
        try StatusLineInstaller.install()
        XCTAssertEqual(StatusLineInstaller.status(), .installed)
        XCTAssertEqual((try settings()["statusLine"] as? [String: String])?["command"], StatusLineInstaller.command)
        let perms = try FileManager.default.attributesOfItem(atPath: StatusLineInstaller.scriptURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o755)
    }

    func testKeepsEveryOtherKey() throws {
        try write(#"{"model":"x","permissions":{"allow":["Bash(ls)"]},"env":{"A":"1"}}"#)
        try StatusLineInstaller.install()
        let s = try settings()
        XCTAssertEqual(s["model"] as? String, "x")
        XCTAssertEqual((s["permissions"] as? [String: [String]])?["allow"], ["Bash(ls)"])
        XCTAssertEqual((s["env"] as? [String: String])?["A"], "1")
    }

    func testNeverOverwritesInvalidJSON() throws {
        let broken = #"{"model": "x", // a comment Claude Code tolerates but JSON does not"#
        try write(broken)
        XCTAssertThrowsError(try StatusLineInstaller.install())
        XCTAssertEqual(try String(contentsOf: StatusLineInstaller.settingsURL, encoding: .utf8), broken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: StatusLineInstaller.scriptURL.path), "nothing written before the check")
    }

    func testWritesThroughSymlinkAndKeepsPermissions() throws {
        let real = dir.appendingPathComponent("dotfiles-settings.json")
        try #"{"model":"x"}"#.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: StatusLineInstaller.settingsURL, withDestinationURL: real)

        try StatusLineInstaller.install()

        let attrs = try FileManager.default.attributesOfItem(atPath: StatusLineInstaller.settingsURL.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink, "symlink must survive")
        let realAttrs = try FileManager.default.attributesOfItem(atPath: real.path)
        XCTAssertEqual((realAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertNotNil(try settings()["statusLine"])
    }

    func testChainsAnExistingStatusLineAndUninstallRestoresIt() throws {
        try write(#"{"statusLine":{"type":"command","command":"~/my-line.sh"}}"#)
        try StatusLineInstaller.install()
        XCTAssertEqual(try String(contentsOf: StatusLineInstaller.chainURL, encoding: .utf8), "~/my-line.sh")
        let chainPerms = try FileManager.default.attributesOfItem(atPath: StatusLineInstaller.chainURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(chainPerms?.intValue, 0o600)

        // Reinstalling must not chain Pace to itself or replace the original backup.
        try StatusLineInstaller.install()
        XCTAssertEqual(try String(contentsOf: StatusLineInstaller.chainURL, encoding: .utf8), "~/my-line.sh")
        let backup = try JSONSerialization.jsonObject(with: Data(contentsOf: StatusLineInstaller.backupURL)) as! [String: Any]
        XCTAssertEqual((backup["statusLine"] as? [String: String])?["command"], "~/my-line.sh")

        try StatusLineInstaller.uninstall()
        XCTAssertEqual((try settings()["statusLine"] as? [String: String])?["command"], "~/my-line.sh")
        XCTAssertFalse(FileManager.default.fileExists(atPath: StatusLineInstaller.scriptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: StatusLineInstaller.chainURL.path))
    }

    func testUninstallWithoutPreviousLineRemovesTheKey() throws {
        try write(#"{"model":"x"}"#)
        try StatusLineInstaller.install()
        try StatusLineInstaller.uninstall()
        let s = try settings()
        XCTAssertNil(s["statusLine"])
        XCTAssertEqual(s["model"] as? String, "x")
        XCTAssertEqual(StatusLineInstaller.status(), .notInstalled)
    }

    func testEmptyFileIsTreatedAsEmptySettings() throws {
        try write("\n")
        try StatusLineInstaller.install()
        XCTAssertEqual(StatusLineInstaller.status(), .installed)
    }

    func testUserCommandMentioningPaceIsNotMistakenForPace() throws {
        try write(#"{"statusLine":{"type":"command","command":"~/scripts/my-pace-statusline.sh"}}"#)
        try StatusLineInstaller.install()
        XCTAssertEqual(try String(contentsOf: StatusLineInstaller.chainURL, encoding: .utf8), "~/scripts/my-pace-statusline.sh")
        try StatusLineInstaller.uninstall()
        XCTAssertEqual((try settings()["statusLine"] as? [String: String])?["command"], "~/scripts/my-pace-statusline.sh")
    }

    func testOtherStatusLineFieldsSurviveInstallAndUninstall() throws {
        try write(#"{"statusLine":{"type":"command","command":"~/line.sh","padding":2}}"#)
        try StatusLineInstaller.install()
        XCTAssertEqual((try settings()["statusLine"] as? [String: Any])?["padding"] as? Int, 2)
        try StatusLineInstaller.uninstall()
        let line = try settings()["statusLine"] as? [String: Any]
        XCTAssertEqual(line?["command"] as? String, "~/line.sh")
        XCTAssertEqual(line?["padding"] as? Int, 2)
    }

    func testDanglingSymlinkIsNotReplaced() throws {
        try FileManager.default.createSymbolicLink(at: StatusLineInstaller.settingsURL,
                                                   withDestinationURL: dir.appendingPathComponent("gone.json"))
        XCTAssertThrowsError(try StatusLineInstaller.install()) { error in
            XCTAssertEqual(error as? StatusLineInstaller.InstallError, .danglingSymlink)
        }
        let attrs = try FileManager.default.attributesOfItem(atPath: StatusLineInstaller.settingsURL.path)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
    }

    func testPrivateSettingsNeverBecomeWorldReadable() throws {
        try write(#"{"env":{"SECRET":"x"}}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: StatusLineInstaller.settingsURL.path)
        try StatusLineInstaller.install()
        let mode = try FileManager.default.attributesOfItem(atPath: StatusLineInstaller.settingsURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
        let backupMode = try FileManager.default.attributesOfItem(atPath: StatusLineInstaller.backupURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(backupMode?.intValue, 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".") && $0.contains(".pace-") }
        XCTAssertEqual(leftovers, [], "no temp files left behind")
    }

    func testUninstallRemovesEveryFilePaceCreated() throws {
        try write(#"{"statusLine":{"type":"command","command":"~/line.sh"}}"#)
        try StatusLineInstaller.install()
        try StatusLineInstaller.uninstall()
        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(left, ["settings.json"])
    }

    func testOutdatedInstalledScriptIsRefreshedAndSettingsAreUntouched() throws {
        try write(#"{"model":"x"}"#)
        try StatusLineInstaller.install()
        try "#!/bin/bash\n# an old version\n".write(to: StatusLineInstaller.scriptURL, atomically: true, encoding: .utf8)
        let settingsBefore = try Data(contentsOf: StatusLineInstaller.settingsURL)
        XCTAssertTrue(StatusLineInstaller.refreshInstalledScript())
        XCTAssertEqual(try String(contentsOf: StatusLineInstaller.scriptURL, encoding: .utf8), StatusLineScript.contents + "\n")
        XCTAssertEqual(try Data(contentsOf: StatusLineInstaller.settingsURL), settingsBefore)
        XCTAssertFalse(StatusLineInstaller.refreshInstalledScript(), "nothing to do when current")
    }

    func testRefreshDoesNothingWhenNotInstalled() throws {
        try write(#"{"statusLine":{"type":"command","command":"~/mine.sh"}}"#)
        XCTAssertFalse(StatusLineInstaller.refreshInstalledScript())
        XCTAssertFalse(FileManager.default.fileExists(atPath: StatusLineInstaller.scriptURL.path))
    }
}
