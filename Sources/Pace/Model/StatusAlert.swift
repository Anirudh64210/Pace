import Foundation

/// A short announcement of a status change, shown as the pill under the menu
/// bar icon (or inside the panel when it is open), and optionally as a system
/// notification.
struct StatusAlert: Equatable, Identifiable {
    enum Kind: Equatable { case good, warning, reward }

    let id = UUID()
    var title: String
    var detail: String
    var kind: Kind

    static func == (a: StatusAlert, b: StatusAlert) -> Bool { a.id == b.id }

    /// The copy for each event. `snapshot` is the data after the change.
    static func make(_ event: PaceEvent, snapshot: UsageSnapshot?, now: Date,
                     calendar: Calendar = .current, locale: Locale = .current) -> StatusAlert {
        let session = snapshot?.session
        let week = snapshot?.week
        func clock(_ d: Date?) -> String? {
            guard let d, d > now else { return nil }
            return Formatting.clockTime(d, calendar: calendar, locale: locale)
        }
        func weekday(_ d: Date?) -> String? {
            guard let d, d > now else { return nil }
            return Formatting.weekdayTime(d, now: now, calendar: calendar, locale: locale)
        }
        switch event {
        case .sessionReset:
            return StatusAlert(title: "Session back", detail: "a fresh 5 hours", kind: .good)
        case .weeklyReset:
            return StatusAlert(title: "New week", detail: "everything's full", kind: .good)
        case .sessionLimitHit:
            return StatusAlert(title: "Session limit", detail: clock(session?.resetsAt).map { "back at \($0)" } ?? "+1 apple", kind: .reward)
        case .weeklyLimitHit:
            return StatusAlert(title: "Weekly limit", detail: weekday(week?.resetsAt).map { "back \($0)" } ?? "reached", kind: .warning)
        case .paceWarning:
            let out = snapshot.flatMap { s -> Date? in
                guard let w = s.session else { return nil }
                return PanelText.runsOut(used: w.utilization, resetsAt: w.resetsAt, length: PanelText.sessionLength, now: now)
            }
            return StatusAlert(title: "Running fast", detail: clock(out).map { "runs out around \($0)" } ?? "at this pace it runs out early", kind: .warning)
        }
    }

    /// Longer copy for the optional system notification.
    var notificationTitle: String {
        switch title {
        case "Session back": return "Your session is back"
        case "New week": return "New week, everything's full"
        default: return title
        }
    }
}
