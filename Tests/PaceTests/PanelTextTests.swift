import XCTest
@testable import Pace

final class PanelTextTests: XCTestCase {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }
    let locale = Locale(identifier: "en_US")
    // A fixed moment, so expected strings never depend on when the tests run.
    let now = Date(timeIntervalSince1970: 1790913600)

    func text(session: (Double, TimeInterval?)?, week: (Double, TimeInterval?)?, weekFresh: Bool = false) -> PanelText {
        var s = UsageSnapshot.empty(source: .statusLine, at: now)
        if let session { s.session = LimitWindow(utilization: session.0, resetsAt: session.1.map { now.addingTimeInterval($0) }) }
        if let week { s.week = LimitWindow(utilization: week.0, resetsAt: week.1.map { now.addingTimeInterval($0) }) }
        return PanelText(.init(snapshot: s, now: now, weekFresh: weekFresh, apples: 12, calendar: cal, locale: locale))
    }

    func row(_ t: PanelText, _ id: String) -> PanelText.Row? { t.rows.first { $0.id == id } }

    func testNormal() {
        let t = text(session: (62, 8048), week: (41, 405_720))
        XCTAssertEqual(t.state, .normal)
        XCTAssertEqual(t.heroTitle, "Session")
        XCTAssertEqual(t.used, 62)
        XCTAssertEqual(t.usedCaption, "used")
        XCTAssertEqual(t.timer, "2h 15m")
        XCTAssertTrue(t.timerCaption.hasPrefix("until "), t.timerCaption)
        XCTAssertFalse(t.timerAccent)
        XCTAssertEqual(row(t, "week")?.value, "41% used")
    }

    func testFreshSession() {
        let t = text(session: (0, nil), week: (41, 405_720))
        XCTAssertEqual(t.timer, "5h")
        XCTAssertEqual(t.used, 0)
        XCTAssertEqual(t.timerCaption, "starts with your next message")
        XCTAssertNil(t.timerTarget)
    }

    func testSessionLimit() {
        let t = text(session: (100, 4320), week: (41, 405_720))
        XCTAssertEqual(t.state, .sessionLimit)
        XCTAssertEqual(t.used, 100)
        XCTAssertEqual(t.timer, "1h 12m")
        XCTAssertTrue(t.timerCaption.hasPrefix("back at "), t.timerCaption)
        XCTAssertTrue(t.timerAccent)
        XCTAssertEqual(t.outlook, "+1 apple · about 1.5M tokens this session")
        XCTAssertEqual(t.outlookTone, .reward)
    }

    func testSessionLimitWithoutAnAwardedAppleSaysNothingExtra() {
        var s = UsageSnapshot.empty(source: .statusLine, at: now)
        s.session = LimitWindow(utilization: 100, resetsAt: now.addingTimeInterval(4320))
        let t = PanelText(.init(snapshot: s, now: now, harvested: false, calendar: cal, locale: locale))
        XCTAssertNil(t.outlook)
    }

    func testWeeklyLimit() {
        let t = text(session: (30, 4320), week: (100, 405_720))
        XCTAssertEqual(t.state, .weeklyLimit)
        XCTAssertEqual(t.heroTitle, "Week")
        XCTAssertEqual(t.used, 100)
        XCTAssertEqual(t.timer, "4d 16h")
        XCTAssertTrue(t.timerCaption.hasPrefix("back "), t.timerCaption)
        XCTAssertEqual(t.outlookTone, .warning)
        XCTAssertEqual(row(t, "session")?.value, "Paused")
        XCTAssertNil(row(t, "week"))
    }

    func testWeeklyLimitCopyDependsOnCredits() {
        var s = UsageSnapshot.empty(source: .oauth, at: now)
        s.week = LimitWindow(utilization: 100, resetsAt: now.addingTimeInterval(86400))
        s.credits = Credits(isEnabled: true, used: 3, monthlyLimit: 50, utilization: 6)
        let on = PanelText(.init(snapshot: s, now: now, calendar: cal, locale: locale))
        XCTAssertTrue(on.outlook?.contains("Your credits keep you going") == true)
        s.credits?.isEnabled = false
        let off = PanelText(.init(snapshot: s, now: now, calendar: cal, locale: locale))
        XCTAssertTrue(off.outlook?.contains("if you turn them on") == true)
    }

    func testFreshWeek() {
        let t = text(session: (0, nil), week: (0, 7 * 86400), weekFresh: true)
        XCTAssertEqual(row(t, "week")?.detail, "fresh week")
    }

    func testLapsedWeekSaysNewWeek() {
        let t = text(session: (10, 3600), week: (70, -60))
        XCTAssertEqual(row(t, "week")?.value, "0% used")
        XCTAssertEqual(row(t, "week")?.detail, "new week")
    }

    func testRowsForModelLimitsAndCredits() {
        var s = UsageSnapshot.empty(source: .oauth, at: now)
        s.session = LimitWindow(utilization: 10, resetsAt: now.addingTimeInterval(3600))
        s.week = LimitWindow(utilization: 20, resetsAt: now.addingTimeInterval(3 * 86400))
        s.scoped = [ScopedLimit(name: "Fable weekly", utilization: 23, resetsAt: nil)]
        s.credits = Credits(isEnabled: false, used: 0, monthlyLimit: nil, utilization: 0)
        let t = PanelText(.init(snapshot: s, now: now, calendar: cal, locale: locale))
        XCTAssertEqual(t.rows.map(\.id), ["week", "scoped-Fable weekly", "credits"])
        XCTAssertEqual(row(t, "scoped-Fable weekly")?.value, "23% used")
        XCTAssertEqual(row(t, "credits")?.value, "Off")
        XCTAssertNil(row(t, "credits")?.used)
        s.credits = Credits(isEnabled: true, used: 12.4, monthlyLimit: 50, utilization: 24.8, currency: "USD")
        let on = PanelText(.init(snapshot: s, now: now, calendar: cal, locale: locale))
        XCTAssertEqual(row(on, "credits")?.value, "$12.40 of $50")
    }

    func testMenuBarText() {
        XCTAssertEqual(PanelText.menuBarText(text(session: (62, 8048), week: (41, 405_720)), now: now), "2h 15m")
        XCTAssertEqual(PanelText.menuBarText(text(session: (30, 4320), week: (100, 405_720)), now: now), "4d 16h")
        XCTAssertNil(PanelText.menuBarText(text(session: (0, nil), week: (41, 405_720)), now: now))
    }

    func testNoDashesInCopy() {
        for t in [text(session: (62, 8048), week: (41, 405_720)),
                  text(session: (100, 4320), week: (41, 405_720)),
                  text(session: (30, 4320), week: (100, 405_720)),
                  text(session: (50, 4 * 3600), week: (40, 6 * 86400)),
                  text(session: (0, nil), week: (0, 7 * 86400), weekFresh: true)] {
            var strings = [t.heroTitle, t.usedCaption, t.timerCaption, t.outlook ?? ""]
            for r in t.rows { strings += [r.name, r.detail ?? "", r.value, r.definer] }
            for s in strings {
                XCTAssertFalse(s.contains("\u{2014}") || s.contains("\u{2013}"), "dash in copy: \(s)")
            }
            for name in [t.usedName, t.timerName] + t.rows.map(\.definer) {
                XCTAssertLessThanOrEqual(name.split(separator: " ").count, 2, "hover label longer than two words: \(name)")
            }
        }
    }

    // MARK: Pace forecast

    func testOnPaceWhenUsageTracksTime() {
        let t = text(session: (30, 3 * 3600), week: (41, 405_720))
        XCTAssertEqual(t.outlook, "On pace to last until the reset")
        XCTAssertEqual(t.outlookTone, .muted)
    }

    func testRunsOutWhenUsageOutpacesTime() {
        let t = text(session: (50, 4 * 3600), week: (41, 405_720))
        XCTAssertTrue(t.outlook?.hasPrefix("At this pace, it runs out around ") == true, t.outlook ?? "nil")
        XCTAssertEqual(t.outlookTone, .warning)
        let out = PanelText.runsOut(used: 50, resetsAt: now.addingTimeInterval(4 * 3600), length: PanelText.sessionLength, now: now)
        XCTAssertEqual(out?.timeIntervalSince(now) ?? 0, 3600, accuracy: 1)
    }

    func testNoForecastTooEarlyInTheWindow() {
        let t = text(session: (20, 5 * 3600 - 600), week: (41, 405_720))
        XCTAssertNil(t.outlook)
        XCTAssertEqual(t.used, 20)
    }

    func testWeekOnPace() {
        let t = text(session: (10, 3 * 3600), week: (40, 4 * 86400))
        XCTAssertTrue(row(t, "week")?.detail?.hasPrefix("resets ") == true)
        XCTAssertEqual(row(t, "week")?.valueTone, .normal)
    }

    func testWeekForecast() {
        let t = text(session: (10, 3 * 3600), week: (40, 6 * 86400))
        XCTAssertTrue(row(t, "week")?.detail?.hasPrefix("runs out ") == true, row(t, "week")?.detail ?? "nil")
        XCTAssertEqual(row(t, "week")?.valueTone, .warning)
    }

    func testNeverShowsFullBelowTheLimit() {
        let t = text(session: (99.7, 3 * 3600), week: (99.6, 405_720))
        XCTAssertEqual(t.used, 99)
        XCTAssertEqual(row(t, "week")?.value, "99% used")
    }

    // MARK: Hover detail

    func testWeekRowShowsItsResetWithACountdown() {
        let t = text(session: (10, 3 * 3600), week: (40, 4 * 86400))
        XCTAssertEqual(row(t, "week")?.detail?.hasSuffix("in 4d"), true, row(t, "week")?.detail ?? "nil")
        XCTAssertEqual(row(t, "week")?.detailTone, .normal)
    }

    func testOpenRowsAddAnalysisNotRepeats() {
        var s = UsageSnapshot.empty(source: .oauth, at: now)
        s.session = LimitWindow(utilization: 10, resetsAt: now.addingTimeInterval(3 * 3600))
        s.week = LimitWindow(utilization: 40, resetsAt: now.addingTimeInterval(4 * 86400))
        s.scoped = [ScopedLimit(name: "Fable weekly", utilization: 100, resetsAt: now.addingTimeInterval(86400))]
        s.credits = Credits(isEnabled: true, used: 12.4, monthlyLimit: 50, utilization: 24.8, currency: "USD")
        let t = PanelText(.init(snapshot: s, now: now, calendar: cal, locale: locale))
        let week = row(t, "week")!
        XCTAssertEqual(week.marker ?? 0, 3.0 / 7 * 100, accuracy: 0.5, "even pace tick after 3 of 7 days")
        XCTAssertTrue(week.lines.contains { $0.text.hasPrefix("Day 4 of 7.") }, "\(week.lines)")
        XCTAssertTrue(week.lines.contains { $0.text.contains("% a day keeps you under the limit") })
        XCTAssertTrue(row(t, "scoped-Fable weekly")!.lines.contains { $0.text == "Other models still work." })
        XCTAssertEqual(row(t, "credits")?.lines.first?.text, "Spent this month. $37.60 left before the cap.")
    }

    /// The open part of a row must add information, never repeat the row.
    func testOpenRowsNeverRepeatTheCollapsedLine() {
        let cases = [text(session: (62, 8048), week: (41, 405_720)),
                     text(session: (10, 3 * 3600), week: (40, 6 * 86400)),      // week running out
                     text(session: (30, 4320), week: (100, 405_720)),
                     text(session: (0, nil), week: (0, 7 * 86400), weekFresh: true)]
        for t in cases {
            for r in t.rows {
                for line in r.lines {
                    if let detail = r.detail {
                        XCTAssertFalse(line.text.lowercased().contains(detail.lowercased()), "\(r.id): \"\(line.text)\" repeats \"\(detail)\"")
                    }
                    XCTAssertFalse(line.text.contains(r.value), "\(r.id): \"\(line.text)\" repeats \"\(r.value)\"")
                }
            }
        }
    }

    /// No seconds anywhere: they tick every second and pull attention.
    func testNoSecondsAnywhere() {
        let seconds = try! NSRegularExpression(pattern: #"\d:\d\d:\d\d|\d+s\b"#)
        let cases = [text(session: (62, 8048), week: (41, 405_720)),
                     text(session: (100, 59), week: (41, 405_720)),
                     text(session: (30, 4320), week: (100, 405_720)),
                     text(session: (0, nil), week: (0, 7 * 86400))]
        for t in cases {
            var strings = [t.timer, t.timerCaption, t.outlook ?? ""]
            for r in t.rows { strings += [r.detail ?? "", r.value] + r.lines.map(\.text) }
            if let m = PanelText.menuBarText(t, now: now) { strings.append(m) }
            for s in strings {
                XCTAssertNil(seconds.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), "seconds in: \(s)")
            }
        }
    }
}
