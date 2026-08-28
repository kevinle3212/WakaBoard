import Foundation
import Testing
@testable import WakaCore

@Suite("Authorization")
struct AuthorizationTests {
    /// Captures the request a client actually put on the wire.
    private actor RequestCapture: HTTPClient {
        private var captured: URLRequest?
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            captured = request
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(#"{"data":[]}"#.utf8), response)
        }
        func request() -> URLRequest? { captured }
    }

    @Test("a personal API key is base64-encoded as a Basic credential")
    func apiKeyIsEncoded() throws {
        // This is the defect the generated code shipped: the raw key was interpolated
        // straight into `Basic `, which is not a valid basic-auth credential.
        let credential = Credential.personalAPIKey("waka_secret_key")
        #expect(credential.authorizationHeaderValue == "Basic \(Data("waka_secret_key".utf8).base64EncodedString())")
        #expect(credential.authorizationHeaderValue != "Basic waka_secret_key")
    }

    @Test("a bearer token is never sent as a Basic credential")
    func bearerIsNotBasic() {
        let credential = Credential.bearerToken("oauth-access-token")
        #expect(credential.authorizationHeaderValue == "Bearer oauth-access-token")
        #expect(!credential.authorizationHeaderValue.hasPrefix("Basic"))
    }

    @Test("the header the client sends matches the credential kind")
    func headerReachesTheWire() async throws {
        let capture = RequestCapture()
        let client = immediateClient(http: capture)
        let range = ActivityRange(start: .now, end: .now, timeZone: .gmt)
        _ = try await client.summaries(range: range, credential: .personalAPIKey("abc123"), timeZone: .gmt)
        let sent = try #require(await capture.request())
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("abc123".utf8).base64EncodedString())")
        #expect(sent.httpMethod == "GET")
        #expect(sent.httpShouldHandleCookies == false)
    }

    @Test("a credential that could inject headers is rejected")
    func rejectsHeaderInjection() {
        // CRLF in a credential would let an attacker append arbitrary headers.
        #expect(!Credential.personalAPIKey("abc\r\nX-Evil: 1").isWellFormed)
        #expect(!Credential.personalAPIKey("abc\ndef").isWellFormed)
        #expect(!Credential.personalAPIKey("abc\u{0000}").isWellFormed)
        #expect(!Credential.personalAPIKey("").isWellFormed)
        #expect(!Credential.personalAPIKey(String(repeating: "a", count: 5_000)).isWellFormed)
        #expect(Credential.personalAPIKey("waka_1234-5678").isWellFormed)

        // And it never reaches a request.
        #expect(throws: WakaTimeError.invalidEndpoint) {
            try WakaTimeEndpoint.currentUser.request(credential: .personalAPIKey("bad\r\nX: 1"))
        }
    }
}

@Suite("Transport")
struct TransportTests {
    @Test("only HTTPS WakaTime hosts are accepted")
    func hostAllowlist() {
        for hostile in [
            "http://api.wakatime.com",
            "https://evil.com",
            "https://api.wakatime.com.evil.com",
            "https://wakatime.com.attacker.net"
        ] {
            #expect(throws: WakaTimeError.invalidEndpoint) {
                try WakaTimeEndpoint.projects.request(baseURL: URL(string: hostile)!, credential: .personalAPIKey("k"))
            }
        }
        #expect(throws: Never.self) {
            try WakaTimeEndpoint.projects.request(baseURL: URL(string: "https://api.wakatime.com")!, credential: .personalAPIKey("k"))
        }
    }

    @Test("a path segment cannot be smuggled through the stats range")
    func statsRangeIsConstrained() {
        for hostile in ["../../admin", "last_7_days/../../x", "a b", "", String(repeating: "x", count: 64), "günstig"] {
            #expect(throws: WakaTimeError.invalidEndpoint) {
                try WakaTimeEndpoint.stats(hostile).request(credential: .personalAPIKey("k"))
            }
        }
        #expect(throws: Never.self) {
            try WakaTimeEndpoint.stats("last_7_days").request(credential: .personalAPIKey("k"))
        }
    }

    @Test("an oversized response body is rejected before it is decoded")
    func rejectsOversizedBody() throws {
        let limit = 512
        // Within the limit.
        #expect(throws: Never.self) { try URLSessionHTTPClient.validateSize(declared: 100, received: 100, maximumBytes: limit) }
        // Honestly declared as oversized.
        #expect(throws: WakaTimeError.responseTooLarge) { try URLSessionHTTPClient.validateSize(declared: 5_000, received: 0, maximumBytes: limit) }
        // A lying Content-Length must not become a bypass.
        #expect(throws: WakaTimeError.responseTooLarge) { try URLSessionHTTPClient.validateSize(declared: 10, received: 5_000, maximumBytes: limit) }
        // Unknown length (-1) still checks what actually arrived.
        #expect(throws: WakaTimeError.responseTooLarge) { try URLSessionHTTPClient.validateSize(declared: -1, received: 5_000, maximumBytes: limit) }
        #expect(throws: Never.self) { try URLSessionHTTPClient.validateSize(declared: -1, received: 10, maximumBytes: limit) }
    }

    @Test("the shipping session does not cache responses or accept cookies")
    func sessionIsHardened() {
        let configuration = URLSessionHTTPClient.makeSession().configuration
        // Private analytics must not be written to the on-disk URL cache.
        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        // This API authenticates by header; cookies would be ambient authority.
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.httpShouldSetCookies == false)
        // A refresh must fail visibly rather than hang for the 60-second default.
        #expect(configuration.timeoutIntervalForRequest == 20)
        #expect(configuration.tlsMinimumSupportedProtocolVersion == .TLSv12)
    }

    @Test("the request carries no fingerprinting headers")
    func minimalHeaders() throws {
        let request = try WakaTimeEndpoint.currentUser.request(credential: .personalAPIKey("k"))
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "WakaBoard")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }
}

@Suite("Keychain")
struct KeychainTests {
    @Test("credential encoding is tagged so a key cannot be replayed as a token")
    func taggedEncoding() throws {
        let key = Credential.personalAPIKey("abc")
        let token = Credential.bearerToken("abc")
        #expect(KeychainCredentialStore.encode(key) != KeychainCredentialStore.encode(token))
        #expect(KeychainCredentialStore.decode(KeychainCredentialStore.encode(key)) == key)
        #expect(KeychainCredentialStore.decode(KeychainCredentialStore.encode(token)) == token)
    }

    @Test("an untagged or malformed stored item is rejected rather than guessed at")
    func rejectsUntagged() {
        #expect(KeychainCredentialStore.decode("abc") == nil)
        #expect(KeychainCredentialStore.decode("") == nil)
        #expect(KeychainCredentialStore.decode("apikey:") == nil)
        #expect(KeychainCredentialStore.decode("apikey:bad\r\nX: 1") == nil)
    }

    @Test("OSStatus values map to distinguishable errors")
    func statusMapping() {
        #expect(KeychainError.from(errSecInteractionNotAllowed) == .interactionNotAllowed)
        #expect(KeychainError.from(errSecAuthFailed) == .interactionNotAllowed)
        #expect(KeychainError.from(errSecDecode) == .unhandled(status: errSecDecode))
    }

    @Test("the in-memory double round-trips and rejects a malformed credential")
    func doubleBehaviour() throws {
        let store = InMemoryCredentialStore()
        #expect(try store.load() == nil)
        try store.save(.personalAPIKey("abc"))
        #expect(try store.load() == .personalAPIKey("abc"))
        #expect(throws: KeychainError.malformedItem) { try store.save(.personalAPIKey("bad\r\n")) }
        try store.remove()
        #expect(try store.load() == nil)
    }

    @Test("a locked keychain surfaces as a failure, not as a missing credential")
    func lockedKeychain() {
        // The distinction matters: "no credential" sends the user to sign-in, while
        // "locked" must not silently discard a credential that still exists.
        let store = InMemoryCredentialStore(failure: .interactionNotAllowed)
        #expect(throws: KeychainError.interactionNotAllowed) { try store.load() }
        #expect(throws: KeychainError.interactionNotAllowed) { try store.remove() }
    }
}

@Suite("Untrusted")
struct UntrustedInputTests {
    private func response(_ json: String) -> (Data, HTTPURLResponse) {
        (Data(json.utf8), HTTPURLResponse(url: URL(string: "https://api.wakatime.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func decode(_ json: String) async throws -> [ActivityDay] {
        let client = immediateClient(http: StubHTTPClient(result: .success(response(json))))
        let range = ActivityRange(start: .now, end: .now, timeZone: .gmt)
        return try await client.summaries(range: range, credential: .personalAPIKey("k"), timeZone: .gmt)
    }

    @Test("an impossible daily duration is clamped to a real day")
    func clampsOversizedDuration() async throws {
        let days = try await decode(#"{"data":[{"range":{"date":"2026-01-01"},"grand_total":{"total_seconds":9999999},"projects":[],"languages":[]}]}"#)
        #expect(days[0].duration == ResponseBounds.maximumDailySeconds)
    }

    @Test("a negative duration becomes zero rather than a negative total")
    func clampsNegative() async throws {
        let days = try await decode(#"{"data":[{"range":{"date":"2026-01-01"},"grand_total":{"total_seconds":-500},"projects":[],"languages":[]}]}"#)
        #expect(days[0].duration == 0)
    }

    @Test("a non-finite duration is rejected instead of poisoning analytics")
    func rejectsNonFinite() {
        // NaN compares false against every bound, so clamping would silently pass it
        // through into every mean, ratio, and chart axis downstream.
        #expect(throws: WakaTimeError.decoding) { _ = try ResponseBounds.duration(.nan) }
        #expect(throws: WakaTimeError.decoding) { _ = try ResponseBounds.duration(.infinity) }
        #expect(ActivityDay(date: .now, duration: .nan).duration == 0)
        #expect(Usage(name: "x", duration: .infinity).duration == 0)
    }

    @Test("an oversized project name is truncated")
    func boundsNames() async throws {
        let long = String(repeating: "A", count: 5_000)
        let days = try await decode(#"{"data":[{"range":{"date":"2026-01-01"},"grand_total":{"total_seconds":60},"projects":[{"name":"\#(long)","total_seconds":60}],"languages":[]}]}"#)
        #expect(days[0].projects[0].name.count == ResponseBounds.maximumNameLength)
    }

    @Test("a malformed date is a decoding failure, not a silently wrong day")
    func rejectsBadDate() async {
        await #expect(throws: WakaTimeError.decoding) {
            _ = try await decode(#"{"data":[{"range":{"date":"not-a-date"},"grand_total":{"total_seconds":60},"projects":[],"languages":[]}]}"#)
        }
        await #expect(throws: WakaTimeError.decoding) {
            _ = try await decode(#"{"data":[{"range":{"date":"2026-13-45"},"grand_total":{"total_seconds":60},"projects":[],"languages":[]}]}"#)
        }
    }

    @Test("an unreasonable number of days is rejected")
    func boundsDayCount() async {
        let entry = #"{"range":{"date":"2026-01-01"},"grand_total":{"total_seconds":1},"projects":[],"languages":[]}"#
        let flood = "{\"data\":[\(Array(repeating: entry, count: ResponseBounds.maximumDays + 1).joined(separator: ","))]}"
        await #expect(throws: WakaTimeError.decoding) { _ = try await decode(flood) }
    }
}
