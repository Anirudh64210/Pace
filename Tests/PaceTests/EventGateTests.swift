import XCTest
@testable import Pace

final class EventGateTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ t: TimeInterval) -> Date { now.addingTimeInterval(t) }

    func testSameWindowAdmitsOnce() {
        var g = EventGate()
        XCTAssertTrue(g.admit(.sessionReset, key: at(0), now: now))
        XCTAssertFalse(g.admit(.sessionReset, key: at(0), now: at(15)))
        XCTAssertFalse(g.admit(.sessionReset, key: at(0), now: at(7200)))
    }

    func testOlderWindowNeverAdmits() {
        var g = EventGate()
        XCTAssertTrue(g.admit(.sessionReset, key: at(18000), now: now))
        XCTAssertFalse(g.admit(.sessionReset, key: at(3600), now: at(30)))
    }

    func testNewerWindowAdmits() {
        var g = EventGate()
        XCTAssertTrue(g.admit(.sessionReset, key: at(0), now: now))
        XCTAssertTrue(g.admit(.sessionReset, key: at(18000), now: at(18000)))
    }

    func testNoKeyUsesTimeGap() {
        var g = EventGate()
        XCTAssertTrue(g.admit(.sessionReset, key: nil, now: now))
        XCTAssertFalse(g.admit(.sessionReset, key: nil, now: at(600)))
        XCTAssertTrue(g.admit(.sessionReset, key: nil, now: at(3601)))
    }

    func testEventsAreIndependent() {
        var g = EventGate()
        XCTAssertTrue(g.admit(.sessionReset, key: at(0), now: now))
        XCTAssertTrue(g.admit(.weeklyReset, key: at(0), now: now))
        XCTAssertTrue(g.admit(.sessionLimitHit, key: at(0), now: now))
        XCTAssertFalse(g.admit(.sessionLimitHit, key: at(0), now: at(5)))
    }

    func testClockThenDataForTheSameResetNotifiesOnce() {
        // The clock sees the window end at T; later the data shows the same ended window.
        var g = EventGate()
        XCTAssertTrue(g.admit(.sessionReset, key: at(0), now: at(1)))
        XCTAssertFalse(g.admit(.sessionReset, key: at(0), now: at(3600)))
    }

    func testRoundTripsThroughJSON() throws {
        var g = EventGate()
        _ = g.admit(.sessionReset, key: at(18000), now: now)
        let data = try JSONEncoder().encode(g)
        XCTAssertEqual(try JSONDecoder().decode(EventGate.self, from: data), g)
    }
}
