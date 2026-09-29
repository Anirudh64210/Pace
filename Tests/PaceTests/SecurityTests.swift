import XCTest
@testable import Pace

/// Token and network safety.
final class SecurityTests: XCTestCase {
    let fakeToken = "sk-ant-oat01-PACE-TEST-TOKEN-DO-NOT-LEAK"

    var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        MockURLProtocol.responses = []
        MockURLProtocol.seenTokens = []
        MockURLProtocol.seenHosts = []
        MockURLProtocol.redirectTo = nil
    }

    func testEndpointIsPinnedToAnthropicOverHTTPS() {
        XCTAssertEqual(OAuthUsageProvider.endpoint.scheme, "https")
        XCTAssertEqual(OAuthUsageProvider.endpoint.host, "api.anthropic.com")
    }

    func testDefaultSessionStoresNothingAndRefusesRedirects() {
        let s = OAuthUsageProvider.makeSession()
        XCTAssertNil(s.configuration.urlCache)
        XCTAssertNil(s.configuration.httpCookieStorage)
        XCTAssertNil(s.configuration.urlCredentialStorage)
        XCTAssertFalse(s.configuration.httpShouldSetCookies)
        XCTAssertTrue(s.delegate is NoRedirects)
    }

    /// A real redirect, through the production session delegate: the request to
    /// the other host must never happen, so the token cannot follow.
    func testRedirectIsRefused() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        MockURLProtocol.redirectTo = URL(string: "https://evil.example/steal")!
        MockURLProtocol.responses = [(200, [:], #"{"five_hour":{"utilization":1}}"#)]
        let p = OAuthUsageProvider(session: session, credentials: { .init(accessToken: self.fakeToken, expiresAt: nil, subscriptionType: nil) })
        do {
            _ = try await p.fetch()
            XCTFail("a redirect must not produce data")
        } catch {}
        XCTAssertEqual(MockURLProtocol.seenHosts, ["api.anthropic.com"], "no request ever reaches the redirect target")
    }

    /// Control: without the delegate the same mock does follow the redirect,
    /// which proves the test above exercises NoRedirects.
    func testRedirectMockFollowsWithoutTheDelegate() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        MockURLProtocol.redirectTo = URL(string: "https://evil.example/steal")!
        MockURLProtocol.responses = [(200, [:], #"{"five_hour":{"utilization":1}}"#)]
        let p = OAuthUsageProvider(session: session, credentials: { .init(accessToken: self.fakeToken, expiresAt: nil, subscriptionType: nil) })
        _ = try? await p.fetch()
        XCTAssertEqual(MockURLProtocol.seenHosts, ["api.anthropic.com", "evil.example"])
    }

    func testErrorsNeverContainTheToken() async {
        let bodies = [(500, fakeToken), (400, #"{"error":"\#(fakeToken)"}"#), (200, "not json \(fakeToken)"), (200, #"{"five_hour":"\#(fakeToken)"}"#)]
        for (code, body) in bodies {
            MockURLProtocol.responses = [(code, [:], body)]
            let p = OAuthUsageProvider(session: session, credentials: { .init(accessToken: self.fakeToken, expiresAt: nil, subscriptionType: nil) })
            do {
                _ = try await p.fetch()
            } catch {
                XCTAssertFalse(error.localizedDescription.contains(fakeToken), "HTTP \(code): \(error.localizedDescription)")
                XCTAssertFalse(String(describing: error).contains(fakeToken))
            }
        }
    }

    func testCredentialsDescriptionDoesNotExposeToken() {
        let c = ClaudeKeychain.Credentials(accessToken: fakeToken, expiresAt: nil, subscriptionType: "max")
        XCTAssertFalse(String(describing: c).contains(fakeToken))
        XCTAssertFalse(String(reflecting: c).contains(fakeToken))
    }

    func testSnapshotNeverCarriesTheToken() throws {
        var s = UsageSnapshot.empty(source: .oauth)
        s.plan = "max"
        let data = try JSONEncoder().encode(s)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("sk-ant"))
    }
}

/// Parsers take input from outside the app. None of it may crash them.
final class ParserFuzzTests: XCTestCase {
    func randomJSON(depth: Int, rng: inout SystemRandomNumberGenerator) -> Any {
        let keys = ["five_hour", "seven_day", "utilization", "resets_at", "limits", "kind", "percent", "scope",
                    "spend", "used", "amount_minor", "exponent", "extra_usage", "seven_day_breakdown", "rows", "key",
                    "used_percentage", "rate_limits", "claudeAiOauth", "accessToken", "expiresAt"]
        switch depth > 3 ? Int.random(in: 0...3, using: &rng) : Int.random(in: 0...5, using: &rng) {
        case 0: return Double.random(in: -1e12...1e12, using: &rng)
        case 1: return ["x", "", "2030-01-01T05:00:00Z", "NaN", "1e999"].randomElement(using: &rng)!
        case 2: return Bool.random(using: &rng)
        case 3: return NSNull()
        case 4: return (0..<Int.random(in: 0...4, using: &rng)).map { _ in randomJSON(depth: depth + 1, rng: &rng) }
        default:
            var d: [String: Any] = [:]
            for _ in 0..<Int.random(in: 0...6, using: &rng) { d[keys.randomElement(using: &rng)!] = randomJSON(depth: depth + 1, rng: &rng) }
            return d
        }
    }

    func testRandomInputNeverCrashes() throws {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<3000 {
            let obj = randomJSON(depth: 0, rng: &rng)
            guard JSONSerialization.isValidJSONObject(obj) else { continue }
            let data = try JSONSerialization.data(withJSONObject: obj)
            _ = try? OAuthUsageProvider.parse(data)
            _ = try? StatusLineProvider.parse(data)
            _ = try? ClaudeKeychain.parse(data)
            _ = ClaudeKeychain.decodeOutput(data)
        }
    }

    /// Parsed values flow into formatting and layout. Extreme numbers must not
    /// trap anywhere on the way to the screen.
    func testExtremeValuesRenderWithoutCrashing() throws {
        let values: [Any] = [1e22, -1e22, 1e308, -5, 0, 4_102_444_801, 4_102_444_800_000, "Infinity", "NaN", "9999-12-31T00:00:00Z"]
        for v in values {
            let obj: [String: Any] = [
                "five_hour": ["utilization": v, "resets_at": v],
                "seven_day": ["utilization": v, "resets_at": v],
                "spend": ["used": ["amount_minor": v, "exponent": v], "enabled": true, "percent": v],
                "seven_day_breakdown": ["rows": [["key": "chat", "percent": v]]],
                "limits": [["kind": "weekly_scoped", "percent": v, "resets_at": v]],
            ]
            guard JSONSerialization.isValidJSONObject(obj),
                  let s = try? OAuthUsageProvider.parse(JSONSerialization.data(withJSONObject: obj)) else { continue }
            let t = PanelText(.init(snapshot: s, now: Date()))
            _ = PanelText.menuBarText(t, now: Date())
            _ = Formatting.money(s.credits?.used ?? 0, currency: s.credits?.currency)
            _ = Formatting.relativeAge(of: s.fetchedAt, now: Date())
        }
        for d in [Date.distantFuture, Date.distantPast, Date(timeIntervalSince1970: 1e15)] {

            _ = Formatting.shortCountdown(to: d, now: Date())
            _ = Formatting.relativeAge(of: d, now: Date())
        }
        _ = Formatting.money(.infinity)
        _ = Formatting.money(1e300)
    }

    /// The newer response shape, with made-up values. Unknown fields are ignored.
    func testNewerShapeParses() throws {
        let json = """
        {"five_hour":{"utilization":10.0,"resets_at":"2030-01-01T05:00:00.000000+00:00","limit_dollars":null},
         "seven_day":{"utilization":40.0,"resets_at":"2030-01-05T00:00:00.000000+00:00"},
         "some_future_field":{"utilization":0.0,"limit_dollars":100},
         "extra_usage":{"is_enabled":false,"monthly_limit":null,"used_credits":null,"currency":null,"decimal_places":null},
         "limits":[{"kind":"session","group":"session","percent":10,"resets_at":"2030-01-01T05:00:00Z","scope":null},
                   {"kind":"weekly_all","group":"weekly","percent":40,"scope":null},
                   {"kind":"weekly_scoped","group":"weekly","percent":30,"resets_at":"2030-01-05T00:00:00Z",
                    "scope":{"model":{"id":null,"display_name":"Fable"},"surface":null}}],
         "spend":{"used":{"amount_minor":0,"currency":"USD","exponent":2},"limit":null,"percent":0,"enabled":false},
         "seven_day_breakdown":{"rows":[{"key":"claude_code","display_name":"Claude Code","percent":50},
                                        {"key":"chat","display_name":"Chats","percent":20},
                                        {"key":"cowork","display_name":"Cowork","percent":30},
                                        {"key":"other","display_name":"Other","percent":0}]}}
        """
        let s = try OAuthUsageProvider.parse(Data(json.utf8))
        XCTAssertEqual(s.week?.utilization, 40)
        XCTAssertEqual(s.scoped.map(\.name), ["Fable weekly"])
        XCTAssertEqual(s.scoped.first?.utilization, 30)
        XCTAssertEqual(s.credits?.isEnabled, false)
        XCTAssertEqual(s.credits?.used, 0)
        XCTAssertEqual(s.credits?.currency, "USD")
        XCTAssertEqual(s.breakdown.map(\.name), ["Code", "Cowork", "Chat", "Other"])
        XCTAssertEqual(s.breakdown.first?.percent, 50)
    }

    func testSpendWithLimitInMinorUnits() throws {
        let json = #"{"five_hour":{"utilization":1},"spend":{"used":{"amount_minor":1240,"currency":"USD","exponent":2},"limit":{"amount_minor":5000,"currency":"USD","exponent":2},"percent":24.8,"enabled":true}}"#
        let c = try OAuthUsageProvider.parse(Data(json.utf8)).credits
        XCTAssertEqual(c?.used, 12.4)
        XCTAssertEqual(c?.monthlyLimit, 50)
        XCTAssertEqual(c?.isEnabled, true)
    }
}

final class HygieneTests: XCTestCase {
    func testSharedHTTPCacheIsDisabled() {
        Hygiene.run()
        XCTAssertEqual(URLCache.shared.diskCapacity, 0)
        XCTAssertEqual(URLCache.shared.memoryCapacity, 0)
    }
}
