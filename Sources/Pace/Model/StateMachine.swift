import Foundation

/// Events raised when two consecutive snapshots differ in a meaningful way.
enum PaceEvent: Equatable {
    case sessionReset
    case weeklyReset
    case sessionLimitHit
    case weeklyLimitHit
    /// The session's pace forecast just turned into a warning. Raised by AppState.
    case paceWarning
}

/// Compares the previous snapshot with the current one and reports transitions.
/// Pure, so it is easy to unit test with fixtures.
enum StateMachine {
    /// A window "moved forward" when its reset time advanced by at least this much.
    static let sessionForwardThreshold: TimeInterval = 60
    /// Weekly windows are long. A new reset time at least this far ahead is a new week.
    static let weeklyForwardThreshold: TimeInterval = 12 * 3600

    static func events(from previous: UsageSnapshot?, to current: UsageSnapshot, now: Date = Date()) -> [PaceEvent] {
        guard let previous else { return [] }
        var events: [PaceEvent] = []

        if let prev = previous.session, let cur = current.session {
            if prev.utilization < 100, cur.utilization >= 100 {
                events.append(.sessionLimitHit)
            }
            if didReset(prev, cur, forwardThreshold: sessionForwardThreshold, now: now) {
                events.append(.sessionReset)
            }
        } else if let prev = previous.session, current.session == nil {
            // Claude Code drops a window once its reset time passes.
            if let resetsAt = prev.resetsAt, resetsAt <= now, prev.utilization > 0 {
                events.append(.sessionReset)
            }
        }

        if let prev = previous.week, let cur = current.week {
            if prev.utilization < 100, cur.utilization >= 100 {
                events.append(.weeklyLimitHit)
            }
            if didReset(prev, cur, forwardThreshold: weeklyForwardThreshold, now: now) {
                events.append(.weeklyReset)
            }
        }
        return events
    }

    /// True when the reset time moved forward and usage dropped, or when the
    /// previous reset time has passed and usage dropped sharply.
    private static func didReset(_ prev: LimitWindow, _ cur: LimitWindow, forwardThreshold: TimeInterval, now: Date) -> Bool {
        let dropped = cur.utilization < prev.utilization
        guard dropped else { return false }
        // The window vanished (no reset time, nothing used): a fresh window.
        if cur.resetsAt == nil, cur.utilization <= 0, prev.utilization > 0 { return true }
        if let p = prev.resetsAt, let c = cur.resetsAt {
            if c.timeIntervalSince(p) >= forwardThreshold { return true }
            if p <= now, c > now { return true }
            return false
        }
        // No timestamps to compare: only trust a big drop from a high level.
        return prev.utilization >= 50 && prev.utilization - cur.utilization >= 50
    }
}
