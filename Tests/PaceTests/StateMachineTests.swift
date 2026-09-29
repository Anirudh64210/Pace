import XCTest
@testable import Pace

final class StateMachineTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func snap(session: (Double, TimeInterval?)?, week: (Double, TimeInterval?)?) -> UsageSnapshot {
        var s = UsageSnapshot.empty(source: .statusLine, at: now)
        if let session { s.session = LimitWindow(utilization: session.0, resetsAt: session.1.map { now.addingTimeInterval($0) }) }
        if let week { s.week = LimitWindow(utilization: week.0, resetsAt: week.1.map { now.addingTimeInterval($0) }) }
        return s
    }

    func testNoPreviousSnapshotYieldsNoEvents() {
        XCTAssertEqual(StateMachine.events(from: nil, to: snap(session: (50, 3600), week: (10, 86400)), now: now), [])
    }

    func testSessionLimitHit() {
        let a = snap(session: (95, 3600), week: (40, 86400))
        let b = snap(session: (100, 3600), week: (41, 86400))
        XCTAssertEqual(StateMachine.events(from: a, to: b, now: now), [.sessionLimitHit])
    }

    func testSessionResetWhenResetTimeMovesForwardAndUsageDrops() {
        let a = snap(session: (100, 60), week: (40, 86400))
        let b = snap(session: (3, 5 * 3600), week: (40, 86400))
        XCTAssertEqual(StateMachine.events(from: a, to: b, now: now), [.sessionReset])
    }

    func testSessionResetWhenWindowDroppedAfterExpiry() {
        let a = snap(session: (80, -30), week: (40, 86400))
        let b = snap(session: nil, week: (40, 86400))
        XCTAssertEqual(StateMachine.events(from: a, to: b, now: now), [.sessionReset])
    }

    func testNoSessionResetWhenUsageJustFluctuates() {
        let a = snap(session: (50, 3600), week: (40, 86400))
        let b = snap(session: (48, 3600), week: (40, 86400))
        XCTAssertEqual(StateMachine.events(from: a, to: b, now: now), [])
    }

    func testWeeklyReset() {
        let a = snap(session: (30, 3600), week: (100, 120))
        let b = snap(session: (0, nil), week: (0, 7 * 86400))
        let events = StateMachine.events(from: a, to: b, now: now)
        XCTAssertTrue(events.contains(.weeklyReset))
        XCTAssertTrue(events.contains(.sessionReset))
    }

    func testWeeklyResetIgnoresSmallForwardDrift() {
        let a = snap(session: (30, 3600), week: (60, 86400))
        let b = snap(session: (30, 3600), week: (59, 86400 + 120))
        XCTAssertEqual(StateMachine.events(from: a, to: b, now: now), [])
    }

    // MARK: - PaceState (one per row of HANDOFF section 4)

    func testStateNormal() {
        XCTAssertEqual(PaceState.derive(from: snap(session: (62, 8048), week: (41, 405_720)), now: now), .normal)
    }

    func testStateFreshSession() {
        XCTAssertEqual(PaceState.derive(from: snap(session: (0, nil), week: (41, 405_720)), now: now), .freshSession)
        XCTAssertEqual(PaceState.derive(from: snap(session: nil, week: (41, 405_720)), now: now), .freshSession)
    }

    func testZeroPercentWithAResetTimeIsARunningSession() {
        XCTAssertEqual(PaceState.derive(from: snap(session: (0, 15_840), week: (27, 147_600)), now: now), .normal)
    }

    func testStateFreshSessionWhenStaleWindowExpired() {
        XCTAssertEqual(PaceState.derive(from: snap(session: (80, -10), week: (41, 405_720)), now: now), .freshSession)
    }

    func testStateSessionLimit() {
        XCTAssertEqual(PaceState.derive(from: snap(session: (100, 4320), week: (41, 405_720)), now: now), .sessionLimit)
    }

    func testStateWeeklyLimitWinsOverSession() {
        XCTAssertEqual(PaceState.derive(from: snap(session: (30, 4320), week: (100, 405_720)), now: now), .weeklyLimit)
        XCTAssertEqual(PaceState.derive(from: snap(session: (100, 4320), week: (100, 405_720)), now: now), .weeklyLimit)
    }
}
