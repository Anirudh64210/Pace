import Foundation

/// Everything the panel shows, derived from a snapshot per docs/DESIGN.md
/// section 4. Pure, so every state is unit tested.
///
/// Layout it feeds: a hero with two equal figures (how much is used, how long
/// until it resets) over one bar and one outlook line, then a quiet list of
/// secondary limits. Every number in the panel is "% used".
struct PanelText: Equatable {
    enum Tone: Equatable { case normal, muted, warning, reward }

    /// One secondary limit. Collapsed it is one line; hovered it opens to show
    /// its bar and the exact figures (`lines`).
    struct Row: Equatable, Identifiable {
        var id: String
        var name: String
        var detail: String?
        var detailTone: Tone = .muted
        var value: String
        var valueTone: Tone = .normal
        /// 0...100 for the bar shown when the row is open, nil for no bar.
        var used: Double?
        /// 0...100: where an even pace would be by now, drawn as a tick on the bar.
        var marker: Double?
        /// Two-word label, for accessibility.
        var definer: String
        /// The exact figures shown when the row is open.
        var lines: [Line] = []
    }

    struct Line: Equatable, Hashable {
        var text: String
        var tone: Tone = .muted
    }

    var state: PaceState

    // Hero
    var heroTitle: String
    var used: Int
    var usedCaption: String
    var usedName: String
    var barUsed: Double
    var timer: String
    var timerCaption: String
    var timerName: String
    var timerAccent: Bool
    /// The date the timer counts to. Nil for the static fresh-session timer.
    var timerTarget: Date?
    var outlook: String?
    var outlookTone: Tone

    // Secondary list
    var rows: [Row]

    struct Inputs {
        var snapshot: UsageSnapshot
        var now: Date
        var weekFresh: Bool = false
        var apples: Int = 0
        /// Whether this window's apple was awarded. The "+1 apple" line shows only then.
        var harvested: Bool = true
        var calendar: Calendar = .current
        var locale: Locale = .current
    }

    static let sessionLength: TimeInterval = 5 * 3600
    static let weekLength: TimeInterval = 7 * 86400

    /// When the window runs out at the current rate of use, if that happens
    /// clearly before it resets. Nil when on pace, or too early in the window to say.
    static func runsOut(used: Double, resetsAt: Date?, length: TimeInterval, now: Date) -> Date? {
        guard let resetsAt, used >= 5, used < 100 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0, remaining < length else { return nil }
        let elapsed = length - remaining
        guard elapsed >= length * 0.1 else { return nil }      // too early to judge
        let secondsToFull = (100 - used) / (used / elapsed)
        // Only warn when it is clearly early: 10 minutes for a session, 6 hours for a week.
        let margin = length > 86400 ? 6 * 3600.0 : 600.0
        return secondsToFull < remaining - margin ? now.addingTimeInterval(secondsToFull) : nil
    }

    /// Whether enough of the window has passed to call it "on pace".
    static func canJudge(resetsAt: Date?, length: TimeInterval, now: Date) -> Bool {
        guard let resetsAt else { return false }
        let remaining = resetsAt.timeIntervalSince(now)
        return remaining > 0 && remaining < length && (length - remaining) >= length * 0.1
    }

    init(_ i: Inputs) {
        let now = i.now
        let snap = i.snapshot.normalized(now: now)
        let cal = i.calendar, loc = i.locale
        state = PaceState.derive(from: snap, now: now)

        let session = snap.session ?? LimitWindow(utilization: 0, resetsAt: nil)
        let week = snap.week ?? LimitWindow(utilization: 0, resetsAt: nil)
        let sUsed = min(100, max(0, session.utilization))
        let wUsed = min(100, max(0, week.utilization))

        func clock(_ d: Date?) -> String? { d.map { Formatting.clockTime($0, calendar: cal, locale: loc) } }
        func weekday(_ d: Date?) -> String? { d.map { Formatting.weekdayTime($0, now: now, calendar: cal, locale: loc) } }
        // Below the limit, never round to "100%".
        func shown(_ u: Double) -> Int { u >= 100 ? 100 : min(99, Int(u.rounded())) }
        let noTimer = "--"
        let creditsOn = snap.credits?.isEnabled == true

        // MARK: Hero

        switch state {
        case .weeklyLimit:
            heroTitle = "Week"
            used = 100
            usedCaption = "used this week"
            usedName = "Week used"
            barUsed = 100
            timerTarget = week.resetsAt
            timer = week.resetsAt.map { Formatting.shortCountdown(to: $0, now: now) } ?? noTimer
            timerCaption = weekday(week.resetsAt).map { "back \($0)" } ?? "until the week resets"
            timerName = "Week reset"
            timerAccent = true
            outlook = creditsOn ? "Weekly limit reached. Your credits keep you going."
                                : "Weekly limit reached. Credits work if you turn them on."
            outlookTone = .warning

        case .sessionLimit:
            heroTitle = "Session"
            used = 100
            usedCaption = "used"
            usedName = "Session used"
            barUsed = 100
            timerTarget = session.resetsAt
            timer = session.resetsAt.map { Formatting.shortCountdown(to: $0, now: now) } ?? noTimer
            timerCaption = clock(session.resetsAt).map { "back at \($0)" } ?? "until it is back"
            timerName = "Time left"
            timerAccent = true
            if i.harvested {
                outlook = "+1 apple · about \(Formatting.tokens(Comparisons.tokensPerSession)) tokens this session"
                outlookTone = .reward
            } else {
                outlook = nil
                outlookTone = .muted
            }

        case .freshSession:
            heroTitle = "Session"
            used = 0
            usedCaption = "used"
            usedName = "Session used"
            barUsed = 0
            timerTarget = nil
            timer = "5h"
            timerCaption = "starts with your next message"
            timerName = "Session length"
            timerAccent = false
            outlook = nil
            outlookTone = .muted

        case .normal:
            heroTitle = "Session"
            used = shown(sUsed)
            usedCaption = "used"
            usedName = "Session used"
            barUsed = sUsed
            timerTarget = session.resetsAt
            timer = session.resetsAt.map { Formatting.shortCountdown(to: $0, now: now) } ?? noTimer
            timerCaption = clock(session.resetsAt).map { "until \($0)" } ?? "in progress"
            timerName = "Time left"
            timerAccent = false
            if let out = Self.runsOut(used: sUsed, resetsAt: session.resetsAt, length: Self.sessionLength, now: now) {
                outlook = "At this pace, it runs out around \(clock(out) ?? "soon")"
                outlookTone = .warning
            } else if Self.canJudge(resetsAt: session.resetsAt, length: Self.sessionLength, now: now), sUsed >= 5 {
                outlook = "On pace to last until the reset"
                outlookTone = .muted
            } else {
                outlook = nil
                outlookTone = .muted
            }
        }

        // MARK: Secondary list

        func inTime(_ d: Date?) -> String? {
            guard let d, d > now else { return nil }
            return "in \(Formatting.shortCountdown(to: d, now: now))"
        }
        func resets(_ d: Date?) -> String? {
            guard let r = weekday(d) else { return nil }
            return "resets \(r)" + (inTime(d).map { " · \($0)" } ?? "")
        }

        /// The open part of a weekly window: where an even pace would be, what day
        /// of the window it is, and how much a day keeps you under the limit.
        /// None of it repeats the collapsed line.
        func weeklyAnalysis(used u: Double, resetsAt: Date?, showReset: Bool) -> (marker: Double?, lines: [Line]) {
            var lines: [Line] = []
            guard let resetsAt, resetsAt > now else { return (nil, lines) }
            let remaining = resetsAt.timeIntervalSince(now)
            let elapsed = max(0, Self.weekLength - remaining)
            let even = min(100, elapsed / Self.weekLength * 100)
            let day = min(7, max(1, Int(elapsed / 86400) + 1))
            if showReset, let r = resets(resetsAt) {
                lines.append(Line(text: r.prefix(1).uppercased() + r.dropFirst()))
            }
            lines.append(Line(text: "Day \(day) of 7. An even pace would be \(Int(even.rounded()))% by now."))
            let left = max(0, 100 - u)
            if u >= 100 {
                // Nothing to budget.
            } else if let out = Self.runsOut(used: u, resetsAt: resetsAt, length: Self.weekLength, now: now) {
                let perDay = left / max(remaining / 86400, 1)
                lines.append(Line(text: "At this pace it runs out \(Formatting.weekdayHour(out, calendar: cal, locale: loc)). About \(max(1, Int(perDay.rounded())))% a day would last.", tone: .warning))
            } else if remaining >= 86400 {
                let perDay = left / (remaining / 86400)
                lines.append(Line(text: "About \(max(1, Int(perDay.rounded())))% a day keeps you under the limit."))
            } else {
                lines.append(Line(text: "\(Int(left.rounded()))% left for the rest of the week."))
            }
            return (even, lines)
        }

        var rows: [Row] = []
        if state == .weeklyLimit {
            let lines = [Line(text: "Sessions start again when the week resets.")]
            rows.append(Row(id: "session", name: "Session", detail: nil, value: "Paused",
                            valueTone: .muted, used: nil, definer: "Session paused", lines: lines))
        } else {
            var row = Row(id: "week", name: "Week", detail: nil, value: "\(shown(wUsed))% used", used: wUsed, definer: "Week used")
            let runsOut = Self.runsOut(used: wUsed, resetsAt: week.resetsAt, length: Self.weekLength, now: now)
            if i.weekFresh {
                row.detail = "fresh week"
                row.detailTone = .reward
            } else if let out = runsOut {
                row.detail = "runs out \(Formatting.weekdayHour(out, calendar: cal, locale: loc))"
                row.detailTone = .warning
                row.valueTone = .warning
            } else {
                row.detail = resets(week.resetsAt) ?? "new week"
                row.detailTone = .normal
            }
            // When the collapsed line shows the forecast, the open part shows the reset.
            let analysis = weeklyAnalysis(used: wUsed, resetsAt: week.resetsAt, showReset: runsOut != nil || i.weekFresh)
            row.marker = analysis.marker
            row.lines = analysis.lines.filter { $0.tone != .warning || runsOut == nil }
            if runsOut != nil {
                // The collapsed line already says when; the open part says what would last.
                let left = max(0, 100 - wUsed)
                if let r = week.resetsAt, r > now {
                    let perDay = left / max(r.timeIntervalSince(now) / 86400, 1)
                    row.lines.append(Line(text: "About \(max(1, Int(perDay.rounded())))% a day would last until the reset.", tone: .warning))
                }
            }
            rows.append(row)
        }

        for limit in snap.scoped {
            let u = min(100, max(0, limit.utilization))
            let analysis = weeklyAnalysis(used: u, resetsAt: limit.resetsAt, showReset: true)
            var lines = analysis.lines
            if u >= 100 { lines.append(Line(text: "Other models still work.", tone: .warning)) }
            rows.append(Row(id: "scoped-\(limit.name)", name: limit.name, detail: nil,
                            value: "\(shown(u))% used", valueTone: u >= 100 ? .warning : .normal,
                            used: u, marker: analysis.marker, definer: "Model limit", lines: lines))
        }

        if let c = snap.credits {
            if c.isEnabled {
                let spent = Formatting.money(c.used ?? 0, currency: c.currency)
                let value = c.monthlyLimit.map { "\(spent) of \(Formatting.money($0, currency: c.currency))" } ?? spent
                var lines: [Line] = []
                if let cap = c.monthlyLimit {
                    lines.append(Line(text: "Spent this month. \(Formatting.money(max(0, cap - (c.used ?? 0)), currency: c.currency)) left before the cap."))
                }
                lines.append(Line(text: "Used only after a plan limit is reached, at API prices."))
                rows.append(Row(id: "credits", name: "Credits", detail: nil, value: value,
                                used: c.fraction * 100, definer: "Extra usage", lines: lines))
            } else {
                rows.append(Row(id: "credits", name: "Credits", detail: nil, value: "Off",
                                valueTone: .muted, used: nil, definer: "Extra usage",
                                lines: [Line(text: "Turn on extra usage from Usage to keep working after a limit.")]))
            }
        }
        self.rows = rows
    }

    /// Text next to the apple in the menu bar.
    static func menuBarText(_ text: PanelText, now: Date) -> String? {
        guard let target = text.timerTarget else { return nil }
        return Formatting.shortCountdown(to: target, now: now)
    }
}
