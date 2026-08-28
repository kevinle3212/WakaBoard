import Foundation
import Testing
@testable import WakaCore

@Suite("RetryAfter")
struct RetryAfterTests {
    @Test("bounds every hostile Retry-After form")
    func parsesAndBounds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // Well-formed delta-seconds.
        #expect(RetryAfter.parse("12", now: now) == 12)
        #expect(RetryAfter.parse("  30  ", now: now) == 30)
        #expect(RetryAfter.parse("0", now: now) == 0)

        // Hostile numeric input. A negative would make the caller retry immediately
        // in a tight loop; an absurd value would hang the refresh for a year.
        #expect(RetryAfter.parse("-5", now: now) == 0)
        #expect(RetryAfter.parse("999999999", now: now) == RetryAfter.maximum)
        #expect(RetryAfter.parse("inf", now: now) == nil)
        #expect(RetryAfter.parse("nan", now: now) == nil)

        // Absent or unusable.
        #expect(RetryAfter.parse(nil, now: now) == nil)
        #expect(RetryAfter.parse("", now: now) == nil)
        #expect(RetryAfter.parse("   ", now: now) == nil)
        #expect(RetryAfter.parse("soon", now: now) == nil)
        #expect(RetryAfter.parse(String(repeating: "9", count: 200), now: now) == nil)

        // RFC 9110 HTTP-date form, which the generated code dropped entirely.
        let future = "Sun, 06 Nov 1994 08:49:37 GMT"
        let base = Date(timeIntervalSince1970: 784_111_777)
        #expect(RetryAfter.parse(future, now: base.addingTimeInterval(-60)) == 60)
        // A date already in the past must not become a negative delay.
        #expect(RetryAfter.parse(future, now: base.addingTimeInterval(600)) == 0)
        // A far-future date is clamped like any other oversized value.
        #expect(RetryAfter.parse(future, now: base.addingTimeInterval(-100_000)) == RetryAfter.maximum)
    }
}

@Suite("RateLimiting")
struct RateLimitingTests {
    /// A controllable clock, so rate-limit behavior is tested without real waiting.
    private actor Clock {
        private var current: Date
        private(set) var slept: [TimeInterval] = []
        init(_ start: Date) { current = start }
        func now() -> Date { current }
        func advance(_ interval: TimeInterval) { current += interval }
        func record(_ interval: TimeInterval) { slept.append(interval); current += interval }
        func sleeps() -> [TimeInterval] { slept }
    }

    private func harness(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> (Clock, @Sendable () -> Date, @Sendable (TimeInterval) async throws -> Void) {
        let clock = Clock(start)
        // The bucket reads the clock synchronously; a nonisolated snapshot keeps the
        // injected closure `Sendable` without making the production API async.
        let box = ClockBox(start)
        let now: @Sendable () -> Date = { box.now }
        let sleep: @Sendable (TimeInterval) async throws -> Void = { interval in
            await clock.record(interval)
            box.advance(interval)
        }
        return (clock, now, sleep)
    }

    private final class ClockBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ start: Date) { value = start }
        var now: Date { lock.withLock { value } }
        func advance(_ interval: TimeInterval) { lock.withLock { value += interval } }
    }

    @Test("bucket allows a burst then throttles to the refill rate")
    func burstThenThrottle() async throws {
        let (clock, now, sleep) = harness()
        let bucket = TokenBucket(capacity: 3, refillPerSecond: 1, now: now, sleep: sleep)

        // The burst is free.
        for _ in 0 ..< 3 { try await bucket.acquire() }
        #expect(await clock.sleeps().isEmpty)

        // The fourth must wait for a token to regenerate.
        try await bucket.acquire()
        let sleeps = await clock.sleeps()
        #expect(sleeps.count == 1)
        #expect(sleeps[0] > 0)
    }

    @Test("bucket refills over elapsed time")
    func refills() async throws {
        let (_, now, sleep) = harness()
        let bucket = TokenBucket(capacity: 5, refillPerSecond: 2, now: now, sleep: sleep)
        for _ in 0 ..< 5 { try await bucket.acquire() }
        #expect(await bucket.availableTokens() < 1)
        // Advance by sleeping, which the box also advances.
        try await sleep(2)
        #expect(await bucket.availableTokens() >= 3.9)
    }

    @Test("bucket survives a backwards clock without minting tokens")
    func backwardsClock() async throws {
        let box = ClockBox(Date(timeIntervalSince1970: 1_800_000_000))
        let now: @Sendable () -> Date = { box.now }
        let bucket = TokenBucket(capacity: 2, refillPerSecond: 1, now: now, sleep: { _ in })
        try await bucket.acquire()
        try await bucket.acquire()
        box.advance(-10_000)
        // A clock that jumps backwards must not resurrect the bucket.
        #expect(await bucket.availableTokens() < 1)
    }

    @Test("policy retries only failures a retry can fix")
    func retryClassification() {
        let policy = RetryPolicy()
        #expect(policy.shouldRetry(.rateLimited(retryAfter: nil)))
        #expect(policy.shouldRetry(.serviceUnavailable))
        #expect(policy.shouldRetry(.transport))
        // Retrying these wastes the API budget and, for 401, risks locking an account.
        #expect(!policy.shouldRetry(.unauthenticated))
        #expect(!policy.shouldRetry(.forbidden))
        #expect(!policy.shouldRetry(.unavailable))
        #expect(!policy.shouldRetry(.decoding))
        #expect(!policy.shouldRetry(.invalidEndpoint))
        #expect(!policy.shouldRetry(.responseTooLarge))
    }

    @Test("backoff grows exponentially, is capped, and is jittered")
    func backoffShape() {
        let policy = RetryPolicy(maximumAttempts: 5, baseDelay: 1, maximumDelay: 8)
        // Full jitter at 1.0 exposes the underlying exponential ceiling.
        #expect(policy.delay(forAttempt: 1, retryAfter: nil, jitter: 1) == 1)
        #expect(policy.delay(forAttempt: 2, retryAfter: nil, jitter: 1) == 2)
        #expect(policy.delay(forAttempt: 3, retryAfter: nil, jitter: 1) == 4)
        #expect(policy.delay(forAttempt: 4, retryAfter: nil, jitter: 1) == 8)
        // Capped, not unbounded.
        #expect(policy.delay(forAttempt: 9, retryAfter: nil, jitter: 1) == 8)
        // Jitter genuinely reduces the delay rather than being decorative.
        #expect(policy.delay(forAttempt: 3, retryAfter: nil, jitter: 0) == 0)
        #expect(policy.delay(forAttempt: 3, retryAfter: nil, jitter: 0.5) == 2)
    }

    @Test("a server Retry-After overrides a shorter backoff but cannot exceed the cap")
    func retryAfterWins() {
        let policy = RetryPolicy(baseDelay: 1, maximumDelay: 4)
        #expect(policy.delay(forAttempt: 1, retryAfter: 30, jitter: 1) == 30)
        // Our own backoff wins when it is the longer of the two.
        #expect(policy.delay(forAttempt: 1, retryAfter: 0.5, jitter: 1) == 1)
        // Even a value that slipped past parsing is re-clamped here.
        #expect(policy.delay(forAttempt: 1, retryAfter: 100_000, jitter: 1) == RetryAfter.maximum)
        #expect(policy.delay(forAttempt: 1, retryAfter: -20, jitter: 1) == 1)
    }

    @Test("client retries a 500 within policy and then surfaces the failure")
    func clientRetriesServerErrors() async throws {
        let http = CountingHTTPClient(status: 500)
        let client = WakaTimeClient(
            http: http,
            bucket: TokenBucket(capacity: 100, refillPerSecond: 100, sleep: { _ in }),
            retryPolicy: RetryPolicy(maximumAttempts: 3, baseDelay: 0.01, maximumDelay: 0.02),
            sleep: { _ in },
            jitter: { 1 }
        )
        await #expect(throws: WakaTimeError.serviceUnavailable) {
            try await client.summaries(range: Self.range, credential: .personalAPIKey("k"), timeZone: .gmt)
        }
        #expect(await http.callCount() == 3)
    }

    @Test("client does not retry an authentication failure")
    func clientDoesNotRetryAuthFailures() async throws {
        let http = CountingHTTPClient(status: 401)
        let client = WakaTimeClient(
            http: http,
            bucket: TokenBucket(capacity: 100, refillPerSecond: 100, sleep: { _ in }),
            retryPolicy: RetryPolicy(maximumAttempts: 5, baseDelay: 0.01),
            sleep: { _ in },
            jitter: { 1 }
        )
        await #expect(throws: WakaTimeError.unauthenticated) {
            try await client.summaries(range: Self.range, credential: .personalAPIKey("k"), timeZone: .gmt)
        }
        #expect(await http.callCount() == 1)
    }

    @Test("client honors a 429 Retry-After when computing its wait")
    func clientHonorsRetryAfter() async throws {
        let http = CountingHTTPClient(status: 429, headers: ["Retry-After": "7"])
        let recorded = SleepRecorder()
        let client = WakaTimeClient(
            http: http,
            bucket: TokenBucket(capacity: 100, refillPerSecond: 100, sleep: { _ in }),
            retryPolicy: RetryPolicy(maximumAttempts: 2, baseDelay: 1, maximumDelay: 2),
            sleep: { await recorded.record($0) },
            jitter: { 1 }
        )
        await #expect(throws: WakaTimeError.rateLimited(retryAfter: 7)) {
            try await client.summaries(range: Self.range, credential: .personalAPIKey("k"), timeZone: .gmt)
        }
        // The server said 7 seconds; our own ceiling was 2. The server's number wins.
        #expect(await recorded.values() == [7])
    }

    static let range = ActivityRange(
        start: Date(timeIntervalSince1970: 1_800_000_000),
        end: Date(timeIntervalSince1970: 1_800_000_000),
        timeZone: .gmt
    )
}

/// Counts requests and returns a fixed status, so retry behavior is observable.
actor CountingHTTPClient: HTTPClient {
    private let status: Int
    private let headers: [String: String]?
    private let body: Data
    private var calls = 0

    init(status: Int, headers: [String: String]? = nil, body: Data = Data("{\"data\":[]}".utf8)) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
        return (body, response)
    }

    func callCount() -> Int { calls }
}

/// Records the delays a client asked to sleep for.
actor SleepRecorder {
    private var recorded: [TimeInterval] = []
    func record(_ interval: TimeInterval) { recorded.append(interval) }
    func values() -> [TimeInterval] { recorded }
}
