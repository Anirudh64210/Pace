import XCTest
@testable import Pace

// MARK: - Policy

final class SyncPolicyTests: XCTestCase {
    func testBackoffDoublesAndCaps() {
        XCTAssertEqual(SyncPolicy.backoff(for: .oauth, failures: 1, retryAfter: nil), 300)
        XCTAssertEqual(SyncPolicy.backoff(for: .oauth, failures: 2, retryAfter: nil), 600)
        XCTAssertEqual(SyncPolicy.backoff(for: .oauth, failures: 10, retryAfter: nil), 1800)
        XCTAssertEqual(SyncPolicy.backoff(for: .statusLine, failures: 1, retryAfter: nil), 60)
    }

    func testBackoffHonoursRetryAfter() {
        XCTAssertEqual(SyncPolicy.backoff(for: .oauth, failures: 1, retryAfter: 900), 900)
    }

    func testExpiredWindowsNormalizeToFresh() {
        let now = Date()
        var s = UsageSnapshot.empty(source: .statusLine, at: now)
        s.session = LimitWindow(utilization: 100, resetsAt: now.addingTimeInterval(-10))
        s.week = LimitWindow(utilization: 100, resetsAt: now.addingTimeInterval(-10))
        let n = s.normalized(now: now)
        XCTAssertEqual(n.session?.utilization, 0)
        XCTAssertEqual(n.week?.utilization, 0)
        XCTAssertEqual(PaceState.derive(from: s, now: now), .freshSession)
    }

    func testKeychainHexOutputDecodes() {
        let json = #"{"claudeAiOauth":{"accessToken":"t"}}"#
        let hex = json.utf8.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(String(decoding: ClaudeKeychain.decodeOutput(Data((hex + "\n").utf8)), as: UTF8.self), json)
        XCTAssertEqual(String(decoding: ClaudeKeychain.decodeOutput(Data((json + "\n").utf8)), as: UTF8.self), json)
    }
}

// MARK: - OAuth provider against a mocked endpoint

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(Int, [String: String], String)] = []
    nonisolated(unsafe) static var seenTokens: [String] = []
    nonisolated(unsafe) static var seenHosts: [String] = []
    /// When set, the first request is redirected here, the way a real server would.
    nonisolated(unsafe) static var redirectTo: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seenHosts.append(request.url?.host ?? "")
        if let target = Self.redirectTo {
            Self.redirectTo = nil
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            var next = URLRequest(url: target)
            next.allHTTPHeaderFields = request.allHTTPHeaderFields
            Self.seenTokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Self.seenTokens.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        let (code, headers, body) = Self.responses.isEmpty ? (500, [:], "") : Self.responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OAuthFlowTests: XCTestCase {
    let ok = #"{"five_hour":{"utilization":40,"resets_at":"2099-01-01T00:00:00Z"},"seven_day":{"utilization":20,"resets_at":"2099-01-05T00:00:00Z"}}"#

    var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        MockURLProtocol.responses = []
        MockURLProtocol.seenTokens = []
    }

    final class Reader: @unchecked Sendable {
        var tokens: [String]
        var calls = 0
        init(_ tokens: [String]) { self.tokens = tokens }
        func read() throws -> ClaudeKeychain.Credentials {
            calls += 1
            let t = tokens.count > 1 ? tokens.removeFirst() : tokens[0]
            return .init(accessToken: t, expiresAt: Date().addingTimeInterval(3600), subscriptionType: "max")
        }
    }

    func testKeychainIsReadOnceAcrossPolls() async throws {
        let reader = Reader(["a"])
        let p = OAuthUsageProvider(session: session, credentials: { try reader.read() })
        MockURLProtocol.responses = [(200, [:], ok), (200, [:], ok), (200, [:], ok)]
        for _ in 0..<3 { _ = try await p.fetch() }
        XCTAssertEqual(reader.calls, 1)
        XCTAssertEqual(MockURLProtocol.seenTokens, ["Bearer a", "Bearer a", "Bearer a"])
    }

    func testUnauthorizedRereadsOnceWithTheNewToken() async throws {
        let reader = Reader(["old", "new"])
        let p = OAuthUsageProvider(session: session, credentials: { try reader.read() })
        MockURLProtocol.responses = [(401, [:], ""), (200, [:], ok)]
        let s = try await p.fetch()
        XCTAssertEqual(s.session?.utilization, 40)
        XCTAssertEqual(s.plan, "max")
        XCTAssertEqual(reader.calls, 2)
        XCTAssertEqual(MockURLProtocol.seenTokens, ["Bearer old", "Bearer new"])
    }

    func testUnauthorizedWithSameTokenStopsInsteadOfLooping() async {
        let reader = Reader(["same"])
        let p = OAuthUsageProvider(session: session, credentials: { try reader.read() })
        MockURLProtocol.responses = [(401, [:], ""), (401, [:], "")]
        do {
            _ = try await p.fetch()
            XCTFail("expected tokenExpired")
        } catch {
            XCTAssertEqual(error as? ProviderError, .tokenExpired)
        }
        XCTAssertEqual(reader.calls, 2)
        XCTAssertEqual(MockURLProtocol.seenTokens.count, 1)
    }

    func testRateLimitCarriesRetryAfter() async {
        let p = OAuthUsageProvider(session: session, credentials: { .init(accessToken: "a", expiresAt: nil, subscriptionType: nil) })
        MockURLProtocol.responses = [(429, ["Retry-After": "120"], "")]
        do {
            _ = try await p.fetch()
            XCTFail("expected rateLimited")
        } catch {
            XCTAssertEqual(error as? ProviderError, .rateLimited(retryAfter: 120))
        }
    }
}

// MARK: - App state

final class StubProvider: UsageProvider {
    let kind: UsageSource
    var results: [Result<UsageSnapshot, Error>]
    var calls = 0
    init(kind: UsageSource = .oauth, _ results: [Result<UsageSnapshot, Error>]) { self.kind = kind; self.results = results }
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        return try (results.count > 1 ? results.removeFirst() : results[0]).get()
    }
}

@MainActor
final class AppStateSyncTests: XCTestCase {
    func makeApp(_ provider: StubProvider) -> AppState {
        let defaults = scratchDefaults()
        return AppState(settings: Settings(defaults: defaults), autoPoll: false, provider: provider)
    }

    func snapshot() -> UsageSnapshot {
        var s = UsageSnapshot.empty(source: .oauth)
        s.session = LimitWindow(utilization: 40, resetsAt: Date().addingTimeInterval(3600))
        s.week = LimitWindow(utilization: 20, resetsAt: Date().addingTimeInterval(86400))
        return s
    }

    func testFailureThatNeedsTheUserStopsRetrying() async {
        let declined = ProviderError.keychainUnavailable("access was declined")
        let stub = StubProvider([.failure(declined)])
        let app = makeApp(stub)
        await app.refresh()
        XCTAssertEqual(app.status, .failed(declined.localizedDescription, retryAt: nil))
        XCTAssertEqual(app.nextDelay, .infinity)
    }

    func testExpiredSignInIsRecheckedQuietly() async {
        let stub = StubProvider([.failure(ProviderError.tokenExpired)])
        let app = makeApp(stub)
        await app.refresh()
        guard case .failed(_, let retryAt?) = app.status else { return XCTFail("expected a scheduled re-check") }
        XCTAssertEqual(retryAt.timeIntervalSinceNow, SyncPolicy.signInRecheck, accuracy: 5)
    }

    func testExpiredSignInIsRecheckedWhenThePanelOpens() async throws {
        let stub = StubProvider([.failure(ProviderError.tokenExpired), .success(snapshot())])
        let app = makeApp(stub)
        await app.refresh()
        try await Task.sleep(nanoseconds: 5_200_000_000)   // past the 5 s re-check throttle
        app.panelDidOpen()
        await waitUntil("the re-check to succeed") { app.status == .live }
        XCTAssertEqual(stub.calls, 2)
    }

    func testOfflineRetriesSoonWithoutEscalating() async {
        let stub = StubProvider([.failure(ProviderError.offline)])
        let app = makeApp(stub)
        for _ in 0..<4 { await app.refresh() }
        guard case .failed(_, let retryAt?) = app.status else { return XCTFail() }
        XCTAssertEqual(retryAt.timeIntervalSinceNow, SyncPolicy.offlineRetry, accuracy: 5)
    }

    func testTransientFailureBacksOffAndKeepsTheLastNumbers() async {
        let stub = StubProvider([.success(snapshot()), .failure(ProviderError.http(500))])
        let app = makeApp(stub)
        await app.refresh()
        await app.refresh()
        XCTAssertNotNil(app.snapshot, "numbers stay on screen through a failed poll")
        guard case .failed(_, let retryAt?) = app.status else { return XCTFail("expected a scheduled retry") }
        XCTAssertGreaterThan(retryAt.timeIntervalSinceNow, 250)
    }

    func testWaitingIsNotAFailure() async {
        let stub = StubProvider(kind: .statusLine, [.failure(ProviderError.noData("send a message"))])
        let app = makeApp(stub)
        await app.refresh()
        XCTAssertEqual(app.status, .waiting("send a message"))
        XCTAssertEqual(app.nextDelay, 15)
    }

    func testOpeningThePanelDoesNotRefetchRightAway() async throws {
        let stub = StubProvider([.success(snapshot())])
        let app = makeApp(stub)
        await app.refresh()
        app.panelDidOpen()
        app.panelDidOpen()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(stub.calls, 1)
    }

    func testOpeningThePanelDoesNotRetryAFailure() async throws {
        let stub = StubProvider([.failure(ProviderError.tokenExpired)])
        let app = makeApp(stub)
        await app.refresh()
        for _ in 0..<5 { app.panelDidOpen() }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(stub.calls, 1)
    }
}

// MARK: - Races, rate limits, toasts, clock events

final class SlowProvider: UsageProvider {
    let kind: UsageSource = .oauth
    var calls = 0
    var result: Result<UsageSnapshot, Error>
    init(_ result: Result<UsageSnapshot, Error>) { self.result = result }
    func fetch() async throws -> UsageSnapshot {
        calls += 1
        try await Task.sleep(nanoseconds: 300_000_000)
        return try result.get()
    }
}

@MainActor
final class AppStateRaceTests: XCTestCase {
    func snapshot(sessionResetsIn: TimeInterval = 3600, used: Double = 40) -> UsageSnapshot {
        var s = UsageSnapshot.empty(source: .oauth)
        s.session = LimitWindow(utilization: used, resetsAt: Date().addingTimeInterval(sessionResetsIn))
        s.week = LimitWindow(utilization: 20, resetsAt: Date().addingTimeInterval(86400))
        return s
    }

    func testRetryDuringAFetchDoesNotCancelItOrFakeAFailure() async throws {
        let slow = SlowProvider(.success(snapshot()))
        let app = AppState(settings: Settings(defaults: scratchDefaults()), autoPoll: false, provider: slow)
        let first = Task { await app.refresh() }
        try await Task.sleep(nanoseconds: 50_000_000)
        for _ in 0..<5 { app.retryNow() }          // hammering Retry mid-flight
        await first.value
        XCTAssertEqual(app.status, .live)
        XCTAssertNotNil(app.snapshot)
    }

    func testRateLimitIsRespectedByRetry() async {
        let stub = StubProvider([.failure(ProviderError.rateLimited(retryAfter: 600)), .success(snapshot())])
        let app = AppState(settings: Settings(defaults: scratchDefaults()), autoPoll: false, provider: stub)
        await app.refresh()
        app.retryNow()
        await app.refresh()
        XCTAssertEqual(stub.calls, 1, "no request before Retry-After")
        guard case .failed(_, let retryAt?) = app.status else { return XCTFail() }
        XCTAssertGreaterThan(retryAt.timeIntervalSinceNow, 590)
    }

    func testSecondToastSurvivesTheFirstOnesTimer() async throws {
        let app = AppState(settings: Settings(defaults: scratchDefaults()), autoPoll: false, provider: StubProvider([.success(snapshot())]))
        app.showToast(title: "one", body: "")
        app.showToast(title: "two", body: "")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(app.toast?.title, "two")
    }

    func testSessionResetFromDataThenSameWindowAgainNotifiesOnce() async {
        let defaults = scratchDefaults()
        let settings = Settings(defaults: defaults)
        let ended = snapshot(sessionResetsIn: -60, used: 100)
        let fresh = snapshot(sessionResetsIn: 18000, used: 2)
        let stub = StubProvider([.success(ended), .success(fresh), .success(ended), .success(fresh)])
        let app = AppState(settings: settings, autoPoll: false, provider: stub)
        for _ in 0..<4 { await app.refresh() }
        XCTAssertNotNil(settings.eventGate.sessionReset)
        XCTAssertEqual(settings.eventGate.sessionReset?.key?.timeIntervalSince1970 ?? 0,
                       ended.session!.resetsAt!.timeIntervalSince1970, accuracy: 1)
    }
}

// MARK: - Keychain tool timeout

final class KeychainTimeoutTests: XCTestCase {
    func testHangingToolIsKilledAndReportedWithinTheTimeout() throws {
        let saved = ClaudeKeychain.tool
        defer { ClaudeKeychain.tool = saved }
        let stub = FileManager.default.temporaryDirectory.appendingPathComponent("pace-hang-\(UUID().uuidString).sh")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
        defer { try? FileManager.default.removeItem(at: stub) }
        ClaudeKeychain.tool = stub

        let start = Date()
        XCTAssertThrowsError(try ClaudeKeychain.readBlocking(timeout: 1)) { error in
            guard case ProviderError.keychainUnavailable = error else { return XCTFail("\(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 8, "far less than the 30 s the tool would have taken")
    }

    func testLargeOutputDoesNotDeadlock() throws {
        let saved = ClaudeKeychain.tool
        defer { ClaudeKeychain.tool = saved }
        let stub = FileManager.default.temporaryDirectory.appendingPathComponent("pace-big-\(UUID().uuidString).sh")
        // 1 MB of JSON on stdout and noise on stderr, more than a pipe buffer holds.
        try """
        #!/bin/sh
        /usr/bin/python3 -c 'import sys,json; sys.stderr.write("x"*200000); print(json.dumps({"claudeAiOauth":{"accessToken":"t","pad":"a"*1000000}}))'
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: stub.path)
        defer { try? FileManager.default.removeItem(at: stub) }
        ClaudeKeychain.tool = stub
        XCTAssertEqual(try ClaudeKeychain.readBlocking(timeout: 10).accessToken, "t")
    }
}
