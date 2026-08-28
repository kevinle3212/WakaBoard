import Foundation
import Testing
@testable import WakaCore

@Suite("Retention")
struct RetentionTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func temporaryCache() -> (JSONCache<[ActivityDay]>, URL) {
        let url = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (JSONCache(fileURL: url), url)
    }

    /// Builds a day `daysAgo` before the fixed clock.
    private func day(daysAgo: Double, duration: TimeInterval = 3_600) -> ActivityDay {
        ActivityDay(date: now.addingTimeInterval(-daysAgo * 86_400), duration: duration)
    }

    @Test("the published window matches what the code enforces")
    func policyMatchesDocumentation() {
        // RETENTION.md quotes these numbers. A policy nothing enforces is not a policy,
        // so if these change the document must change in the same commit.
        #expect(RetentionPolicy.cachedActivity == 90 * 24 * 60 * 60)
        #expect(RetentionPolicy.widgetSnapshot == 7 * 24 * 60 * 60)
        #expect(RetentionPolicy.cacheFreshness == 300)
    }

    @Test("days past the retention window are dropped from a served cache")
    func prunesOnRead() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let recent = day(daysAgo: 1)
        let expired = day(daysAgo: 200)
        try await cache.store([expired, recent], writtenAt: now)

        let repository = AnalyticsRepository(
            client: immediateClient(http: StubHTTPClient(result: .success((Data(), HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!)))),
            cache: cache,
            now: { self.now }
        )
        let range = ActivityRange(start: now, end: now, timeZone: .gmt)
        let result = try await repository.days(range: range, credential: .personalAPIKey("k"), timeZone: .gmt)
        #expect(result.days.count == 1)
        #expect(result.days.first?.date == recent.date)
    }

    @Test("days past the retention window are never written back to disk")
    func prunesOnWrite() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let body = """
        {"data":[
          {"range":{"date":"2020-01-01"},"grand_total":{"total_seconds":3600},"projects":[],"languages":[]},
          {"range":{"date":"2027-01-14"},"grand_total":{"total_seconds":3600},"projects":[],"languages":[]}
        ]}
        """
        let response = HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let repository = AnalyticsRepository(
            client: immediateClient(http: StubHTTPClient(result: .success((Data(body.utf8), response)))),
            cache: cache,
            now: { self.now }
        )
        let range = ActivityRange(start: now, end: now, timeZone: .gmt)
        let result = try await repository.days(range: range, credential: .personalAPIKey("k"), timeZone: .gmt)
        // 2020-01-01 is far outside the 90-day window; 2027-01-14 is within it.
        #expect(result.days.count == 1)

        let persisted = try await cache.load(now: now, maximumAge: 10_000)
        #expect(persisted?.value.count == 1)
    }

    @Test("an entirely expired cache is treated as absent, not as stale data")
    func fullyExpiredCacheIsNotServed() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        try await cache.store([day(daysAgo: 500)], writtenAt: now)
        let response = HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let repository = AnalyticsRepository(
            client: immediateClient(http: StubHTTPClient(result: .success((Data(), response)))),
            cache: cache,
            now: { self.now }
        )
        let range = ActivityRange(start: now, end: now, timeZone: .gmt)
        // Nothing retained means nothing to fall back on: the failure must surface
        // rather than the app presenting year-old numbers as "saved data".
        await #expect(throws: WakaTimeError.serviceUnavailable) {
            _ = try await repository.days(range: range, credential: .personalAPIKey("k"), timeZone: .gmt)
        }
    }

    @Test("clearing the cache removes the file")
    func clearRemovesFile() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        try await cache.store([day(daysAgo: 1)], writtenAt: now)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let repository = AnalyticsRepository(client: immediateClient(http: StubHTTPClient(result: .success((Data(), HTTPURLResponse())))), cache: cache, now: { self.now })
        try await repository.clearCache()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a widget snapshot past its window is discarded rather than shown")
    func widgetSnapshotExpires() throws {
        let suite = "test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = WidgetSnapshotStore(suiteName: suite)

        let fresh = WidgetSnapshot(generatedAt: now, todayDuration: 60, weekDuration: 120, topProject: "A")
        try store.store(fresh)
        #expect(store.load(now: now.addingTimeInterval(60)) != nil)
        // A widget showing a two-week-old figure as if current is the failure here.
        #expect(store.load(now: now.addingTimeInterval(RetentionPolicy.widgetSnapshot + 1)) == nil)
        // And the expired value is erased, not merely hidden.
        #expect(store.load(now: now) == nil)
    }

    @Test("sign-out erases the credential, the cache, and the widget snapshot")
    func signOutErasesEverything() async throws {
        let (cache, url) = temporaryCache()
        defer { try? FileManager.default.removeItem(at: url) }
        let suite = "test.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let credentials = InMemoryCredentialStore(seeded: .personalAPIKey("secret"))
        let snapshots = WidgetSnapshotStore(suiteName: suite)
        try snapshots.store(WidgetSnapshot(generatedAt: now, todayDuration: 60, weekDuration: 60, topProject: "A"))
        try await cache.store([day(daysAgo: 1)], writtenAt: now)

        let environment = WakaEnvironment(
            repository: AnalyticsRepository(client: immediateClient(http: StubHTTPClient(result: .success((Data(), HTTPURLResponse())))), cache: cache, now: { self.now }),
            client: immediateClient(http: StubHTTPClient(result: .success((Data(), HTTPURLResponse())))),
            credentials: credentials,
            snapshots: snapshots
        )

        try await environment.signOut()

        #expect(try credentials.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(snapshots.load(now: now) == nil)
    }
}
