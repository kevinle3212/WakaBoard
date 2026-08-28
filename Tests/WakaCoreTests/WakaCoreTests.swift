import Foundation
import Testing
@testable import WakaCore

private struct StubHTTPClient: HTTPClient {
    let result: Result<(Data, HTTPURLResponse), Error>
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { try result.get() }
}

private actor Counter { var value = 0; func increment() { value += 1 }; func get() -> Int { value } }

private actor TrackingHTTPClient: HTTPClient {
    let result: Result<(Data, HTTPURLResponse), Error>
    private var calls = 0
    init(result: Result<(Data, HTTPURLResponse), Error>) { self.result = result }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { calls += 1; return try result.get() }
    func callCount() -> Int { calls }
}

@Test("analytics avoids fabricated percentage and calculates consistency")
func analyticsFormulas() {
    #expect(AnalyticsEngine.percentageChange(current: 20, previous: 0) == nil)
    #expect(AnalyticsEngine.percentageChange(current: 20, previous: 10) == 100)
    #expect(AnalyticsEngine.consistency([60, 60]) == 100)
    #expect(AnalyticsEngine.consistency([0, 0]) == nil)
}

@Test("range query uses calendar days across DST")
func dateRangeDST() {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let formatter = ISO8601DateFormatter()
    let start = formatter.date(from: "2025-03-09T08:00:00Z")!
    let end = formatter.date(from: "2025-03-11T07:00:00Z")!
    let range = ActivityRange(start: start, end: end, timeZone: zone)
    #expect(range.queryDates().start == "2025-03-09")
    #expect(range.calendarDayCount() == 3)
}

@Test("duration and deep links are stable and allowlisted")
func presentationContracts() {
    #expect(DurationFormatter().string(3_661) == "1h 1m")
    let link = DeepLink.overview.url(scheme: "wakaboard")
    #expect(DeepLink(url: link, scheme: "wakaboard") == .overview)
    #expect(DeepLink(url: URL(string: "wakaboard://open/untrusted?next=settings")!, scheme: "wakaboard") == nil)
}

@Test("widget snapshots carry aggregates but cannot encode credentials")
func widgetSnapshotPrivacy() throws {
    let snapshot = WidgetSnapshot(generatedAt: .now, todayDuration: 3_600, weekDuration: 7_200, topProject: "Example API")
    let encoded = try JSONEncoder().encode(snapshot)
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(!text.localizedCaseInsensitiveContains("authorization"))
    #expect(!text.localizedCaseInsensitiveContains("token"))
    #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: encoded) == snapshot)
}

@Test("endpoint rejects unsafe host and maps HTTP status safely")
func endpointAndStatus() async throws {
    #expect(throws: WakaTimeError.invalidEndpoint) { try WakaTimeEndpoint.projects.request(baseURL: URL(string: "http://example.com")!, authorization: "key") }
    let response = HTTPURLResponse(url: URL(string: "https://wakatime.com")!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "12"])!
    let client = WakaTimeClient(http: StubHTTPClient(result: .success((Data(), response))) )
    let range = ActivityRange(start: .now, end: .now, timeZone: .gmt)
    await #expect(throws: WakaTimeError.rateLimited(retryAfter: 12)) { try await client.summaries(range: range, authorization: "key", timeZone: .gmt) }
    for (status, expected) in [(401, WakaTimeError.unauthenticated), (403, .forbidden), (404, .unavailable), (500, .serviceUnavailable)] {
        let response = HTTPURLResponse(url: URL(string: "https://wakatime.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        let statusClient = WakaTimeClient(http: StubHTTPClient(result: .success((Data(), response))))
        await #expect(throws: expected) { try await statusClient.summaries(range: range, authorization: "key", timeZone: .gmt) }
    }
}

@Test("client maps malformed JSON to decoding")
func decodingFailure() async {
    let response = HTTPURLResponse(url: URL(string: "https://wakatime.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    let client = WakaTimeClient(http: StubHTTPClient(result: .success((Data("bad".utf8), response))))
    let range = ActivityRange(start: .now, end: .now, timeZone: .gmt)
    await #expect(throws: WakaTimeError.decoding) { try await client.summaries(range: range, authorization: "key", timeZone: .gmt) }
}

@Test("cache distinguishes expiry and corruption")
func cacheExpiryAndCorruption() async throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let cache = JSONCache<[ActivityDay]>(fileURL: url)
    try await cache.store([], writtenAt: Date(timeIntervalSince1970: 0))
    let cached = try await cache.load(now: Date(timeIntervalSince1970: 10), maximumAge: 5)
    #expect(cached?.isFresh == false)
    try Data("not json".utf8).write(to: url)
    await #expect(throws: CacheError.corrupt) { try await cache.load(maximumAge: 5) }
}

@Test("OAuth callback requires exact one-time state and route")
func callbackValidation() async throws {
    let session = OAuthSession(state: "expected", callbackScheme: "wakaboard", callbackHost: "oauth", callbackPath: "/callback")
    #expect(try session.validate(callback: URL(string: "wakaboard://oauth/callback?code=abc&state=expected")!) == "abc")
    #expect(throws: OAuthError.invalidCallback) { try session.validate(callback: URL(string: "wakaboard://oauth/other?code=abc&state=expected")!) }
    #expect(throws: OAuthError.invalidCallback) { try session.validate(callback: URL(string: "wakaboard://oauth/callback?code=abc&state=replay")!) }
    #expect(throws: OAuthError.invalidCallback) { try session.validate(callback: URL(string: "wakaboard://oauth/callback?code=abc&state=expected&state=duplicate")!) }
    let validator = OAuthCallbackValidator()
    await validator.begin(session)
    let valid = URL(string: "wakaboard://oauth/callback?code=abc&state=expected")!
    #expect(try await validator.consume(callback: valid) == "abc")
    await #expect(throws: OAuthError.invalidCallback) { try await validator.consume(callback: valid) }
}

@Test("request coalescer runs matching work once")
func requestCoalescing() async throws {
    let coalescer = RequestCoalescer<String, Int>()
    let counter = Counter()
    async let first = coalescer.value(for: "same") { await counter.increment(); try await Task.sleep(for: .milliseconds(20)); return 7 }
    async let second = coalescer.value(for: "same") { await counter.increment(); return 8 }
    #expect(try await first == 7)
    #expect(try await second == 7)
    #expect(await counter.get() == 1)
}

@Test("repository prefers fresh cache and serves stale values offline")
func repositoryCachePolicy() async throws {
    let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let days = [ActivityDay(date: now, duration: 900)]
    let cache = JSONCache<[ActivityDay]>(fileURL: url)
    try await cache.store(days, writtenAt: now)
    let response = HTTPURLResponse(url: URL(string: "https://wakatime.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
    let network = TrackingHTTPClient(result: .success((Data(), response)))
    let repository = AnalyticsRepository(client: WakaTimeClient(http: network), cache: cache, now: { now })
    let range = ActivityRange(start: now, end: now, timeZone: .gmt)
    let fresh = try await repository.days(range: range, credentials: Credentials(authorization: "key"), timeZone: .gmt)
    #expect(fresh.days == days && !fresh.isStale)
    #expect(await network.callCount() == 0)
    let staleRepository = AnalyticsRepository(client: WakaTimeClient(http: network), cache: cache, now: { now.addingTimeInterval(1) })
    let stale = try await staleRepository.days(range: range, credentials: Credentials(authorization: "key"), timeZone: .gmt, maximumAge: 0)
    #expect(stale.days == days && stale.isStale)
    #expect(await network.callCount() == 1)
}
