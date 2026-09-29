import Foundation

/// Polls the usage endpoint with the sign-in Claude Code already has on this Mac.
///
/// Security: the token is a full account credential. It is read from the
/// Keychain, kept only in this object's memory until it expires, sent only to
/// `endpoint`, and never written to disk or logged.
final class OAuthUsageProvider: UsageProvider {
    let kind: UsageSource = .oauth

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Pace uses Claude Code's sign-in, so it identifies as a Claude Code client and
    /// names itself. The endpoint is reported to rate limit unknown clients hard.
    static let userAgent = "claude-code/2.1.283 (compatible; Pace/\(PaceVersion.string); +https://github.com/Anirudh64210/pace)"

    typealias CredentialReader = () async throws -> ClaudeKeychain.Credentials

    private let session: URLSession
    private let readCredentials: CredentialReader
    private var cached: ClaudeKeychain.Credentials?

    /// Plan name from the sign-in ("max", "pro"), once known.
    private(set) var plan: String?

    /// Nothing about these requests is stored: no cache, no cookies. Redirects
    /// are refused so the bearer token can only ever reach `endpoint`.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    deinit { session.finishTasksAndInvalidate() }

    init(session: URLSession = OAuthUsageProvider.makeSession(), credentials: @escaping CredentialReader = { try await ClaudeCredentials.read() }) {
        self.session = session
        self.readCredentials = credentials
    }

    func fetch() async throws -> UsageSnapshot {
        let creds = try await credentials(forceReload: false)
        do {
            return try await request(with: creds)
        } catch ProviderError.tokenExpired {
            // Claude Code may have refreshed the token since it was cached. Re-read once.
            let fresh = try await credentials(forceReload: true)
            guard fresh.accessToken != creds.accessToken else { throw ProviderError.tokenExpired }
            return try await request(with: fresh)
        }
    }

    private func credentials(forceReload: Bool) async throws -> ClaudeKeychain.Credentials {
        if !forceReload, let cached, !cached.isExpired(at: Date()) { return cached }
        cached = nil
        let creds = try await readCredentials()
        if creds.isExpired(at: Date()) { throw ProviderError.tokenExpired }
        cached = creds
        plan = creds.subscriptionType
        return creds
    }

    private func request(with creds: ClaudeKeychain.Credentials) async throws -> UsageSnapshot {
        precondition(Self.endpoint.scheme == "https" && Self.endpoint.host == "api.anthropic.com")
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut, .dnsLookupFailed].contains(error.code) {
            throw ProviderError.offline
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401:
                throw ProviderError.tokenExpired
            case 403:
                throw ProviderError.forbidden
            case 300..<400:
                throw ProviderError.badResponse("unexpected redirect, refused")
            case 429:
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw ProviderError.rateLimited(retryAfter: retry)
            default:
                throw ProviderError.http(http.statusCode)
            }
        }
        var snapshot = try Self.parse(data)
        snapshot.plan = creds.subscriptionType
        return snapshot
    }

    /// Parses the usage response. Handles both the older top-level windows and
    /// the newer `limits[]` array, and treats every unknown field as optional.
    static func parse(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        let root = try JSONHelpers.object(data)
        var snapshot = UsageSnapshot.empty(source: .oauth, at: fetchedAt)

        snapshot.session = window(root["five_hour"])
        snapshot.week = window(root["seven_day"])

        // Legacy per-model windows.
        for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
            if let w = window(root[key]) {
                snapshot.scoped.append(ScopedLimit(name: "\(name) weekly", utilization: w.utilization, resetsAt: w.resetsAt))
            }
        }

        // Newer shape: limits[] with kind / percent / resets_at / scope.
        if let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                let kind = (limit["kind"] as? String) ?? ""
                let percent = JSONHelpers.double(limit["percent"]) ?? JSONHelpers.double(limit["utilization"])
                let resetsAt = JSONHelpers.date(limit["resets_at"])
                switch kind {
                case "session", "five_hour":
                    if snapshot.session == nil, let percent { snapshot.session = LimitWindow(utilization: percent, resetsAt: resetsAt) }
                    else if snapshot.session?.resetsAt == nil { snapshot.session?.resetsAt = resetsAt }
                case "weekly_all", "seven_day":
                    if snapshot.week == nil, let percent { snapshot.week = LimitWindow(utilization: percent, resetsAt: resetsAt) }
                    else if snapshot.week?.resetsAt == nil { snapshot.week?.resetsAt = resetsAt }
                default:
                    guard let percent else { continue }
                    let name = scopedName(limit)
                    if !snapshot.scoped.contains(where: { $0.name == name }) {
                        snapshot.scoped.append(ScopedLimit(name: name, utilization: percent, resetsAt: resetsAt))
                    }
                }
            }
        }

        snapshot.credits = credits(root)
        snapshot.breakdown = breakdown(root)

        guard snapshot.hasData else { throw ProviderError.badResponse("no five_hour or seven_day window") }
        return snapshot
    }

    /// Credits: the newer `spend` object first (amounts in minor units with an
    /// exponent), then the older `extra_usage` object (amounts in cents).
    static func credits(_ root: [String: Any]) -> Credits? {
        func amount(_ any: Any?) -> Double? {
            guard let o = any as? [String: Any], let minor = JSONHelpers.double(o["amount_minor"]) else { return nil }
            return minor / pow(10, JSONHelpers.double(o["exponent"]) ?? 2)
        }
        if let spend = root["spend"] as? [String: Any] {
            let used = amount(spend["used"])
            let limit = amount(spend["limit"]) ?? amount(spend["cap"])
            let currency = ((spend["used"] as? [String: Any])?["currency"] as? String)
                ?? ((spend["limit"] as? [String: Any])?["currency"] as? String)
            return Credits(isEnabled: (spend["enabled"] as? Bool) ?? false,
                           used: used, monthlyLimit: limit,
                           utilization: JSONHelpers.double(spend["percent"]),
                           currency: currency)
        }
        if let extra = root["extra_usage"] as? [String: Any] {
            let scale = pow(10, JSONHelpers.double(extra["decimal_places"]) ?? 2)
            return Credits(isEnabled: (extra["is_enabled"] as? Bool) ?? false,
                           used: JSONHelpers.double(extra["used_credits"]).map { $0 / scale },
                           monthlyLimit: JSONHelpers.double(extra["monthly_limit"]).map { $0 / scale },
                           utilization: JSONHelpers.double(extra["utilization"]),
                           currency: extra["currency"] as? String)
        }
        return nil
    }

    /// `seven_day_breakdown.rows`: each product's share of this week's usage.
    static func breakdown(_ root: [String: Any]) -> [ProductShare] {
        guard let b = root["seven_day_breakdown"] as? [String: Any],
              let rows = b["rows"] as? [[String: Any]] else { return [] }
        let short = ["claude_code": "Code", "chat": "Chat", "cowork": "Cowork", "other": "Other"]
        return rows.compactMap { row in
            guard let key = row["key"] as? String, let pct = JSONHelpers.double(row["percent"]) else { return nil }
            let name = short[key] ?? (row["display_name"] as? String) ?? key.replacingOccurrences(of: "_", with: " ").capitalized
            return ProductShare(key: key, name: name, percent: max(0, min(100, pct)))
        }
        .sorted { $0.percent > $1.percent }
    }

    private static func window(_ any: Any?) -> LimitWindow? {
        guard let obj = any as? [String: Any] else { return nil }
        guard let pct = JSONHelpers.double(obj["utilization"]) ?? JSONHelpers.double(obj["percent"]) ?? JSONHelpers.double(obj["used_percentage"]) else { return nil }
        return LimitWindow(utilization: pct, resetsAt: JSONHelpers.date(obj["resets_at"]))
    }

    private static func scopedName(_ limit: [String: Any]) -> String {
        let kind = (limit["kind"] as? String) ?? "limit"
        let group = (limit["group"] as? String) ?? ""
        var model: String?
        if let scope = limit["scope"] as? [String: Any] {
            if let m = scope["model"] as? [String: Any] {
                model = (m["display_name"] as? String) ?? (m["id"] as? String)
            } else if let surface = scope["surface"] as? [String: Any] {
                model = (surface["display_name"] as? String) ?? (surface["id"] as? String)
            } else if let s = scope["display_name"] as? String {
                model = s
            }
        }
        if let model, !model.isEmpty {
            return group == "weekly" || kind.hasPrefix("weekly") ? "\(model) weekly" : model
        }
        if let name = limit["name"] as? String { return name }
        return kind.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Refuses every redirect so the Authorization header never follows one.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
