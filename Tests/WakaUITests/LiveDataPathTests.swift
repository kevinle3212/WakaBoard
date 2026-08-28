import Foundation
import Testing
import WakaCore
@testable import WakaUI

/// Returns a canned HTTP result for every request.
private struct StubHTTPClient: HTTPClient {
    let status: Int
    let body: Data
    let headers: [String: String]?

    init(status: Int = 200, json: String = #"{"data":[]}"#, headers: [String: String]? = nil) {
        self.status = status
        self.body = Data(json.utf8)
        self.headers = headers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        return (body, response)
    }
}

/// Builds an environment with no real network, Keychain, or timing.
@MainActor
private func makeEnvironment(
    http: any HTTPClient,
    credential: Credential? = .personalAPIKey("test-key"),
    credentialFailure: KeychainError? = nil,
    cacheURL: URL
) -> (WakaEnvironment, WidgetSnapshotStore, String) {
    let client = WakaTimeClient(
        http: http,
        bucket: TokenBucket(capacity: 1_000, refillPerSecond: 1_000, sleep: { _ in }),
        retryPolicy: .none,
        sleep: { _ in },
        jitter: { 1 }
    )
    let suite = "test.\(UUID().uuidString)"
    let snapshots = WidgetSnapshotStore(suiteName: suite)
    let environment = WakaEnvironment(
        repository: AnalyticsRepository(client: client, cache: JSONCache(fileURL: cacheURL), now: { fixedNow }),
        client: client,
        credentials: InMemoryCredentialStore(seeded: credential, failure: credentialFailure),
        snapshots: snapshots
    )
    return (environment, snapshots, suite)
}

/// The fixed clock every test in this file reads. Declared at file scope so the
/// `@Sendable` closures the model takes can capture it without actor isolation.
private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// A day of activity dated relative to the model's clock, so ranges line up.
private func summariesJSON(dates: [String], seconds: [Double], project: String = "Orbit") -> String {
    let entries = zip(dates, seconds).map { date, value in
        """
        {"range":{"date":"\(date)"},"grand_total":{"total_seconds":\(value)},
         "projects":[{"name":"\(project)","total_seconds":\(value)}],
         "languages":[{"name":"Swift","total_seconds":\(value)}]}
        """
    }
    return "{\"data\":[\(entries.joined(separator: ","))]}"
}

@Suite("LiveDataPath")
@MainActor
struct LiveDataPathTests {
    private func temporaryURL() -> URL {
        URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("the model loads real analytics instead of a fixture")
    func loadsRealData() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // 2027-01-15 is the day `now` falls on in GMT.
        let json = summariesJSON(dates: ["2027-01-15"], seconds: [7_200])
        let (environment, _, suite) = makeEnvironment(http: StubHTTPClient(json: json), cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.refresh()

        #expect(model.state == .loaded)
        #expect(model.days.count == 1)
        #expect(model.days.first?.duration == 7_200)
        // The numbers come from the response, not from `WakaDashboard.fixture`.
        #expect(model.projects.first?.name == "Orbit")
        #expect(model.languages.first?.name == "Swift")
        #expect(model.overview?.total == 7_200)
    }

    @Test("no stored credential means the sign-in screen, not empty analytics")
    func signedOutState() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (environment, _, suite) = makeEnvironment(http: StubHTTPClient(), credential: nil, cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.start()

        #expect(model.state == .signedOut)
        #expect(!model.isSignedIn)
        #expect(model.days.isEmpty)
    }

    @Test("a rejected key surfaces as expired, not as a generic failure")
    func expiredCredential() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (environment, _, suite) = makeEnvironment(http: StubHTTPClient(status: 401), cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.refresh()

        #expect(model.state == .expired)
    }

    @Test("a rate-limited refresh keeps cached data and says so")
    func rateLimitedState() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // Seed a cache so there is something to preserve.
        let cache = JSONCache<[ActivityDay]>(fileURL: url)
        try await cache.store([ActivityDay(date: fixedNow, duration: 3_600)], writtenAt: fixedNow.addingTimeInterval(-10_000))

        let (environment, _, suite) = makeEnvironment(
            http: StubHTTPClient(status: 429, headers: ["Retry-After": "30"]),
            cacheURL: url
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.refresh()

        // The repository serves the stale cache, so the user still sees their data
        // and is told it is not current.
        #expect(model.state == .stale(reason: "Showing your last saved data. The most recent refresh did not reach WakaTime."))
        #expect(model.days.count == 1)
    }

    @Test("a successful load publishes the credential-free widget snapshot")
    func publishesWidgetSnapshot() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = summariesJSON(dates: ["2027-01-15"], seconds: [5_400])
        let (environment, snapshots, suite) = makeEnvironment(http: StubHTTPClient(json: json), cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let reloaded = ReloadFlag()
        let model = WakaUIModel(
            environment: environment,
            timeZone: .gmt,
            now: { fixedNow },
            reloadWidgets: { reloaded.mark() }
        )
        await model.refresh()

        // This handoff is what the generated code documented but never performed.
        let snapshot = try #require(snapshots.load(now: fixedNow))
        #expect(snapshot.todayDuration == 5_400)
        #expect(reloaded.wasCalled)
    }

    @Test("an unreadable Keychain is reported as such, not as being signed out")
    func keychainFailureIsDistinct() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (environment, _, suite) = makeEnvironment(
            http: StubHTTPClient(),
            credentialFailure: .interactionNotAllowed,
            cacheURL: url
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.start()

        // Found on real hardware: a `try?` collapsed "Keychain unreadable" into
        // "not signed in", so the user was sent to re-enter a key that would fail to
        // save for the same underlying reason.
        #expect(model.state != .signedOut)
        guard case .credentialUnavailable(let message) = model.state else {
            Issue.record("expected .credentialUnavailable, got \(model.state)")
            return
        }
        #expect(message.contains("Unlock"))
        // Routing still sends the user to the sign-in screen rather than a dashboard
        // of someone else's stale data.
        #expect(!model.isSignedIn)
    }

    @Test("refresh also distinguishes an unreadable Keychain")
    func refreshKeychainFailure() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (environment, _, suite) = makeEnvironment(
            http: StubHTTPClient(),
            credentialFailure: .malformedItem,
            cacheURL: url
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.refresh()

        guard case .credentialUnavailable = model.state else {
            Issue.record("expected .credentialUnavailable, got \(model.state)")
            return
        }
    }

    @Test("a Keychain that cannot store the key says so, and stays on sign-in")
    func signInStorageFailure() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        // The key is accepted by WakaTime (200) but the store rejects it — exactly the
        // shape of the -34018 failure that made Connect appear to do nothing.
        let (environment, _, suite) = makeEnvironment(
            http: StubHTTPClient(),
            credential: nil,
            credentialFailure: .unhandled(status: -34018),
            cacheURL: url
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        model.apiKeyInput = "a-valid-looking-key"
        await model.signIn()

        let message = try #require(model.signInError)
        // The old copy blamed the network for a storage failure.
        #expect(!message.contains("connection"))
        #expect(message.contains("could not save"))
        // Crucially the screen must not flip to the dashboard and back.
        #expect(!model.isSignedIn)
        #expect(model.state == .signedOut)
    }

    @Test("a rejected key reports the rejection without leaving the sign-in screen")
    func signInRejected() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (environment, _, suite) = makeEnvironment(http: StubHTTPClient(status: 401), credential: nil, cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        model.apiKeyInput = "bad-key"
        await model.signIn()

        #expect(model.signInError != nil)
        #expect(!model.isSignedIn)
    }

    @Test("a successful sign-in stores the key, clears the field, and hides it again")
    func signInSuccess() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = summariesJSON(dates: ["2027-01-15"], seconds: [3_600])
        let (environment, _, suite) = makeEnvironment(http: StubHTTPClient(json: json), credential: nil, cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        model.apiKeyInput = "good-key"
        model.isKeyVisible = true
        await model.signIn()

        #expect(model.signInError == nil)
        #expect(model.apiKeyInput.isEmpty)
        // A revealed key must not stay revealed for the next person to open Settings.
        #expect(!model.isKeyVisible)
        #expect(try environment.credentials.load() == .personalAPIKey("good-key"))
        #expect(model.isSignedIn)
    }

    @Test("a key with stray whitespace is trimmed rather than rejected")
    func signInTrimsWhitespace() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (environment, _, suite) = makeEnvironment(http: StubHTTPClient(), credential: nil, cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        // Pasting from a browser commonly picks up a trailing newline.
        model.apiKeyInput = "  waka_key-123\n"
        await model.signIn()

        #expect(try environment.credentials.load() == .personalAPIKey("waka_key-123"))
    }

    @Test("signing out erases everything and returns to the sign-in screen")
    func signOutClearsState() async throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let json = summariesJSON(dates: ["2027-01-15"], seconds: [3_600])
        let (environment, snapshots, suite) = makeEnvironment(http: StubHTTPClient(json: json), cacheURL: url)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { fixedNow }, reloadWidgets: {})
        await model.refresh()
        #expect(!model.days.isEmpty)

        await model.signOut()

        #expect(model.state == .signedOut)
        #expect(model.days.isEmpty)
        #expect(model.overview == nil)
        #expect(model.projects.isEmpty)
        #expect(try environment.credentials.load() == nil)
        #expect(snapshots.load(now: fixedNow) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

/// Records whether the widget reload was requested.
private final class ReloadFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var called = false
    func mark() { lock.withLock { called = true } }
    var wasCalled: Bool { lock.withLock { called } }
}
