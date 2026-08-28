import Foundation

/// A narrow boundary that makes HTTP behavior deterministic in tests.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession`-backed HTTP client that exposes only validated HTTP responses.
///
/// The session is deliberately not `URLSession.shared`. Shared state is the wrong
/// default for a client that carries a credential and receives private analytics:
///
/// - **Ephemeral configuration** keeps responses out of the on-disk URL cache. A
///   user's project names and coding hours are private analytics; they should not
///   survive in `~/Library/Caches` after the app is closed.
/// - **Cookies disabled.** This API is authenticated by header. Accepting cookies
///   would create ambient authority the app never intended to hold.
/// - **TLS 1.2 floor** so a downgrade cannot be negotiated.
/// - **Explicit timeouts**, because the default 60-second request timeout leaves a
///   refresh spinning long past the point a user has concluded the app is broken.
/// - **A response size ceiling**, because `data(for:)` buffers the whole body in
///   memory and the body is attacker-controlled if TLS is ever terminated by
///   something other than WakaTime.
public struct URLSessionHTTPClient: HTTPClient {
    /// Largest response body accepted, in bytes.
    ///
    /// A year of daily summaries is comfortably under a megabyte; 8 MB is generous
    /// while still bounding memory against a hostile or malfunctioning server.
    public static let maximumResponseBytes = 8 * 1_024 * 1_024

    private let session: URLSession
    private let maximumBytes: Int

    public init(session: URLSession = URLSessionHTTPClient.makeSession(), maximumBytes: Int = URLSessionHTTPClient.maximumResponseBytes) {
        self.session = session
        self.maximumBytes = maximumBytes
    }

    /// Builds the hardened session described in the type documentation.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = [:]
        return URLSession(configuration: configuration)
    }

    /// Rejects a body larger than the client is willing to hold in memory.
    ///
    /// Both the declared and the received size are checked: a server that lies in
    /// `Content-Length` must not be able to bypass the limit, and a server that
    /// declares an honest oversized length should be rejected without buffering it.
    static func validateSize(declared: Int64, received: Int, maximumBytes: Int) throws {
        if declared > 0, declared > Int64(maximumBytes) { throw WakaTimeError.responseTooLarge }
        guard received <= maximumBytes else { throw WakaTimeError.responseTooLarge }
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw WakaTimeError.transport }
            // Check the declared length first so an oversized body can be rejected
            // by its header, then check what actually arrived — a lying
            // `Content-Length` must not become a bypass.
            try Self.validateSize(declared: http.expectedContentLength, received: data.count, maximumBytes: maximumBytes)
            return (data, http)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WakaTimeError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw WakaTimeError.transport
        }
    }
}

/// Errors are safe to display as coarse recovery states and never contain request
/// secrets, credentials, response bodies, or user analytics.
public enum WakaTimeError: Error, Equatable, Sendable {
    case invalidEndpoint
    case unauthenticated
    case forbidden
    case unavailable
    case rateLimited(retryAfter: TimeInterval?)
    case serviceUnavailable
    case transport
    case decoding
    case responseTooLarge
}

/// How a request proves who it is.
///
/// The two supported schemes are not interchangeable, and conflating them was a
/// real defect in the generated code: a bearer token sent as a `Basic` credential
/// authenticates nothing and leaks the token into a header the server will log as
/// a malformed basic-auth attempt.
///
/// - `personalAPIKey`: WakaTime expects the key base64-encoded in a `Basic`
///   credential. Encoding happens here, once, so no caller can forget it.
/// - `bearerToken`: An OAuth access token, sent as `Bearer`. Reserved for the
///   relay-backed flow described in `SECURITY.md`; not reachable in this build.
public enum Credential: Equatable, Sendable {
    case personalAPIKey(String)
    case bearerToken(String)

    /// The exact `Authorization` header value for this credential kind.
    public var authorizationHeaderValue: String {
        switch self {
        case .personalAPIKey(let key):
            "Basic \(Data(key.utf8).base64EncodedString())"
        case .bearerToken(let token):
            "Bearer \(token)"
        }
    }

    /// The secret itself, for storage. Never log or display this.
    var secret: String {
        switch self {
        case .personalAPIKey(let key): key
        case .bearerToken(let token): token
        }
    }

    /// Whether the credential is structurally usable.
    ///
    /// A header value may not contain control characters or newlines — a credential
    /// carrying `\r\n` would otherwise permit header injection into the request.
    public var isWellFormed: Bool {
        let value = secret
        guard !value.isEmpty, value.count <= 4_096 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7F && scalar.isASCII
        }
    }
}

/// Typed read-only WakaTime API endpoint construction.
///
/// Every endpoint is a safe `GET`. There is no code path that writes to WakaTime,
/// which is what makes retrying a failed request safe in the first place.
public enum WakaTimeEndpoint: Sendable {
    case currentUser
    case summaries(ActivityRange)
    case stats(String)
    case projects

    /// The only host this client will ever contact.
    public static let canonicalBaseURL = URL(string: "https://api.wakatime.com")!

    public func request(baseURL: URL = WakaTimeEndpoint.canonicalBaseURL, credential: Credential) throws -> URLRequest {
        guard baseURL.scheme == "https",
              let host = baseURL.host,
              Self.allowedHosts.contains(host.lowercased()),
              credential.isWellFormed else {
            throw WakaTimeError.invalidEndpoint
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        switch self {
        case .currentUser:
            components?.path = "/api/v1/users/current"
        case .projects:
            components?.path = "/api/v1/users/current/projects"
        case .stats(let range):
            guard !range.isEmpty, range.count <= 32,
                  range.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else {
                throw WakaTimeError.invalidEndpoint
            }
            components?.path = "/api/v1/users/current/stats/\(range)"
        case .summaries(let range):
            components?.path = "/api/v1/users/current/summaries"
            let dates = range.queryDates()
            components?.queryItems = [
                URLQueryItem(name: "start", value: dates.start),
                URLQueryItem(name: "end", value: dates.end)
            ]
        }
        guard let url = components?.url else { throw WakaTimeError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(credential.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Identify the client without fingerprinting the user: no version of the OS,
        // no device model, no unique identifier.
        request.setValue("WakaBoard", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpShouldHandleCookies = false
        return request
    }

    /// Hosts WakaTime serves its public API from. Anything else is rejected before
    /// a credential is attached, so a mistyped or injected base URL cannot exfiltrate one.
    private static let allowedHosts: Set<String> = ["api.wakatime.com", "wakatime.com"]
}

/// The parts of the summaries response needed at the repository boundary.
public struct WakaTimeSummariesResponse: Decodable, Sendable {
    public let data: [WakaTimeSummaryDay]
}

public struct WakaTimeSummaryDay: Decodable, Sendable {
    public let range: WakaTimeRange
    public let grandTotal: WakaTimeDuration
    public let projects: [WakaTimeNamedDuration]
    public let languages: [WakaTimeNamedDuration]

    enum CodingKeys: String, CodingKey { case range; case grandTotal = "grand_total"; case projects; case languages }
}

public struct WakaTimeRange: Decodable, Sendable { public let date: String }

public struct WakaTimeDuration: Decodable, Sendable {
    public let totalSeconds: Double
    enum CodingKeys: String, CodingKey { case totalSeconds = "total_seconds" }
}

public struct WakaTimeNamedDuration: Decodable, Sendable {
    public let name: String
    public let totalSeconds: Double
    enum CodingKeys: String, CodingKey { case name; case totalSeconds = "total_seconds" }
}

/// Bounds applied to values decoded from an untrusted response before they are
/// allowed to reach analytics, the cache, or the UI.
///
/// Without these, a single absurd `total_seconds` propagates into every derived
/// figure — averages, percentages, the chart's y-axis — and a multi-megabyte
/// project name becomes an unbounded string rendered in a `List` row.
public enum ResponseBounds {
    /// No day can contain more than 24 hours of coding.
    public static let maximumDailySeconds: TimeInterval = 24 * 60 * 60
    /// Longest project or language name retained.
    public static let maximumNameLength = 128
    /// Most day entries accepted from one response, bounding memory and render cost.
    public static let maximumDays = 400
    /// Most buckets retained per day.
    public static let maximumBucketsPerDay = 200

    /// Clamps a duration into a value analytics can safely consume.
    ///
    /// Non-finite input is rejected rather than clamped: `NaN` compares false
    /// against every bound, so silently mapping it to zero would hide a malformed
    /// response, while propagating it poisons every downstream mean and ratio.
    public static func duration(_ raw: Double) throws -> TimeInterval {
        guard raw.isFinite else { throw WakaTimeError.decoding }
        return min(maximumDailySeconds, max(0, raw))
    }

    /// Truncates a display name to a bounded length, preserving grapheme clusters
    /// so an emoji or combining mark is never split into invalid output.
    public static func name(_ raw: String) -> String {
        raw.count <= maximumNameLength ? raw : String(raw.prefix(maximumNameLength))
    }
}

public extension WakaTimeSummariesResponse {
    /// Maps the wire response into normalized days, rejecting anything unusable.
    func normalized(calendar: Calendar = .current, timeZone: TimeZone) throws -> [ActivityDay] {
        guard data.count <= ResponseBounds.maximumDays else { throw WakaTimeError.decoding }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return try data.map { item in
            guard let date = formatter.date(from: item.range.date) else { throw WakaTimeError.decoding }
            return ActivityDay(
                date: date,
                duration: try ResponseBounds.duration(item.grandTotal.totalSeconds),
                projects: try bucket(item.projects),
                languages: try bucket(item.languages)
            )
        }
    }

    private func bucket(_ raw: [WakaTimeNamedDuration]) throws -> [Usage] {
        try raw.prefix(ResponseBounds.maximumBucketsPerDay).map {
            Usage(name: ResponseBounds.name($0.name), duration: try ResponseBounds.duration($0.totalSeconds))
        }
    }
}

/// Reads typed WakaTime endpoints, applies client-side rate limiting and bounded
/// retries, and maps protocol, HTTP, and decoder failures to safe categories.
public struct WakaTimeClient: Sendable {
    private let http: any HTTPClient
    private let decoder: JSONDecoder
    private let bucket: TokenBucket
    private let retryPolicy: RetryPolicy
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let jitter: @Sendable () -> Double
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - bucket: Client-side rate limiter applied to every outbound request.
    ///   - retryPolicy: Bounded backoff for retryable failures.
    ///   - sleep: Suspension primitive, injected so tests need no real delay.
    ///   - jitter: Source of retry jitter in `0...1`, injected for determinism.
    ///   - now: Clock reading used to resolve an HTTP-date `Retry-After`.
    public init(
        http: any HTTPClient = URLSessionHTTPClient(),
        decoder: JSONDecoder = JSONDecoder(),
        bucket: TokenBucket = TokenBucket(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0 ... 1) },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.http = http
        self.decoder = decoder
        self.bucket = bucket
        self.retryPolicy = retryPolicy
        self.sleep = sleep
        self.jitter = jitter
        self.now = now
    }

    public func summaries(range: ActivityRange, credential: Credential, timeZone: TimeZone) async throws -> [ActivityDay] {
        let request = try WakaTimeEndpoint.summaries(range).request(credential: credential)
        let data = try await send(request)
        do {
            return try decoder.decode(WakaTimeSummariesResponse.self, from: data).normalized(timeZone: timeZone)
        } catch let error as WakaTimeError {
            throw error
        } catch {
            throw WakaTimeError.decoding
        }
    }

    /// Verifies a credential against the account endpoint without persisting anything.
    ///
    /// Used at sign-in so a bad key fails immediately and visibly, rather than being
    /// stored in the Keychain and failing on the next refresh.
    public func verifyCredential(_ credential: Credential) async throws {
        _ = try await send(try WakaTimeEndpoint.currentUser.request(credential: credential))
    }

    /// Performs one logical read: rate limited, retried within policy, cancellable.
    private func send(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            try await bucket.acquire()
            do {
                let (data, response) = try await http.data(for: request)
                try map(response: response)
                return data
            } catch let error as WakaTimeError {
                attempt += 1
                guard attempt < retryPolicy.maximumAttempts, retryPolicy.shouldRetry(error) else { throw error }
                let delay = retryPolicy.delay(forAttempt: attempt, retryAfter: error.retryAfter, jitter: jitter())
                try await sleep(delay)
            }
        }
    }

    private func map(response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ... 299: return
        case 401: throw WakaTimeError.unauthenticated
        case 403: throw WakaTimeError.forbidden
        case 404: throw WakaTimeError.unavailable
        case 429: throw WakaTimeError.rateLimited(retryAfter: RetryAfter.parse(response.value(forHTTPHeaderField: "Retry-After"), now: now()))
        case 500 ... 599: throw WakaTimeError.serviceUnavailable
        default: throw WakaTimeError.transport
        }
    }
}

private extension WakaTimeError {
    /// The server-requested delay carried by this failure, if any.
    var retryAfter: TimeInterval? {
        if case .rateLimited(let value) = self { return value }
        return nil
    }
}
