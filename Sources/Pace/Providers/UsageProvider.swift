import Foundation

enum ProviderError: LocalizedError, Equatable {
    /// Nothing to show yet, and nothing is wrong (setup pending, no message sent yet).
    case noData(String)
    case notSignedIn
    case keychainUnavailable(String)
    case tokenExpired
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case offline
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noData(let hint): return hint
        case .notSignedIn: return "No Claude Code sign-in on this Mac. Run claude in a terminal and sign in, then retry."
        case .keychainUnavailable(let why): return "Could not read the Claude Code sign-in: \(why)"
        case .tokenExpired: return "Your Claude sign-in needs renewing. It renews the next time Claude Code or the Claude app's Code tab runs, and Pace picks it up within a minute."
        case .forbidden: return "Anthropic refused this sign-in for usage data (HTTP 403). Sign out and back in to Claude Code, or use the status line source."
        case .rateLimited: return "The usage endpoint asked Pace to slow down. It will try again on its own."
        case .http(let code): return "The usage endpoint returned an error (HTTP \(code))."
        case .offline: return "You appear to be offline."
        case .badResponse(let why): return "The usage response changed shape: \(why)"
        }
    }

    /// Waiting is a normal state, not a failure: no backoff, no red text.
    var isWaiting: Bool {
        if case .noData = self { return true }
        return false
    }

    /// Failures that a timer cannot fix and that Pace should not keep retrying.
    var needsUser: Bool {
        switch self {
        case .keychainUnavailable, .forbidden: return true
        default: return false
        }
    }

    /// The user fixes these elsewhere (by opening Claude Code). Pace re-checks the
    /// Keychain quietly, with no network call, until the sign-in is back.
    var isRecheckable: Bool {
        switch self {
        case .notSignedIn, .tokenExpired: return true
        default: return false
        }
    }
}

/// A source of usage snapshots. Each source can be swapped when it breaks.
protocol UsageProvider: AnyObject {
    var kind: UsageSource { get }
    func fetch() async throws -> UsageSnapshot
}

/// Shared JSON helpers for the providers.
enum JSONHelpers {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.badResponse("top level is not an object")
        }
        return obj
    }

    static func double(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d.isFinite ? d : nil
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String: return Double(s).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }

    /// Dates outside this range are treated as missing. Limits reset within days,
    /// credentials expire within months; anything else is bad input.
    static let saneDates = Date(timeIntervalSince1970: 1_577_836_800)...Date(timeIntervalSince1970: 4_102_444_800) // 2020...2100

    /// Accepts ISO 8601 strings (with or without fractional seconds) and epoch
    /// seconds or milliseconds. Returns nil for anything non-finite or out of range.
    static func date(_ any: Any?) -> Date? {
        var result: Date?
        if let s = any as? String, let d = iso(s) {
            result = d
        } else if let n = double(any), n.isFinite, n > 0 {
            // Past the year 2100 in seconds means milliseconds.
            result = Date(timeIntervalSince1970: n > 4_102_444_800 ? n / 1000 : n)
        }
        guard let result, saneDates.contains(result) else { return nil }
        return result
    }

    private static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
