import XCTest
@testable import Pace

@MainActor
final class LaunchTests: XCTestCase {
    func testShortcutRegistersAndUnregisters() {
        let hotKey = GlobalHotKey()
        hotKey.register {}
        XCTAssertTrue(hotKey.isRegistered, "⌃⌥P should be free in the test process")
        hotKey.unregister()
        XCTAssertFalse(hotKey.isRegistered)
    }

    func testRegisteringTwiceKeepsOneShortcut() {
        let hotKey = GlobalHotKey()
        hotKey.register {}
        hotKey.register {}
        XCTAssertTrue(hotKey.isRegistered)
        hotKey.unregister()
    }

    func testStartAtLoginIsOnlyDefaultedForAnInstalledApp() {
        // The test runner is not /Applications/Pace.app, so nothing may be registered.
        let settings = Settings(defaults: scratchDefaults())
        settings.applyFirstRunDefaults()
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testShortcutIsOnByDefault() {
        XCTAssertTrue(Settings(defaults: scratchDefaults()).hotKeyEnabled)
    }
}
