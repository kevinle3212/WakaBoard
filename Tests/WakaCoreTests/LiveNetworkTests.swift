import Foundation
import Testing
@testable import WakaCore

/// Opt-in tests that make a **real** HTTPS request to WakaTime.
///
/// Every other test in this suite uses a stub, which means the whole suite could pass
/// while the real host, TLS configuration, endpoint path, or header format was wrong.
/// These close that gap without ever needing a valid credential: an intentionally
/// bogus key must produce a real `401`, and that round trip exercises DNS, TLS 1.2+,
/// the host allowlist, request construction, and status mapping against the live
/// server.
///
/// Disabled by default so the suite stays hermetic, fast, and runnable offline and in
/// CI. Enable with:
///
/// ```sh
/// WAKABOARD_LIVE=1 swift test --filter LiveNetwork
/// ```
@Suite("LiveNetwork", .enabled(if: ProcessInfo.processInfo.environment["WAKABOARD_LIVE"] == "1"))
struct LiveNetworkTests {
    /// A client with real networking but no retry, so one failure is one request.
    private func liveClient() -> WakaTimeClient {
        WakaTimeClient(
            http: URLSessionHTTPClient(),
            bucket: TokenBucket(capacity: 4, refillPerSecond: 1),
            retryPolicy: .none
        )
    }

    @Test("a bogus key is rejected by the real WakaTime API with 401")
    func realUnauthenticated() async throws {
        // Deliberately invalid. This test must never carry a real credential, and
        // there is nothing to leak if its output is pasted into an issue.
        let credential = Credential.personalAPIKey("wakaboard-live-check-invalid-key")
        await #expect(throws: WakaTimeError.unauthenticated) {
            try await liveClient().verifyCredential(credential)
        }
    }

    @Test("the summaries endpoint reaches the real host and is rejected, not misrouted")
    func realSummariesEndpoint() async throws {
        let range = ActivityRange(start: .now.addingTimeInterval(-6 * 86_400), end: .now, timeZone: .current)
        // A 404 or a transport failure here would mean the path or host is wrong;
        // 401 proves the request was understood and only the credential was refused.
        await #expect(throws: WakaTimeError.unauthenticated) {
            _ = try await liveClient().summaries(
                range: range,
                credential: .personalAPIKey("wakaboard-live-check-invalid-key"),
                timeZone: .current
            )
        }
    }

    @Test("the hardened session completes a real TLS handshake with WakaTime")
    func realTLS() async throws {
        let request = try WakaTimeEndpoint.currentUser.request(credential: .personalAPIKey("wakaboard-live-check-invalid-key"))
        let (_, response) = try await URLSessionHTTPClient().data(for: request)
        // Any HTTP response at all proves DNS, TLS 1.2+, and the ephemeral session
        // configuration work against the live host.
        #expect(response.statusCode == 401)
        #expect(response.url?.host == "api.wakatime.com")
    }
}

/// Opt-in tests that use the **real stored credential** to make an authenticated
/// request.
///
/// Separate from ``LiveNetworkTests`` because those need no credential and these do.
/// Nothing here prints a key, a project name, or any other analytic content: the
/// assertions are structural, so the output is safe to paste into an issue.
///
/// ```sh
/// WAKABOARD_LIVE_AUTH=1 swift test --filter LiveAuthenticated
/// ```
@Suite("LiveAuthenticated", .enabled(if: ProcessInfo.processInfo.environment["WAKABOARD_LIVE_AUTH"] == "1"))
struct LiveAuthenticatedTests {
    private func storedCredential() throws -> Credential {
        let store = KeychainCredentialStore(service: WakaIdentifiers.keychainService)
        guard let credential = try store.load() else {
            Issue.record("no stored credential; sign in through the app first")
            throw WakaTimeError.unauthenticated
        }
        return credential
    }

    @Test("the stored credential is accepted by the real WakaTime API")
    func credentialIsAccepted() async throws {
        let client = WakaTimeClient(http: URLSessionHTTPClient(), retryPolicy: .none)
        // A throw here is the whole assertion; nothing about the account is printed.
        try await client.verifyCredential(try storedCredential())
    }

    @Test("a real summaries response decodes into bounded, finite analytics")
    func summariesDecode() async throws {
        let client = WakaTimeClient(http: URLSessionHTTPClient(), retryPolicy: .none)
        let range = ActivityRange(start: .now.addingTimeInterval(-6 * 86_400), end: .now, timeZone: .current)
        let days = try await client.summaries(range: range, credential: try storedCredential(), timeZone: .current)

        // Structure only — never the values themselves.
        #expect(!days.isEmpty, "the API returned no days for the last week")
        #expect(days.count <= ResponseBounds.maximumDays)
        for day in days {
            #expect(day.duration.isFinite)
            #expect(day.duration >= 0)
            #expect(day.duration <= ResponseBounds.maximumDailySeconds)
            for bucket in day.projects + day.languages {
                #expect(bucket.duration.isFinite)
                #expect(bucket.name.count <= ResponseBounds.maximumNameLength)
            }
        }
    }

    @Test("the new dimensions arrive from the real API, bounded")
    func extraDimensionsDecode() async throws {
        let client = WakaTimeClient(http: URLSessionHTTPClient(), retryPolicy: .none)
        let range = ActivityRange(start: .now.addingTimeInterval(-6 * 86_400), end: .now, timeZone: .current)
        let days = try await client.summaries(range: range, credential: try storedCredential(), timeZone: .current)

        // Editors, operating systems, and categories are decoded tolerantly, which
        // means a rename on WakaTime's side would silently produce empty lists rather
        // than an error. This is the check that would notice.
        let active = days.filter { $0.duration > 0 }
        #expect(!active.isEmpty, "the API returned no active days for the last week")
        #expect(active.contains { !$0.editors.isEmpty }, "no day carried an editor")
        #expect(active.contains { !$0.operatingSystems.isEmpty }, "no day carried an operating system")
        #expect(active.contains { !$0.categories.isEmpty }, "no day carried a category")
        for day in days {
            for bucket in day.editors + day.operatingSystems + day.categories {
                #expect(bucket.duration.isFinite)
                #expect(bucket.duration <= ResponseBounds.maximumDailySeconds)
                #expect(bucket.name.count <= ResponseBounds.maximumNameLength)
            }
        }
    }

    @Test("the file-type breakdown reconstructs real durations from real heartbeats")
    func breakdownAgainstLiveAPI() async throws {
        let client = WakaTimeClient(http: URLSessionHTTPClient(), bucket: TokenBucket(capacity: 4, refillPerSecond: 1), retryPolicy: .none)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let yesterday = formatter.string(from: Date.now.addingTimeInterval(-86_400))

        let heartbeats = try await client.heartbeats(day: yesterday, credential: try storedCredential())
        // An account with no activity yesterday returns an empty array, which is a
        // valid response and not a failure — the assertion is about shape, and about
        // the reconstruction never inventing time.
        let attributed = FileTypeBreakdown.attribute(heartbeats)
        #expect(attributed.count == heartbeats.filter { $0.time.isFinite }.count)
        for (_, seconds) in attributed {
            #expect(seconds >= 0)
            #expect(seconds <= FileTypeBreakdown.keystrokeTimeout)
        }
        // A day cannot contain more reconstructed time than a day.
        let total = attributed.reduce(0) { $0 + $1.seconds }
        #expect(total <= ResponseBounds.maximumDailySeconds)

        // Nothing about the account reaches the output: extensions only, no paths.
        for row in FileTypeBreakdown.rows(from: heartbeats, bucket: "Other") {
            #expect(!row.name.contains("/"))
            #expect(row.duration.isFinite && row.duration > 0)
        }
    }

    @Test("a snapshot built from real data carries aggregates and no credential")
    func snapshotFromRealData() async throws {
        let client = WakaTimeClient(http: URLSessionHTTPClient(), retryPolicy: .none)
        let range = ActivityRange(start: .now.addingTimeInterval(-6 * 86_400), end: .now, timeZone: .current)
        let days = try await client.summaries(range: range, credential: try storedCredential(), timeZone: .current)

        let snapshot = WidgetSnapshot(days: days, generatedAt: .now)
        let encoded = try JSONEncoder().encode(snapshot)
        let text = try #require(String(data: encoded, encoding: .utf8))
        for forbidden in ["authorization", "apikey", "bearer", "password", "secret"] {
            #expect(!text.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(snapshot.dailyDurations.count <= WidgetSnapshot.maximumDailyValues)
        #expect(snapshot.todayDuration.isFinite && snapshot.weekDuration.isFinite)
    }
}
