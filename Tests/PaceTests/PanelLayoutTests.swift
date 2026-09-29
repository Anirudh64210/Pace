import XCTest
import SwiftUI
@testable import Pace

/// The panel sits in a fixed window and animates its own height. These tests
/// pin down the rules that keep it from glitching:
/// - its height never depends on the window,
/// - hovering never changes its size (so nothing moves under the pointer),
/// - every state, with any row open, fits in the window,
/// - the window's position depends only on the icon and the screen.
@MainActor
final class PanelLayoutTests: XCTestCase {
    func makeApp(demo: Bool) -> AppState {
        AppState(settings: Settings(defaults: scratchDefaults()), demo: demo, autoPoll: false)
    }

    func size(_ app: AppState, hover: Bool = false, proposal: CGSize = CGSize(width: Theme.panelWidth, height: 10_000)) -> CGSize {
        let view = PanelView().environmentObject(app).environment(\.forcedHover, hover)
        return NSHostingController(rootView: view).sizeThatFits(in: proposal)
    }

    func assertStable(_ app: AppState, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let reference = size(app)
        XCTAssertEqual(reference.width, Theme.panelWidth, label, file: file, line: line)
        XCTAssertLessThanOrEqual(reference.height, Theme.panelHeight, "\(label) must fit the window", file: file, line: line)
        for proposal in [CGSize(width: 10, height: 10), CGSize(width: 2000, height: 2000), CGSize(width: 360, height: 100)] {
            XCTAssertEqual(size(app, proposal: proposal), reference, "\(label) at \(proposal)", file: file, line: line)
        }
        XCTAssertEqual(size(app, hover: true), reference, "\(label): hover must not change the size", file: file, line: line)
    }

    func testOnboarding() {
        assertStable(makeApp(demo: false), "onboarding")
    }

    /// Every demo state, closed and with each row open, and Settings.
    func testEveryStateAndEveryOpenRowFitsAndIsStable() async {
        let app = makeApp(demo: true)
        for step in 0..<6 {
            await app.refresh()
            assertStable(app, "state \(step)")
            let ids = (app.panelText?.rows.map(\.id) ?? []) + ["breakdown"]
            for id in ids {
                app.settings.openRows = [id]
                assertStable(app, "state \(step), \(id) open")
            }
            app.settings.openRows = Set(ids)
            assertStable(app, "state \(step), every row open at once")
            app.settings.openRows = []
        }
        app.showSettings = true
        assertStable(app, "settings")
        app.settings.source = .oauth
        assertStable(app, "settings, sign-in source")
    }

    func testOpeningARowGrowsThePanelAndClosingRestoresIt() async {
        let app = makeApp(demo: true)
        await app.refresh()
        let closed = size(app)
        app.toggleRow("week")
        XCTAssertGreaterThan(size(app).height, closed.height)
        app.toggleRow("week")
        XCTAssertEqual(size(app), closed)
    }

    func testWindowPositionIgnoresContentAndStaysOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let icon = NSRect(x: 1300, y: 944, width: 60, height: 24)
        let f = StatusItemController.windowFrame(icon: icon, visible: screen)
        XCTAssertEqual(f.size, StatusItemController.windowSize)
        // The panel's top edge sits 6 pt under the icon.
        XCTAssertEqual(f.maxY, icon.minY - 6)
        // The panel stays 8 pt inside the screen at the right edge.
        let farRight = StatusItemController.windowFrame(icon: NSRect(x: 1500, y: 944, width: 20, height: 24), visible: screen)
        XCTAssertLessThanOrEqual(farRight.minX + Theme.windowMargin + Theme.panelWidth, screen.maxX - 8)
        // Same inputs, same frame: nothing about the panel's content is involved.
        XCTAssertEqual(StatusItemController.windowFrame(icon: icon, visible: screen), f)
    }

    func testMenuBarImageIsReusedForTheSameFill() {
        XCTAssertTrue(AppleImage.menuBar(fill: 0.62) === AppleImage.menuBar(fill: 0.62))
        XCTAssertTrue(AppleImage.menuBar(fill: 0.62) === AppleImage.menuBar(fill: 0.61))
    }
}

@MainActor
final class RowOpeningTests: XCTestCase {
    func makeApp() -> AppState {
        AppState(settings: Settings(defaults: scratchDefaults()), demo: true, autoPoll: false)
    }

    func testClickOpensAndClickAgainCloses() {
        let app = makeApp()
        app.toggleRow("week")
        XCTAssertTrue(app.isOpen("week"))
        app.toggleRow("week")
        XCTAssertFalse(app.isOpen("week"))
    }

    /// Several rows can be open at once, to compare them.
    func testRowsOpenIndependently() {
        let app = makeApp()
        app.toggleRow("week")
        app.toggleRow("credits")
        XCTAssertTrue(app.isOpen("week"))
        XCTAssertTrue(app.isOpen("credits"))
    }

    /// Open rows are remembered across panel openings and app launches.
    func testOpenRowsAreRemembered() {
        let defaults = scratchDefaults()
        let app = AppState(settings: Settings(defaults: defaults), demo: true, autoPoll: false)
        app.toggleRow("week")
        app.showSettings = true
        app.panelDidClose()
        XCTAssertTrue(app.isOpen("week"))
        XCTAssertFalse(app.showSettings)
        XCTAssertTrue(Settings(defaults: defaults).openRows.contains("week"))
    }

    /// 2,000 random clicks: every row's state always matches a simple model.
    func testRandomClickStorm() {
        let app = makeApp()
        let ids = ["week", "scoped-Fable weekly", "credits", "breakdown"]
        var model = Set<String>()
        for _ in 0..<2000 {
            let id = ids.randomElement()!
            app.toggleRow(id)
            if model.contains(id) { model.remove(id) } else { model.insert(id) }
            XCTAssertEqual(app.settings.openRows, model)
        }
    }
}

@MainActor
final class PanelLayoutUnseenDotTests: XCTestCase {
    /// The unseen "+1" dot once triggered an endless slide-in.
    func testPanelWithUnseenDotIsStable() {
        let settings = Settings(defaults: scratchDefaults())
        settings.unseenApple = true
        let app = AppState(settings: settings, demo: false, autoPoll: false)
        let controller = NSHostingController(rootView: PanelView().environmentObject(app))
        XCTAssertEqual(controller.sizeThatFits(in: CGSize(width: 360, height: 100)),
                       controller.sizeThatFits(in: CGSize(width: 360, height: 5000)))
    }
}
