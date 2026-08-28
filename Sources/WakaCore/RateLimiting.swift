import Foundation

/// Parses the `Retry-After` header of an untrusted response into a delay WakaBoard
/// is willing to wait.
///
/// RFC 9110 §10.2.3 permits two forms: a non-negative delta in seconds, or an
/// HTTP-date. A server — or anything able to impersonate one — may also send a
/// negative number, a value large enough to hang the client for a year, or
/// something that is not a number at all. Every result is therefore clamped to
/// ``maximum`` and floored at zero, and an unparsable value yields `nil` so the
/// caller falls back to its own backoff rather than to an attacker's number.
public enum RetryAfter {
    /// The longest server-requested delay WakaBoard will honor, in seconds.
    ///
    /// Beyond this the request is abandoned and retried on the next user-initiated
    /// refresh, which is friendlier than an unbounded sleep the user cannot see.
    public static let maximum: TimeInterval = 300

    /// Longest header value considered at all, to bound parsing work on hostile input.
    private static let maximumHeaderLength = 64

    /// Returns a bounded delay in seconds, or `nil` when the header is absent or unusable.
    ///
    /// - Parameters:
    ///   - raw: The raw header value, if the response carried one.
    ///   - now: Clock reading used to resolve the HTTP-date form. Injected for tests.
    public static func parse(_ raw: String?, now: Date = .now) -> TimeInterval? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maximumHeaderLength else { return nil }

        if let seconds = TimeInterval(trimmed) {
            guard seconds.isFinite else { return nil }
            return clamp(seconds)
        }

        guard let date = httpDate(from: trimmed) else { return nil }
        return clamp(date.timeIntervalSince(now))
    }

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        min(maximum, max(0, seconds))
    }

    /// Parses the preferred RFC 9110 IMF-fixdate form, for example
    /// `Sun, 06 Nov 1994 08:49:37 GMT`.
    ///
    /// The formatter is built per call rather than cached in a `static`: `DateFormatter`
    /// is not `Sendable`, this path only runs on an already-failed request, and a
    /// shared mutable formatter would be a data race under strict concurrency.
    private static func httpDate(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}

/// Bounds how fast WakaBoard may call WakaTime, independent of how often the user
/// taps refresh or how many views ask for data at once.
///
/// This is the client's own limiter, not a reaction to a 429. It exists so a
/// refresh loop, a widget reload storm, or a bug cannot turn into abusive traffic
/// against a third-party API — which would get the user's own account throttled or
/// banned. Callers `await` ``acquire()`` before every outbound request.
///
/// Classic token bucket: ``capacity`` tokens allow a short burst, and tokens return
/// at ``refillPerSecond``. Defaults are deliberately well under any published
/// WakaTime limit, because the cost of being too slow is a slightly later refresh
/// and the cost of being too fast is the user's account.
public actor TokenBucket {
    private let capacity: Double
    private let refillPerSecond: Double
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var tokens: Double
    private var lastRefill: Date

    /// - Parameters:
    ///   - capacity: Maximum burst size. Must be at least 1.
    ///   - refillPerSecond: Sustained request rate once the burst is spent.
    ///   - now: Clock reading. Injected so tests need no real time.
    ///   - sleep: Suspension primitive. Injected so tests need no real delay.
    public init(
        capacity: Double = 5,
        refillPerSecond: Double = 1,
        now: @escaping @Sendable () -> Date = { .now },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.capacity = max(1, capacity)
        self.refillPerSecond = max(0.001, refillPerSecond)
        self.now = now
        self.sleep = sleep
        self.tokens = max(1, capacity)
        self.lastRefill = now()
    }

    /// Consumes one token, suspending until one is available.
    ///
    /// Throws `CancellationError` if the task is cancelled while waiting, so a user
    /// who navigates away is not silently held behind the limiter.
    public func acquire() async throws {
        refill()
        if tokens < 1 {
            let deficit = (1 - tokens) / refillPerSecond
            try await sleep(deficit)
            try Task.checkCancellation()
            refill()
        }
        tokens = max(0, tokens - 1)
    }

    /// Reports the currently available tokens. Exposed for tests and diagnostics.
    public func availableTokens() -> Double {
        refill()
        return tokens
    }

    private func refill() {
        let current = now()
        let elapsed = current.timeIntervalSince(lastRefill)
        // A backwards clock (NTP correction, user changing the date) must not mint
        // tokens or strand the bucket; treat it as no elapsed time.
        guard elapsed > 0 else {
            lastRefill = current
            return
        }
        tokens = min(capacity, tokens + elapsed * refillPerSecond)
        lastRefill = current
    }
}

/// How WakaBoard retries a failed read.
///
/// Only idempotent `GET` requests are retried, and only for failures that a retry
/// can plausibly fix. Delay grows exponentially, is capped, and carries jitter so
/// that many clients failing at once do not resynchronize into a thundering herd.
public struct RetryPolicy: Sendable {
    /// Total attempts including the first. `1` disables retrying.
    public let maximumAttempts: Int
    /// Delay before the first retry, doubled on each subsequent attempt.
    public let baseDelay: TimeInterval
    /// Ceiling applied to the computed backoff, before `Retry-After` is considered.
    public let maximumDelay: TimeInterval

    public init(maximumAttempts: Int = 3, baseDelay: TimeInterval = 1, maximumDelay: TimeInterval = 30) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.baseDelay = max(0, baseDelay)
        self.maximumDelay = max(0, maximumDelay)
    }

    /// Disables retrying entirely. Used by callers that own their own scheduling.
    public static let none = RetryPolicy(maximumAttempts: 1)

    /// Whether a given failure is worth another attempt.
    ///
    /// Authentication, authorization, missing-resource, and decoding failures are
    /// deterministic: retrying them wastes the user's battery and the API's budget,
    /// and for `401` it can lock an account. Only transport blips, rate limiting,
    /// and server-side faults are retried.
    public func shouldRetry(_ error: WakaTimeError) -> Bool {
        switch error {
        case .rateLimited, .serviceUnavailable, .transport:
            true
        case .invalidEndpoint, .unauthenticated, .forbidden, .unavailable, .decoding, .responseTooLarge:
            false
        }
    }

    /// The delay before `attempt`, where the first retry is attempt 1.
    ///
    /// A server-supplied `Retry-After` wins when it is longer than our own backoff —
    /// the server knows its own recovery window — but it has already been clamped by
    /// ``RetryAfter/parse(_:now:)`` so it cannot impose an unbounded wait.
    ///
    /// - Parameter jitter: A value in `0...1`, injected so tests are deterministic.
    ///   Production callers pass `Double.random(in: 0...1)`.
    public func delay(forAttempt attempt: Int, retryAfter: TimeInterval?, jitter: Double) -> TimeInterval {
        let exponential = min(maximumDelay, baseDelay * pow(2, Double(max(0, attempt - 1))))
        // Full jitter: sample uniformly from [0, exponential] rather than adding a
        // fixed fraction, which is what actually decorrelates retrying clients.
        let jittered = exponential * min(1, max(0, jitter))
        guard let retryAfter else { return jittered }
        return max(jittered, min(RetryAfter.maximum, max(0, retryAfter)))
    }
}
