import Foundation

/// Lets each reward or reset event through once per limit window.
///
/// Data sources can flap: several Claude Code sessions write the same status
/// file, a poll can return an older snapshot, a window can vanish and come back.
/// The state machine reports every flip; this gate makes sure the user hears
/// about each real reset once.
struct EventGate: Codable, Equatable {
    struct Mark: Codable, Equatable {
        var key: Date?     // the window's reset time that triggered the event
        var at: Date       // when we let it through
    }

    var sessionReset: Mark?
    var weeklyReset: Mark?
    var harvest: Mark?
    var weeklyLimit: Mark?
    var paceWarning: Mark?

    /// Minimum spacing when the window has no reset time to key on.
    static let sessionGap: TimeInterval = 3600
    static let weeklyGap: TimeInterval = 86400
    static let harvestGap: TimeInterval = 3600

    /// Returns true if the event should be acted on, and records it.
    ///
    /// `key` identifies the limit window the event belongs to: for a reset, the
    /// reset time of the window that just ended; for a harvest, the reset time of
    /// the window that hit its limit. The same window never passes twice, whether
    /// the event came from new data or from the clock.
    mutating func admit(_ event: PaceEvent, key: Date?, now: Date) -> Bool {
        switch event {
        case .sessionReset: return Self.admit(&sessionReset, key: key, gap: Self.sessionGap, now: now)
        case .weeklyReset: return Self.admit(&weeklyReset, key: key, gap: Self.weeklyGap, now: now)
        case .sessionLimitHit: return Self.admit(&harvest, key: key, gap: Self.harvestGap, now: now)
        case .weeklyLimitHit: return Self.admit(&weeklyLimit, key: key, gap: Self.weeklyGap, now: now)
        case .paceWarning: return Self.admit(&paceWarning, key: key, gap: Self.sessionGap, now: now)
        }
    }

    private static func admit(_ mark: inout Mark?, key: Date?, gap: TimeInterval, now: Date) -> Bool {
        if let key {
            // A keyed event repeats only for a strictly newer window.
            if let last = mark, let lastKey = last.key, key <= lastKey.addingTimeInterval(60) { return false }
            if let last = mark, last.key == nil, now.timeIntervalSince(last.at) < gap { return false }
        } else {
            if let last = mark, now.timeIntervalSince(last.at) < gap { return false }
        }
        mark = Mark(key: key, at: now)
        return true
    }
}
