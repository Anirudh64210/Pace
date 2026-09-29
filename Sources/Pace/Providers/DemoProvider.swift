import Foundation

/// Made-up numbers only. Cycles through every state in docs/DESIGN.md section 4 so the UI, animations and
/// notifications can be checked without waiting for real limits. Run with `--demo`.
final class DemoProvider: UsageProvider {
    let kind: UsageSource = .demo

    private let start = Date()
    private var step = 0
    // 2h 14m left of the session, 2d 8h left of the week.
    private var sessionResetsAt = Date().addingTimeInterval(8048)
    private var weekResetsAt = Date().addingTimeInterval(201_600)

    /// Each call advances the story by one step.
    func fetch() async throws -> UsageSnapshot {
        defer { step += 1 }
        let now = Date()
        var s = UsageSnapshot.empty(source: .demo, at: now)
        s.scoped = [ScopedLimit(name: "Fable weekly", utilization: 26, resetsAt: weekResetsAt)]
        s.credits = Credits(isEnabled: true, used: 12.4, monthlyLimit: 50, utilization: 24.8, currency: "USD")
        s.breakdown = [ProductShare(key: "claude_code", name: "Code", percent: 50),
                       ProductShare(key: "cowork", name: "Cowork", percent: 30),
                       ProductShare(key: "chat", name: "Chat", percent: 20)]
        s.plan = "max"

        switch step % 6 {
        case 0: // normal, on pace
            s.session = LimitWindow(utilization: 48, resetsAt: sessionResetsAt)
            s.week = LimitWindow(utilization: 41, resetsAt: weekResetsAt)
        case 1: // climbing
            s.session = LimitWindow(utilization: 88, resetsAt: sessionResetsAt)
            s.week = LimitWindow(utilization: 43, resetsAt: weekResetsAt)
        case 2: // session limit
            s.session = LimitWindow(utilization: 100, resetsAt: sessionResetsAt)
            s.week = LimitWindow(utilization: 45, resetsAt: weekResetsAt)
        case 3: // session reset
            sessionResetsAt = now.addingTimeInterval(5 * 3600)
            s.session = LimitWindow(utilization: 0, resetsAt: nil)
            s.week = LimitWindow(utilization: 45, resetsAt: weekResetsAt)
        case 4: // weekly limit
            s.session = LimitWindow(utilization: 30, resetsAt: sessionResetsAt)
            s.week = LimitWindow(utilization: 100, resetsAt: weekResetsAt)
            s.scoped = [ScopedLimit(name: "Fable weekly", utilization: 100, resetsAt: weekResetsAt)]
        default: // weekly reset
            weekResetsAt = now.addingTimeInterval(7 * 86400)
            sessionResetsAt = now.addingTimeInterval(5 * 3600)
            s.session = LimitWindow(utilization: 0, resetsAt: nil)
            s.week = LimitWindow(utilization: 0, resetsAt: weekResetsAt)
            s.scoped = [ScopedLimit(name: "Fable weekly", utilization: 0, resetsAt: weekResetsAt)]
        }
        return s
    }
}
