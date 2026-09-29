import XCTest
@testable import Pace

@MainActor
final class PanelPositionTests: XCTestCase {
    /// The countdown text beside the apple changes the icon's width. The panel
    /// must open in exactly the same place regardless (it used to slide sideways).
    func testPanelPositionIgnoresTheIconsWidth() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let rightEdge: CGFloat = 1320
        let frames = [18.0, 48.0, 72.0, 96.0].map { width in
            StatusItemController.windowFrame(icon: NSRect(x: rightEdge - width, y: 920, width: width, height: 24), visible: screen)
        }
        XCTAssertEqual(Set(frames.map { $0.origin.x }).count, 1, "\(frames)")
        XCTAssertEqual(Set(frames.map { $0.origin.y }).count, 1)
    }

    func testPillStaysOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let f = PillController.frame(icon: NSRect(x: 1495, y: 920, width: 17, height: 24), visible: screen)
        XCTAssertLessThanOrEqual(f.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(f.minX, screen.minX)
        XCTAssertLessThan(f.maxY, 920)
    }
}

@MainActor
final class SourceSwitchTests: XCTestCase {
    func snap(_ used: Double, resetsIn: TimeInterval) -> UsageSnapshot {
        var s = UsageSnapshot.empty(source: .oauth)
        s.session = LimitWindow(utilization: used, resetsAt: Date().addingTimeInterval(resetsIn))
        s.week = LimitWindow(utilization: 30, resetsAt: Date().addingTimeInterval(3 * 86400))
        return s
    }

    func testNumbersStayOnScreenWhileTheNewSourceConnects() async throws {
        let settings = Settings(defaults: scratchDefaults())
        let first = StubProvider(kind: .statusLine, [.success(snap(40, resetsIn: 3600))])
        let app = AppState(settings: settings, autoPoll: false, provider: first)
        await app.refresh()
        XCTAssertNotNil(app.snapshot)
        settings.source = .oauth
        try await Task.sleep(nanoseconds: 500_000_000)       // past the switch debounce
        XCTAssertNotNil(app.snapshot, "the old numbers stay until the new source answers")
        XCTAssertNotEqual(app.status, .connecting)
    }
}

@MainActor
final class AnnounceTests: XCTestCase {
    func makeApp() -> (AppState, Settings) {
        let settings = Settings(defaults: scratchDefaults())
        let app = AppState(settings: settings, autoPoll: false, provider: StubProvider([.failure(ProviderError.offline)]))
        return (app, settings)
    }

    let alert = StatusAlert(title: "Session back", detail: "a fresh 5 hours", kind: .good)

    func testClosedPanelGetsThePill() {
        let (app, _) = makeApp()
        app.isPanelVisible = false
        app.announce(alert)
        XCTAssertEqual(app.pill, alert)
        XCTAssertNil(app.toast)
    }

    func testOpenPanelShowsItInside() {
        let (app, _) = makeApp()
        app.isPanelVisible = true
        app.announce(alert)
        XCTAssertNil(app.pill)
        XCTAssertEqual(app.toast?.title, "Session back")
    }

    func testPillCanBeTurnedOff() {
        let (app, settings) = makeApp()
        settings.showPill = false
        app.announce(alert)
        XCTAssertNil(app.pill)
    }

    func testDefaults() {
        let settings = Settings(defaults: scratchDefaults())
        XCTAssertTrue(settings.showPill)
        XCTAssertFalse(settings.notificationsEnabled, "the pill is the default; notifications are an extra")
    }
}

final class StatusEventTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func snap(session: Double, week: Double) -> UsageSnapshot {
        var s = UsageSnapshot.empty(source: .oauth, at: now)
        s.session = LimitWindow(utilization: session, resetsAt: now.addingTimeInterval(3600))
        s.week = LimitWindow(utilization: week, resetsAt: now.addingTimeInterval(86400))
        return s
    }

    func testWeeklyLimitHit() {
        XCTAssertEqual(StateMachine.events(from: snap(session: 20, week: 99), to: snap(session: 20, week: 100), now: now), [.weeklyLimitHit])
    }

    func testWeeklyLimitAndPaceWarningAreGatedPerWindow() {
        var gate = EventGate()
        let key = now.addingTimeInterval(86400)
        XCTAssertTrue(gate.admit(.weeklyLimitHit, key: key, now: now))
        XCTAssertFalse(gate.admit(.weeklyLimitHit, key: key, now: now.addingTimeInterval(600)))
        XCTAssertTrue(gate.admit(.paceWarning, key: key, now: now))
        XCTAssertFalse(gate.admit(.paceWarning, key: key, now: now.addingTimeInterval(60)))
    }

    func testOldSavedGateStillDecodes() throws {
        let old = #"{"sessionReset":{"key":800000000,"at":800000000}}"#
        let gate = try JSONDecoder().decode(EventGate.self, from: Data(old.utf8))
        XCTAssertNotNil(gate.sessionReset)
        XCTAssertNil(gate.weeklyLimit)
    }

    func testAlertCopyIsShortAndClean() {
        var s = snap(session: 60, week: 100)
        s.session = LimitWindow(utilization: 60, resetsAt: now.addingTimeInterval(3 * 3600))
        for event in [PaceEvent.sessionReset, .weeklyReset, .sessionLimitHit, .weeklyLimitHit, .paceWarning] {
            let a = StatusAlert.make(event, snapshot: s, now: now)
            XCTAssertFalse(a.title.isEmpty)
            XCTAssertLessThanOrEqual((a.title + a.detail).count, 40, "\(event): \(a.title) \(a.detail)")
            XCTAssertFalse((a.title + a.detail).contains("\u{2014}") || (a.title + a.detail).contains("\u{2013}"))
        }
    }
}
