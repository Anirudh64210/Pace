import Foundation

/// Where the data pipeline stands. The panel and settings read only this, so
/// every screen agrees on what is happening.
enum SyncStatus: Equatable {
    /// Nothing tried yet.
    case idle
    /// A fetch is in flight and there is nothing on screen yet.
    case connecting
    /// Last fetch worked.
    case live
    /// Nothing is wrong, the source just has nothing yet (setup pending, no message sent).
    case waiting(String)
    /// Last fetch failed. `retryAt` is nil when retrying on a timer cannot help.
    case failed(String, retryAt: Date?)

    var message: String? {
        switch self {
        case .waiting(let m), .failed(let m, _): return m
        default: return nil
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

/// Poll timing, kept pure so it can be tested.
enum SyncPolicy {
    /// Normal cadence per source. `urgent` means a limit is above 90% or a reset is within 10 minutes.
    static func interval(for source: UsageSource, urgent: Bool) -> TimeInterval {
        switch source {
        case .statusLine: return urgent ? 5 : 15        // a local file read
        case .oauth: return urgent ? 60 : 300           // docs/DESIGN.md section 8
        case .demo: return 12
        }
    }

    /// Delay before the next attempt after `failures` consecutive failures.
    /// Doubles from the normal cadence, capped at 30 minutes, and honours Retry-After.
    static func backoff(for source: UsageSource, failures: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let base = max(60, interval(for: source, urgent: false))
        let exp = base * pow(2, Double(max(0, failures - 1)))
        return min(1800, max(exp, retryAfter ?? 0))
    }

    /// Offline is usually brief (wake from sleep, Wi-Fi switch). Retry soon, without escalating.
    static let offlineRetry: TimeInterval = 30
    /// How often an expired or missing sign-in is re-checked. Local only (the
    /// Keychain and the credentials file), no network, so it can be frequent:
    /// Pace picks up a renewed sign-in within a minute.
    static let signInRecheck: TimeInterval = 60

    /// Opening the panel refreshes only if the last attempt is older than this.
    static func openRefreshAge(for source: UsageSource) -> TimeInterval {
        source == .oauth ? 60 : 3
    }

    static func isUrgent(_ snapshot: UsageSnapshot?, now: Date) -> Bool {
        guard let s = snapshot?.normalized(now: now) else { return false }
        for w in [s.session, s.week].compactMap({ $0 }) {
            if w.utilization > 90 { return true }
            if let r = w.resetsAt, r > now, r.timeIntervalSince(now) < 600 { return true }
        }
        return false
    }
}
