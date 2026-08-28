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
