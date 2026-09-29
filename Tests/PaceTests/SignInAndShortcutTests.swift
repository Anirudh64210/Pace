import XCTest
import Carbon.HIToolbox
@testable import Pace

final class CredentialPickTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func creds(_ token: String, expiresIn: TimeInterval?, plan: String? = nil) -> ClaudeKeychain.Credentials {
        .init(accessToken: token, expiresAt: expiresIn.map { now.addingTimeInterval($0) }, subscriptionType: plan)
    }

    /// The desktop app renews the sign-in into the file and leaves the Keychain stale.
    func testFresherFileWinsOverStaleKeychain() {
        let keychain = creds("old", expiresIn: -600, plan: "max")
        let file = creds("new", expiresIn: 7 * 3600)
        let picked = ClaudeCredentials.pick([keychain, file], now: now)
        XCTAssertEqual(picked?.accessToken, "new")
        XCTAssertEqual(picked?.subscriptionType, "max", "the plan carries over from the Keychain copy")
    }

    func testLaterExpiryWinsWhenBothAreValid() {
        let picked = ClaudeCredentials.pick([creds("a", expiresIn: 3600), creds("b", expiresIn: 7200)], now: now)
        XCTAssertEqual(picked?.accessToken, "b")
    }

    func testBothExpiredReturnsTheLatestSoTheCallerReportsExpired() {
        let picked = ClaudeCredentials.pick([creds("a", expiresIn: -7200), creds("b", expiresIn: -600)], now: now)
        XCTAssertEqual(picked?.accessToken, "b")
        XCTAssertTrue(picked?.isExpired(at: now) == true)
    }

    func testNothingFound() {
        XCTAssertNil(ClaudeCredentials.pick([], now: now))
    }

    func testCredentialsFileMustBePrivate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pace-creds-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"claudeAiOauth":{"accessToken":"t","expiresAt":4102444700000}}"#.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        XCTAssertNil(ClaudeCredentials.readFile(url), "a credentials file others can read is ignored")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        XCTAssertEqual(ClaudeCredentials.readFile(url)?.accessToken, "t")
    }

    func testSymlinkedCredentialsFileIsIgnored() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pace-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent("real.json")
        try #"{"claudeAiOauth":{"accessToken":"t"}}"#.write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        let link = dir.appendingPathComponent(".credentials.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertNil(ClaudeCredentials.readFile(link))
    }
}

@MainActor
final class SignInWaitTests: XCTestCase {
    func testExpiredSignInPausesCalmlyAndRechecksEveryMinute() async {
        var s = UsageSnapshot.empty(source: .oauth)
        s.session = LimitWindow(utilization: 20, resetsAt: Date().addingTimeInterval(3600))
        let stub = StubProvider([.success(s), .failure(ProviderError.tokenExpired)])
        let app = AppState(settings: Settings(defaults: scratchDefaults()), autoPoll: false, provider: stub)
        await app.refresh()
        await app.refresh()
        XCTAssertTrue(app.isWaitingForSignIn)
        XCTAssertNotNil(app.snapshot, "the last numbers stay on screen")
        XCTAssertTrue(app.footerText.hasPrefix("Paused · numbers from "), app.footerText)
        guard case .failed(_, let retryAt?) = app.status else { return XCTFail() }
        XCTAssertEqual(retryAt.timeIntervalSinceNow, 60, accuracy: 5)
    }

    func testRecoversOnTheNextCheckOnceRenewed() async {
        var s = UsageSnapshot.empty(source: .oauth)
        s.session = LimitWindow(utilization: 20, resetsAt: Date().addingTimeInterval(3600))
        let stub = StubProvider([.failure(ProviderError.tokenExpired), .success(s)])
        let app = AppState(settings: Settings(defaults: scratchDefaults()), autoPoll: false, provider: stub)
        await app.refresh()
        XCTAssertTrue(app.isWaitingForSignIn)
        await app.refresh()
        XCTAssertEqual(app.status, .live)
        XCTAssertFalse(app.isWaitingForSignIn)
    }
}

final class ShortcutTests: XCTestCase {
    func testControlCommandP() {
        let s = Shortcut.from(keyCode: UInt16(kVK_ANSI_P), modifiers: [.control, .command], characters: "p")
        XCTAssertEqual(s?.display, "⌃⌘P")
        XCTAssertEqual(s?.spoken, "Control-Command-P")
        XCTAssertEqual(s?.carbonModifiers, UInt32(controlKey | cmdKey))
    }

    func testDefaultIsControlOptionP() {
        XCTAssertEqual(Shortcut.default.display, "⌃⌥P")
        XCTAssertEqual(Shortcut.default.spoken, "Control-Option-P")
    }

    /// Option changes the typed character (⌥P types π); the label comes from the key.
    func testOptionLabelsTheKeyNotTheCharacter() {
        let s = Shortcut.from(keyCode: UInt16(kVK_ANSI_P), modifiers: [.option, .command], characters: "π")
        XCTAssertEqual(s?.display, "⌥⌘P")
    }

    func testRejectsShortcutsThatWouldFireWhileTyping() {
        XCTAssertNil(Shortcut.from(keyCode: UInt16(kVK_ANSI_P), modifiers: [], characters: "p"))
        XCTAssertNil(Shortcut.from(keyCode: UInt16(kVK_ANSI_P), modifiers: [.shift], characters: "P"))
        XCTAssertNil(Shortcut.from(keyCode: UInt16(kVK_Escape), modifiers: [.command], characters: "\u{1b}"))
    }

    func testMenuOrderOfSymbols() {
        let s = Shortcut.from(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .shift, .option, .control], characters: "k")
        XCTAssertEqual(s?.display, "⌃⌥⇧⌘K")
    }

    @MainActor
    func testRecordedShortcutIsSavedAndRegisters() throws {
        let defaults = scratchDefaults()
        let settings = Settings(defaults: defaults)
        settings.shortcut = Shortcut.from(keyCode: UInt16(kVK_ANSI_P), modifiers: [.control, .command], characters: "p")!
        XCTAssertEqual(Settings(defaults: defaults).shortcut.display, "⌃⌘P")
        let hotKey = GlobalHotKey()
        hotKey.register(settings.shortcut) {}
        XCTAssertTrue(hotKey.isRegistered)
        hotKey.unregister()
    }
}

final class RowTextFitTests: XCTestCase {
    /// The weekly reset line has its own full-width line and must fit on it.
    func testLongResetLineFitsTheRowWidth() {
        let text = "resets Wed 11:59 PM · in 6d 23h"
        let width = (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        let available = Theme.panelWidth - 2 * 20 - 18     // panel padding, chevron
        XCTAssertLessThan(width, available)
    }
}
