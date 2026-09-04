import Foundation
import Testing
@testable import WakaCore

/// Regressions for two defects the analytics cache shipped with.
///
/// Both were silent: neither threw, neither logged, and both produced a screen that
/// looked completely normal while showing the wrong thing.
@Suite("Cache keying")
struct CacheKeyingTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func temporaryCache() -> (JSONCache<CachedActivity>, URL) {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (JSONCache(fileURL: url, version: AnalyticsRepository.cacheSchemaVersion), url)
    }

    private func range(days: Int) -> ActivityRange {
        ActivityRange(start: now.addingTimeInterval(-Double(days) * 86_400), end: now, timeZone: .gmt)
    }

    /// A client whose every request fails, so anything returned came from the cache.
    private func failingClient() -> WakaTimeClient {
        let response = HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        return immediateClient(http: StubHTTPClient(result: .success((Data(), response))))
    }

    @Test("a cache written for one period is not served for another")
    func periodSwitchDoesNotServeTheWrongPeriod() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let week = range(days: 6)
        let quarter = range(days: 89)
        try await cache.store(
            CachedActivity(rangeKey: week.cacheKey, days: [ActivityDay(date: now, duration: 3_600)]),
            writtenAt: now
        )
        let repository = AnalyticsRepository(client: failingClient(), cache: cache, now: { self.now })

        // The seven-day question has a cached answer and is served from it.
        let served = try await repository.days(range: week, credential: .personalAPIKey("k"), timeZone: .gmt)
        #expect(served.days.count == 1)

        // The ninety-day question does not, and must fail rather than hand back the
        // seven-day answer relabelled. Before the cache carried its range, this
        // returned one day and the UI captioned it "Last 3 months".
        await #expect(throws: WakaTimeError.serviceUnavailable) {
            _ = try await repository.days(range: quarter, credential: .personalAPIKey("k"), timeZone: .gmt)
        }
    }

    @Test("the same period is still served from cache within the freshness window")
    func matchingPeriodIsStillCached() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let week = range(days: 6)
        try await cache.store(
            CachedActivity(rangeKey: week.cacheKey, days: [ActivityDay(date: now, duration: 60)]),
            writtenAt: now
        )
        let repository = AnalyticsRepository(client: failingClient(), cache: cache, now: { self.now })
        let result = try await repository.days(range: week, credential: .personalAPIKey("k"), timeZone: .gmt)
        #expect(result.isStale == false)
        #expect(result.days.first?.duration == 60)
    }

    @Test("the key distinguishes two periods that share a start date")
    func keyIsNotAmbiguous() {
        #expect(range(days: 6).cacheKey != range(days: 89).cacheKey)
        #expect(range(days: 6).cacheKey == range(days: 6).cacheKey)
        // Two identical spans in different zones are different questions, because the
        // day boundaries they aggregate over are different.
        let gmt = ActivityRange(start: now, end: now, timeZone: .gmt)
        let tokyo = ActivityRange(start: now, end: now, timeZone: TimeZone(identifier: "Asia/Tokyo") ?? .gmt)
        #expect(gmt.cacheKey != tokyo.cacheKey)
    }

    @Test("a stored cache can be read back on this platform")
    func cacheIsReadableAfterWriting() async throws {
        // Not a tautology. The cache was written with a data-protection class this
        // build is not entitled to use, so on macOS every write succeeded and every
        // subsequent read failed with EPERM — the offline fallback could never fire,
        // and nothing in the suite noticed because no test read a file back after
        // writing it. This is that test.
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let stored = CachedActivity(rangeKey: "k", days: [ActivityDay(date: now, duration: 42)])
        try await cache.store(stored, writtenAt: now)
        let loaded = try await cache.load(now: now, maximumAge: 60)
        #expect(loaded?.value == stored)
        #expect(loaded?.isFresh == true)
    }
}
