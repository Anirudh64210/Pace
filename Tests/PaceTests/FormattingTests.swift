import XCTest
@testable import Pace

final class FormattingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testShortCountdown() {
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(8048), now: now), "2h 15m", "rounds up")
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(59 * 60), now: now), "59m")
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(405_715), now: now), "4d 16h")
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(20), now: now), "1m", "no seconds")
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(5 * 3600), now: now), "5h")
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(2 * 86400), now: now), "2d")
        XCTAssertEqual(Formatting.shortCountdown(to: now.addingTimeInterval(-5), now: now), "0m")
    }

    func testTokens() {
        XCTAssertEqual(Formatting.tokens(18_000_000), "18M")
        XCTAssertEqual(Formatting.tokens(1_500_000), "1.5M")
        XCTAssertEqual(Formatting.tokens(240_000), "240K")
        XCTAssertEqual(Formatting.tokens(900), "900")
    }

    func testMoney() {
        XCTAssertEqual(Formatting.money(12.4), "$12.40")
        XCTAssertEqual(Formatting.money(50), "$50")
    }

    func testWeekdayFormats() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let loc = Locale(identifier: "en_US")
        // 2026-10-08 21:00 PDT
        let d = Date(timeIntervalSince1970: 1791518400)
        let s = Formatting.weekdayDateHour(d, calendar: cal, locale: loc)
        XCTAssertTrue(s.hasPrefix("Thu"), s)
        XCTAssertEqual(s, "Thu Oct 8, 9 PM")
        XCTAssertTrue(s.hasSuffix("9 PM"), s)
        XCTAssertEqual(Formatting.weekdayHour(d, calendar: cal, locale: loc), "Thu 9 PM")
        XCTAssertEqual(Formatting.weekdayHour(d.addingTimeInterval(1800), calendar: cal, locale: loc), "Thu 9:30 PM")
        XCTAssertEqual(Formatting.clockTime(d, calendar: cal, locale: loc), "9:00 PM")
    }

    func testRelativeAge() {
        XCTAssertEqual(Formatting.relativeAge(of: now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(Formatting.relativeAge(of: now.addingTimeInterval(-600), now: now), "10 min ago")
        XCTAssertEqual(Formatting.relativeAge(of: now.addingTimeInterval(-7200), now: now), "2 h ago")
    }
}
