import Foundation

/// Reads the JSON that `scripts/pace-statusline.sh` saves from Claude Code's
/// status line input. No credentials involved. Only updates while Claude Code runs.
final class StatusLineProvider: UsageProvider {
    let kind: UsageSource = .statusLine

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pace", isDirectory: true)
    }
    static var defaultFile: URL { defaultDirectory.appendingPathComponent("status.json") }

    let fileURL: URL

    init(fileURL: URL = StatusLineProvider.defaultFile) {
        self.fileURL = fileURL
    }

    func fetch() async throws -> UsageSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw ProviderError.noData("Waiting for Claude Code. Install the status line script from Settings, then send one message in Claude Code.")
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modified = attrs?[.modificationDate] as? Date ?? Date()
        let snapshot = try Self.parse(data, fetchedAt: modified)
        guard snapshot.hasData else {
            throw ProviderError.noData("Connected. Send a message in Claude Code and your limits show up here.")
        }
        return snapshot
    }

    /// Parses the Claude Code status line JSON (or a wrapper written by the script).
    static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let root = try JSONHelpers.object(data)
        // The script may save the whole status line payload, or just `rate_limits`.
        let limits = (root["rate_limits"] as? [String: Any]) ?? root
        var snapshot = UsageSnapshot.empty(source: .statusLine, at: fetchedAt)
        if let w = window(limits["five_hour"]) { snapshot.session = w }
        if let w = window(limits["seven_day"]) { snapshot.week = w }
        // `rate_limits` is only present after the first API response; a missing
        // session window while a weekly one exists means the session is fresh.
        if snapshot.session == nil, snapshot.week != nil {
            snapshot.session = LimitWindow(utilization: 0, resetsAt: nil)
        }
        if let saved = JSONHelpers.date(root["pace_saved_at"]) { snapshot.fetchedAt = saved }
        return snapshot
    }

    private static func window(_ any: Any?) -> LimitWindow? {
        guard let obj = any as? [String: Any] else { return nil }
        guard let pct = JSONHelpers.double(obj["used_percentage"]) ?? JSONHelpers.double(obj["utilization"]) else { return nil }
        return LimitWindow(utilization: pct, resetsAt: JSONHelpers.date(obj["resets_at"]))
    }
}
