import XCTest
@testable import Pace

final class ProviderParsingTests: XCTestCase {
    func testStatusLinePayloadFromScript() throws {
        let json = """
        {"rate_limits": {"five_hour": {"used_percentage": 62, "resets_at": 1900000000},
                         "seven_day": {"used_percentage": 41.2, "resets_at": 1900400000}},
         "pace_saved_at": 1899990000.5, "model": {"id": "x"}, "version": null}
        """
        let s = try StatusLineProvider.parse(Data(json.utf8))
        XCTAssertEqual(s.session?.utilization, 62)
        XCTAssertEqual(s.session?.resetsAt, Date(timeIntervalSince1970: 1900000000))
        XCTAssertEqual(s.week?.utilization, 41.2)
        XCTAssertEqual(s.fetchedAt.timeIntervalSince1970, 1899990000.5, accuracy: 0.01)
        XCTAssertEqual(s.source, .statusLine)
    }

    func testStatusLineRawClaudeCodeJSON() throws {
        let json = """
        {"cwd": "/x", "model": {"id": "m"}, "rate_limits": {"seven_day": {"used_percentage": 10, "resets_at": 1900400000}}}
        """
        let s = try StatusLineProvider.parse(Data(json.utf8))
        XCTAssertEqual(s.week?.utilization, 10)
        XCTAssertEqual(s.session?.utilization, 0, "missing session window while week exists means fresh session")
        XCTAssertNil(s.session?.resetsAt)
    }

    func testStatusLineEmptyRateLimits() throws {
        let s = try StatusLineProvider.parse(Data("{\"rate_limits\": {}, \"pace_saved_at\": 1}".utf8))
        XCTAssertFalse(s.hasData)
    }

    func testOAuthLegacyShape() throws {
        let json = """
        {"five_hour": {"utilization": 33.0, "resets_at": "2030-01-02T07:00:00.528743+00:00"},
         "seven_day": {"utilization": 13.0, "resets_at": "2030-01-02T00:59:59.951713+00:00"},
         "seven_day_opus": null,
         "seven_day_sonnet": {"utilization": 1.0, "resets_at": "2030-01-02T03:00:00.951719+00:00"},
         "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null}}
        """
        let s = try OAuthUsageProvider.parse(Data(json.utf8))
        XCTAssertEqual(s.session?.utilization, 33)
        XCTAssertNotNil(s.session?.resetsAt)
        XCTAssertEqual(s.week?.utilization, 13)
        XCTAssertEqual(s.scoped.map(\.name), ["Sonnet weekly"])
        XCTAssertEqual(s.credits?.isEnabled, false)
        XCTAssertEqual(s.source, .oauth)
    }

    func testOAuthLimitsArrayShape() throws {
        let json = """
        {"five_hour": {"utilization": 9.0, "resets_at": "2030-01-02T02:10:00Z"},
         "seven_day": {"utilization": 68.0, "resets_at": "2030-01-02T09:00:00Z"},
         "seven_day_opus": null, "seven_day_sonnet": null,
         "limits": [
           {"kind": "session", "group": "session", "percent": 9, "severity": "normal", "is_active": false},
           {"kind": "weekly_all", "group": "weekly", "percent": 68, "severity": "normal", "is_active": false},
           {"kind": "weekly_scoped", "group": "weekly", "percent": 100, "severity": "critical", "is_active": true,
            "resets_at": "2030-01-02T09:00:00Z", "scope": {"model": {"id": null, "display_name": "Fable"}}}
         ],
         "extra_usage": {"is_enabled": true, "monthly_limit": 5000, "used_credits": 1240, "utilization": 24.8}}
        """
        let s = try OAuthUsageProvider.parse(Data(json.utf8))
        XCTAssertEqual(s.session?.utilization, 9)
        XCTAssertEqual(s.week?.utilization, 68)
        XCTAssertEqual(s.scoped.count, 1)
        XCTAssertEqual(s.scoped.first?.name, "Fable weekly")
        XCTAssertEqual(s.scoped.first?.utilization, 100)
        XCTAssertEqual(s.credits?.isEnabled, true)
        XCTAssertEqual(s.credits?.used, 12.40)
        XCTAssertEqual(s.credits?.monthlyLimit, 50)
        XCTAssertEqual(s.credits?.fraction ?? 0, 0.248, accuracy: 0.001)
    }

    func testOAuthRejectsEmpty() {
        XCTAssertThrowsError(try OAuthUsageProvider.parse(Data("{}".utf8)))
    }

    func testKeychainCredentialsParse() throws {
        let json = """
        {"claudeAiOauth": {"accessToken": "sk-ant-oat01-abc", "refreshToken": "r", "expiresAt": 1900000000000,
                           "scopes": ["user:inference"], "subscriptionType": "max"}, "mcpOAuth": {}}
        """
        let c = try ClaudeKeychain.parse(Data(json.utf8))
        XCTAssertEqual(c.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(c.expiresAt, Date(timeIntervalSince1970: 1900000000))
        XCTAssertEqual(c.subscriptionType, "max")
    }

    func testKeychainMissingTokenThrows() {
        XCTAssertThrowsError(try ClaudeKeychain.parse(Data("{\"mcpOAuth\": {}}".utf8)))
    }

    func testTokenLogByteScan() {
        let line = """
        {"type":"assistant","message":{"usage":{"input_tokens": 1200,"cache_read_input_tokens":5000,"output_tokens":340}}}
        {"type":"user","message":{"content":"input_tokens: not json"}}
        {"message":{"usage":{"input_tokens":10,"output_tokens":5}}}
        """
        XCTAssertEqual(TokenLogReader.tokens(in: Data(line.utf8)), 1200 + 340 + 10 + 5)
    }

    func testEmbeddedScriptMatchesRepoFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/pace-statusline.sh")
        let file = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(file, StatusLineScript.contents + "\n", "scripts/pace-statusline.sh and StatusLineScript.contents must stay identical")
    }
}
