import Foundation

/// Text formatting for timers and reset times. All functions take an explicit
/// `now` and calendar so they can be tested with fixed dates.
enum Formatting {
    /// Whole seconds between two dates, clamped so the Int conversion can never trap.
    static func seconds(from now: Date, to date: Date) -> Int {
        let raw = date.timeIntervalSince(now)
        guard raw.isFinite else { return 0 }
        return Int(max(0, min(raw, 100 * 365 * 86400)).rounded(.down))
    }

    /// Time left, calmly: `2h 14m`, `48m`, `2d 8h`, `5h`. No seconds anywhere:
    /// a ticking second counter pulls attention for no gain. Rounds up, so it
    /// never says "0m" while time remains.
    static func shortCountdown(to date: Date, now: Date) -> String {
        let total = seconds(from: now, to: date)
        guard total > 0 else { return "0m" }
        let minutes = (total + 59) / 60
        let days = minutes / 1440
        let h = (minutes % 1440) / 60
        let m = minutes % 60
        if days > 0 { return h > 0 ? "\(days)d \(h)h" : "\(days)d" }
        if h > 0 { return m > 0 ? "\(h)h \(String(format: "%02d", m))m" : "\(h)h" }
        return "\(m)m"
    }

    /// `3:32 AM` in the user's locale.
    static func clockTime(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = formatter("short-time", calendar, locale) { f in
            f.timeStyle = .short
            f.dateStyle = .none
        }
        return tidy(f.string(from: date))
    }

    /// `Thu 9 PM` (or `Thu 9:30 PM`) when within the next six days,
    /// otherwise `Thu Oct 8, 9 PM`.
    static func weekdayTime(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let withinWeek = date.timeIntervalSince(now) < 6 * 86400
        return withinWeek ? weekdayHour(date, calendar: calendar, locale: locale)
                          : weekdayDateHour(date, calendar: calendar, locale: locale)
    }

    /// Always includes the date: `Thu Oct 8, 9 PM`.
    static func weekdayDateHour(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let weekday = part("EEE", date, calendar, locale)
        let day = part("MMMd", date, calendar, locale)
        return "\(weekday) \(day), \(hour(date, calendar: calendar, locale: locale))"
    }

    /// `Thu 9 PM` or `Thu 9:30 PM`.
    static func weekdayHour(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        "\(part("EEE", date, calendar, locale)) \(hour(date, calendar: calendar, locale: locale))"
    }

    /// `9 PM`, or `9:30 PM` when minutes are not zero. 24-hour locales get `21:00`.
    static func hour(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        part(usesMinutes(date, calendar) ? "jmm" : "j", date, calendar, locale)
    }

    static func tokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            let m = Double(count) / 1_000_000
            return m >= 10 || m == m.rounded() ? "\(Int(m.rounded()))M" : String(format: "%.1fM", m)
        }
        if count >= 1_000 { return "\(Int((Double(count) / 1_000).rounded()))K" }
        return "\(count)"
    }

    static func money(_ amount: Double, currency: String? = nil) -> String {
        let safe = amount.isFinite ? min(max(amount, -1e12), 1e12) : 0
        let number = safe == safe.rounded() ? String(format: "%.0f", safe) : String(format: "%.2f", safe)
        switch (currency ?? "USD").uppercased() {
        case "USD": return "$" + number
        case "EUR": return "€" + number
        case "GBP": return "£" + number
        case let code: return "\(code) \(number)"
        }
    }

    static func relativeAge(of date: Date, now: Date) -> String {
        let secs = seconds(from: date, to: now)
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60) min ago" }
        if secs < 86400 { return "\(secs / 3600) h ago" }
        return "\(secs / 86400) d ago"
    }

    // MARK: - private

    private static func part(_ template: String, _ date: Date, _ calendar: Calendar, _ locale: Locale) -> String {
        let f = formatter(template, calendar, locale) { $0.setLocalizedDateFormatFromTemplate(template) }
        return tidy(f.string(from: date))
    }

    /// DateFormatters are expensive; the panel asks for the same few every second.
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    private static func formatter(_ id: String, _ calendar: Calendar, _ locale: Locale, configure: (DateFormatter) -> Void) -> DateFormatter {
        let key = "\(id)|\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)"
        formattersLock.lock()
        defer { formattersLock.unlock() }
        if let f = formatters[key] { return f }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        configure(f)
        formatters[key] = f
        return f
    }

    private static func usesMinutes(_ date: Date, _ calendar: Calendar) -> Bool {
        calendar.component(.minute, from: date) != 0
    }

    /// Some locales insert a narrow no-break space before AM/PM. Use a plain space.
    private static func tidy(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
