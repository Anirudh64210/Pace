import Foundation

/// `Pace --check`: tries each data source once and prints what it found.
/// Prints percentages and times only. Never prints the token.
enum HealthCheck {
    static func run() async {
        print("Pace check\n")

        print("Status line")
        switch StatusLineInstaller.status() {
        case .installed: print("  script: installed")
        case .notInstalled: print("  script: not installed (open Pace and click Install status line)")
        case .otherStatusLine: print("  script: not installed (another status line is configured; Install keeps it)")
        }
        do {
            let s = try await StatusLineProvider().fetch()
            print("  data: \(describe(s))")
        } catch {
            print("  data: \(error.localizedDescription)")
        }

        print("\nClaude sign-in (reads the Keychain and, if the desktop app saved one, ~/.claude/.credentials.json; the token is never printed)")
        do {
            let c = try await ClaudeCredentials.read()
            let exp = c.expiresAt.map { $0 > Date() ? "valid for \(Formatting.shortCountdown(to: $0, now: Date()))" : "expired" } ?? "no expiry"
            print("  sign-in: found, \(c.subscriptionType ?? "unknown") plan, token \(exp)")
            let s = try await OAuthUsageProvider(credentials: { c }).fetch()
            print("  endpoint: \(describe(s))")
        } catch {
            print("  \(error.localizedDescription)")
        }
    }

    static func describe(_ s: UsageSnapshot) -> String {
        let now = Date()
        func w(_ name: String, _ l: LimitWindow?) -> String? {
            guard let l else { return nil }
            let r = l.resetsAt.map { ", resets in \(Formatting.shortCountdown(to: $0, now: now))" } ?? ""
            return "\(name) \(Int(l.utilization.rounded()))% used\(r)"
        }
        var parts = [w("session", s.session), w("week", s.week)].compactMap { $0 }
        parts += s.scoped.map { "\($0.name) \(Int($0.utilization.rounded()))% used" }
        if let c = s.credits {
            if c.isEnabled {
                let cap = c.monthlyLimit.map { Formatting.money($0, currency: c.currency) } ?? "no cap"
                parts.append("credits \(Formatting.money(c.used ?? 0, currency: c.currency)) of \(cap)")
            } else {
                parts.append("credits off")
            }
        }
        if !s.breakdown.isEmpty {
            parts.append("this week by product: " + s.breakdown.map { "\($0.name) \(Int($0.percent))%" }.joined(separator: ", "))
        }
        parts.append("updated \(Formatting.relativeAge(of: s.fetchedAt, now: now))")
        return parts.joined(separator: "; ")
    }
}
