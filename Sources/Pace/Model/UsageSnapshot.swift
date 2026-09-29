import Foundation

/// One rate limit window: how much of it is used and when it resets.
struct LimitWindow: Equatable, Codable {
    /// 0...100. Values above 100 are clamped by the display layer, not here.
    var utilization: Double
    var resetsAt: Date?

    var isFull: Bool { utilization >= 100 }
    var isFresh: Bool { utilization <= 0 }
}

/// A weekly limit scoped to one model family (for example "Fable weekly").
struct ScopedLimit: Equatable, Codable, Identifiable {
    var id: String { name }
    var name: String
    var utilization: Double
    var resetsAt: Date?
}

/// Share of this week's usage that came from one product (Claude Code, Chat, Cowork).
struct ProductShare: Equatable, Codable, Identifiable {
    var id: String { key }
    var key: String
    var name: String
    var percent: Double
}

/// Extra usage credits, in whole currency units (dollars), not cents.
struct Credits: Equatable, Codable {
    var isEnabled: Bool
    var used: Double?
    var monthlyLimit: Double?
    var utilization: Double?
    var currency: String? = nil

    var fraction: Double {
        if let utilization { return min(1, max(0, utilization / 100)) }
        if let used, let monthlyLimit, monthlyLimit > 0 { return min(1, max(0, used / monthlyLimit)) }
        return 0
    }
}

enum UsageSource: String, Codable, CaseIterable, Identifiable {
    case statusLine
    case oauth
    case demo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statusLine: return "Claude Code status line"
        case .oauth: return "Claude sign-in (Keychain)"
        case .demo: return "Demo data"
        }
    }
}

/// Everything the UI needs, captured at one moment.
struct UsageSnapshot: Equatable, Codable {
    var session: LimitWindow?
    var week: LimitWindow?
    var scoped: [ScopedLimit] = []
    var credits: Credits?
    /// This week's usage split by product. Only the sign-in source reports it.
    var breakdown: [ProductShare] = []
    var fetchedAt: Date
    var source: UsageSource
    /// Subscription plan when the source knows it ("max", "pro").
    var plan: String?

    static func empty(source: UsageSource, at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(session: nil, week: nil, scoped: [], credits: nil, breakdown: [], fetchedAt: date, source: source)
    }

    var hasData: Bool { session != nil || week != nil }

    /// A window whose reset time has passed is full again, even if the source has
    /// not caught up yet (the status line file only changes while Claude Code runs).
    func normalized(now: Date) -> UsageSnapshot {
        var s = self
        func fresh(_ w: LimitWindow?) -> LimitWindow? {
            guard let w else { return nil }
            if let r = w.resetsAt, r <= now { return LimitWindow(utilization: 0, resetsAt: nil) }
            return w
        }
        s.session = fresh(session)
        s.week = fresh(week)
        s.scoped = scoped.map { l in
            if let r = l.resetsAt, r <= now { return ScopedLimit(name: l.name, utilization: 0, resetsAt: nil) }
            return l
        }
        return s
    }
}

/// The four visual states from docs/DESIGN.md section 4.
enum PaceState: Equatable {
    case normal
    case freshSession
    case sessionLimit
    case weeklyLimit

    static func derive(from raw: UsageSnapshot, now: Date = Date()) -> PaceState {
        let snapshot = raw.normalized(now: now)
        if let week = snapshot.week, week.isFull { return .weeklyLimit }
        guard let session = snapshot.session else { return .freshSession }
        if session.isFull { return .sessionLimit }
        // Only a window that has not started is fresh. 0% with a reset time means
        // the window is running and the countdown is real.
        if session.isFresh, session.resetsAt == nil { return .freshSession }
        return .normal
    }
}
