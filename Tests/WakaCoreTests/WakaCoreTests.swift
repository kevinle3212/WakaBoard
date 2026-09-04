import Foundation
import Testing
@testable import WakaCore

/// Returns a fixed result for every request.
struct StubHTTPClient: HTTPClient {
    let result: Result<(Data, HTTPURLResponse), any Error>
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { try result.get() }
}

private actor Counter {
    var value = 0
    func increment() { value += 1 }
    func get() -> Int { value }
}

/// A client with the limiter and backoff neutralised, for tests about something else.
func immediateClient(http: any HTTPClient) -> WakaTimeClient {
    WakaTimeClient(
        http: http,
        bucket: TokenBucket(capacity: 1_000, refillPerSecond: 1_000, sleep: { _ in }),
        retryPolicy: .none,
        sleep: { _ in },
        jitter: { 1 }
    )
}

@Suite("Analytics")
struct AnalyticsTests {
    @Test("avoids fabricated percentages and scores consistency")
    func formulas() {
        #expect(AnalyticsEngine.percentageChange(current: 20, previous: 0) == nil)
        #expect(AnalyticsEngine.percentageChange(current: 20, previous: nil) == nil)
        #expect(AnalyticsEngine.percentageChange(current: 20, previous: 10) == 100)
        #expect(AnalyticsEngine.consistency([60, 60]) == 100)
        #expect(AnalyticsEngine.consistency([0, 0]) == nil)
        #expect(AnalyticsEngine.consistency([60]) == nil)
    }

    @Test("aggregation sums duplicate buckets")
    func aggregation() {
        let merged = AnalyticsEngine.aggregate([
            Usage(name: "A", duration: 100),
            Usage(name: "A", duration: 50),
            Usage(name: "B", duration: 25)
        ])
        #expect(merged.first { $0.name == "A" }?.duration == 150)
        #expect(merged.first { $0.name == "B" }?.duration == 25)
    }
}

@Suite("DateRanges")
struct DateRangeTests {
    @Test("query uses calendar days across a DST transition")
    func dstSafe() {
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        let formatter = ISO8601DateFormatter()
        let start = formatter.date(from: "2025-03-09T08:00:00Z")!
        let end = formatter.date(from: "2025-03-11T07:00:00Z")!
        let range = ActivityRange(start: start, end: end, timeZone: zone)
        #expect(range.queryDates().start == "2025-03-09")
        // Three calendar days, even though only 47 wall-clock hours elapsed.
        #expect(range.calendarDayCount() == 3)
    }
}

@Suite("DeepLinks")
struct DeepLinkTests {
    @Test("round-trips known routes and rejects everything else")
    func allowlist() throws {
        #expect(DurationFormatter().string(1) == "<1m")
        #expect(DurationFormatter().string(3_661) == "1h 1m")
        let link = try #require(DeepLink.overview.url(scheme: "wakaboard"))
        #expect(DeepLink(url: link, scheme: "wakaboard") == .overview)

        // Unknown route, wrong scheme, and query smuggling all fail closed.
        #expect(DeepLink(url: URL(string: "wakaboard://open/untrusted?next=settings")!, scheme: "wakaboard") == nil)
        #expect(DeepLink(url: URL(string: "wakaboard://open/settings?x=1")!, scheme: "wakaboard") == nil)
        #expect(DeepLink(url: URL(string: "evil://open/settings")!, scheme: "wakaboard") == nil)
        #expect(DeepLink(url: URL(string: "wakaboard://elsewhere/settings")!, scheme: "wakaboard") == nil)
    }

    @Test("every route round-trips, including the ones shipped widgets still use")
    func everyRouteRoundTrips() throws {
        // Enumerated rather than spot-checked: `breakdown` was added after
        // `projects` and `languages`, and those two are live in widgets already
        // installed on somebody's Home Screen. A link that stops resolving sends the
        // user to the wrong screen with no error anywhere.
        for route in [DeepLink.overview, .activity, .breakdown, .projects, .languages, .insights, .settings] {
            let url = try #require(route.url(scheme: "wakaboard"))
            #expect(DeepLink(url: url, scheme: "wakaboard") == route, "\(route) did not round-trip")
        }
    }

    @Test("the older dimension links open the breakdown on their own dimension")
    func legacyLinksCarryTheirDimension() {
        #expect(DeepLink.projects.dimension == .projects)
        #expect(DeepLink.languages.dimension == .languages)
        // Everything else selects the screen without forcing a dimension, so a link
        // cannot silently reset a choice the user already made.
        #expect(DeepLink.breakdown.dimension == nil)
        #expect(DeepLink.overview.dimension == nil)
    }
}

@Suite("WidgetSnapshotPrivacy")
struct WidgetSnapshotTests {
    @Test("snapshots carry aggregates but cannot encode credentials")
    func privacy() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            todayDuration: 3_600,
            weekDuration: 7_200,
            topProject: "Example API",
            dailyDurations: [60, 120]
        )
        let encoded = try JSONEncoder().encode(snapshot)
        let text = try #require(String(data: encoded, encoding: .utf8))
        for forbidden in ["authorization", "token", "apikey", "bearer", "password", "secret"] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: encoded) == snapshot)
    }

    @Test("decodes a snapshot written before the daily series existed")
    func forwardCompatible() throws {
        let legacy = Data(#"{"generatedAt":0,"todayDuration":60,"weekDuration":120,"topProject":"A"}"#.utf8)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: legacy)
        #expect(decoded.dailyDurations.isEmpty)
        #expect(decoded.todayDuration == 60)
    }
}

@Suite("HTTPStatusMapping")
struct HTTPStatusTests {
    @Test("maps every documented status to a distinct recovery state")
    func statuses() async throws {
        let range = ActivityRange(start: .now, end: .now, timeZone: .gmt)
        let cases: [(Int, WakaTimeError)] = [
            (401, .unauthenticated),
            (403, .forbidden),
            (404, .unavailable),
            (418, .transport),
            (500, .serviceUnavailable),
            (503, .serviceUnavailable)
        ]
        for (status, expected) in cases {
            let response = HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
            let client = immediateClient(http: StubHTTPClient(result: .success((Data(), response))))
            await #expect(throws: expected) {
                try await client.summaries(range: range, credential: .personalAPIKey("k"), timeZone: .gmt)
            }
        }
    }

    @Test("maps malformed JSON to a decoding failure")
    func malformedJSON() async {
        let response = HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let client = immediateClient(http: StubHTTPClient(result: .success((Data("bad".utf8), response))))
        let range = ActivityRange(start: .now, end: .now, timeZone: .gmt)
        await #expect(throws: WakaTimeError.decoding) {
            try await client.summaries(range: range, credential: .personalAPIKey("k"), timeZone: .gmt)
        }
    }
}

@Suite("Cache")
struct CacheTests {
    @Test("distinguishes expiry from corruption")
    func expiryAndCorruption() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = JSONCache<CachedActivity>(fileURL: url)
        try await cache.store(CachedActivity(rangeKey: "empty", days: []), writtenAt: Date(timeIntervalSince1970: 0))
        let cached = try await cache.load(now: Date(timeIntervalSince1970: 10), maximumAge: 5)
        #expect(cached?.isFresh == false)
        try Data("not json".utf8).write(to: url)
        await #expect(throws: CacheError.corrupt) { try await cache.load(maximumAge: 5) }
    }

    @Test("rejects a cache written by an incompatible schema version")
    func versionMismatch() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try await JSONCache<CachedActivity>(fileURL: url, version: 1).store(CachedActivity(rangeKey: "empty", days: []))
        let newer = JSONCache<CachedActivity>(fileURL: url, version: 2)
        await #expect(throws: CacheError.unsupportedVersion) { try await newer.load(maximumAge: 60) }
    }

    @Test("cache file is readable only by its owner")
    func filePermissions() async throws {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try await JSONCache<CachedActivity>(fileURL: url).store(CachedActivity(rangeKey: "empty", days: []))
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        // A user's coding history must not be world-readable on a shared Mac.
        #expect(mode?.int16Value == 0o600)
    }
}

@Suite("OAuthCallback")
struct OAuthTests {
    @Test("requires an exact one-time state and route")
    func callbackValidation() async throws {
        let session = OAuthSession(state: "expected", callbackScheme: "wakaboard", callbackHost: "oauth", callbackPath: "/callback")
        #expect(try session.validate(callback: URL(string: "wakaboard://oauth/callback?code=abc&state=expected")!) == "abc")

        for hostile in [
            "wakaboard://oauth/other?code=abc&state=expected",
            "wakaboard://oauth/callback?code=abc&state=replay",
            "wakaboard://oauth/callback?code=abc&state=expected&state=duplicate",
            "wakaboard://oauth/callback?code=&state=expected",
            "https://oauth/callback?code=abc&state=expected"
        ] {
            #expect(throws: OAuthError.invalidCallback) {
                try session.validate(callback: URL(string: hostile)!)
            }
        }
    }

    @Test("a pending session is consumed exactly once")
    func replayRejected() async throws {
        let validator = OAuthCallbackValidator()
        let session = OAuthSession(state: "expected", callbackScheme: "wakaboard", callbackHost: "oauth", callbackPath: "/callback")
        await validator.begin(session)
        let valid = URL(string: "wakaboard://oauth/callback?code=abc&state=expected")!
        #expect(try await validator.consume(callback: valid) == "abc")
        await #expect(throws: OAuthError.invalidCallback) { try await validator.consume(callback: valid) }
    }

    @Test("a failed callback still burns the pending session")
    func failureBurnsSession() async throws {
        let validator = OAuthCallbackValidator()
        await validator.begin(OAuthSession(state: "expected", callbackScheme: "wakaboard", callbackHost: "oauth", callbackPath: "/callback"))
        // Probing with a wrong state must not leave the session available to guess again.
        await #expect(throws: OAuthError.invalidCallback) {
            try await validator.consume(callback: URL(string: "wakaboard://oauth/callback?code=abc&state=wrong")!)
        }
        await #expect(throws: OAuthError.invalidCallback) {
            try await validator.consume(callback: URL(string: "wakaboard://oauth/callback?code=abc&state=expected")!)
        }
    }
}

@Suite("Coalescing")
struct CoalescingTests {
    @Test("matching work runs once")
    func coalesces() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let counter = Counter()
        async let first = coalescer.value(for: "same") {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(20))
            return 7
        }
        async let second = coalescer.value(for: "same") {
            await counter.increment()
            return 8
        }
        #expect(try await first == 7)
        #expect(try await second == 7)
        #expect(await counter.get() == 1)
    }
}
