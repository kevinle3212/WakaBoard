import Foundation

/// One heartbeat, as WakaTime's plugins recorded it.
///
/// Only the four fields WakaBoard needs are decoded, and every one of them except
/// `time` is optional in WakaTime's own documentation. A heartbeat with no language
/// is not a malformed response — it is a file WakaTime could not classify, which is
/// precisely the case this whole feature exists to explain.
public struct WakaTimeHeartbeat: Decodable, Sendable, Equatable {
    /// The file path, application, or domain the time was logged against.
    public let entity: String?
    /// `file`, `app`, `url`, or `domain`.
    public let type: String?
    /// The language WakaTime assigned, if it assigned one.
    public let language: String?
    /// Start of the heartbeat, as a UNIX epoch with fractional seconds.
    public let time: Double

    public init(entity: String?, type: String?, language: String?, time: Double) {
        self.entity = entity
        self.type = type
        self.language = language
        self.time = time
    }
}

/// The heartbeats response envelope.
public struct WakaTimeHeartbeatsResponse: Decodable, Sendable {
    public let data: [WakaTimeHeartbeat]
}

/// Turns WakaTime's unresolved language buckets into named file types.
///
/// ## Why heartbeats and not durations
///
/// WakaTime's `durations` endpoint slices by exactly one dimension at a time —
/// `entity` **or** `language`, never both — so no response from it can say which
/// files ended up inside the "Other" bucket. Heartbeats carry `entity` and
/// `language` on the same record, which is the only join WakaTime's public API
/// offers. The cost is that heartbeats are point events, so the durations have to be
/// reconstructed here.
///
/// ## What "reconstructed" means, and why the UI has to say so
///
/// WakaTime builds a duration by joining heartbeats that fall within the account's
/// keystroke-timeout preference, which defaults to fifteen minutes. That preference
/// is not exposed by the API, and neither is the account's `writes_only` setting, so
/// this reconstruction uses the documented defaults and will not match WakaTime's own
/// figure to the second. Every screen built on it says as much. Presenting a
/// reconstructed number as WakaTime's own would be the exact kind of quiet
/// fabrication this app is built to avoid.
public enum FileTypeBreakdown {
    /// WakaTime's default keystroke timeout, and the join window used here.
    public static let keystrokeTimeout: TimeInterval = 15 * 60

    /// The most days one drill-down will fetch.
    ///
    /// One request per day, so a ninety-day period would be ninety requests for a
    /// single tap. Fourteen covers the weekly and monthly periods outright and keeps
    /// the quarterly one to a bounded, honest sample the UI labels as such.
    public static let maximumDays = 14

    /// The language names WakaTime uses when it could not classify a file.
    ///
    /// Matched case-insensitively and exactly. Not a prefix match: "Other" is
    /// unresolved, but "OtherLang" would be a real language and folding it in here
    /// would misattribute somebody's time.
    private static let unresolvedNames: Set<String> = ["other", "unknown"]

    /// Whether this bucket name is one WakaTime uses for files it could not classify.
    public static func isUnresolvedBucket(_ name: String) -> Bool {
        unresolvedNames.contains(name.lowercased())
    }

    /// Reconstructs a duration for each heartbeat by joining it to the next one.
    ///
    /// A heartbeat is credited with the gap to the heartbeat that follows it, capped
    /// at the keystroke timeout. A gap longer than the timeout ends the session, so
    /// the heartbeat before it is credited with nothing — that is the interval the
    /// user was away, and counting it would inflate every figure downstream. The last
    /// heartbeat of the day is credited with nothing for the same reason: there is no
    /// evidence of how long it lasted.
    ///
    /// - Returns: Each heartbeat paired with the seconds attributed to it.
    public static func attribute(
        _ heartbeats: [WakaTimeHeartbeat],
        timeout: TimeInterval = keystrokeTimeout
    ) -> [(heartbeat: WakaTimeHeartbeat, seconds: TimeInterval)] {
        let sorted = heartbeats.filter { $0.time.isFinite }.sorted { $0.time < $1.time }
        return sorted.enumerated().map { index, heartbeat in
            guard index + 1 < sorted.count else { return (heartbeat, 0) }
            let gap = sorted[index + 1].time - heartbeat.time
            guard gap > 0, gap <= timeout else { return (heartbeat, 0) }
            return (heartbeat, gap)
        }
    }

    /// The file types inside one unresolved language bucket, largest first.
    ///
    /// - Parameters:
    ///   - heartbeats: Every heartbeat across the days being examined.
    ///   - bucket: The language name being opened, such as `Other`.
    public static func rows(
        from heartbeats: [WakaTimeHeartbeat],
        bucket: String,
        timeout: TimeInterval = keystrokeTimeout
    ) -> [Usage] {
        var totals: [String: TimeInterval] = [:]
        for (heartbeat, seconds) in attribute(heartbeats, timeout: timeout) where seconds > 0 {
            guard matches(heartbeat.language, bucket: bucket) else { continue }
            totals[label(for: heartbeat), default: 0] += seconds
        }
        return totals
            .map { Usage(name: $0.key, duration: $0.value) }
            .filter { $0.duration > 0 }
            .sorted { $0.duration == $1.duration ? $0.name < $1.name : $0.duration > $1.duration }
    }

    /// Whether a heartbeat's language belongs to the bucket being opened.
    ///
    /// A heartbeat with no language at all belongs to an unresolved bucket: a file
    /// WakaTime could not classify is exactly what "Other" is made of.
    private static func matches(_ language: String?, bucket: String) -> Bool {
        guard let language, !language.isEmpty else { return isUnresolvedBucket(bucket) }
        return language.caseInsensitiveCompare(bucket) == .orderedSame
    }

    /// What one heartbeat is counted as in the breakdown.
    ///
    /// A file becomes its extension, because that is the thing a reader recognises
    /// and the thing WakaTime failed to classify. A file with no extension becomes
    /// its own name — `Makefile` and `Dockerfile` are meaningful answers, and
    /// grouping them under "no extension" would throw away the only useful part.
    /// Anything that is not a file is counted as its own kind.
    static func label(for heartbeat: WakaTimeHeartbeat) -> String {
        guard let entity = heartbeat.entity, !entity.isEmpty else { return "Unnamed" }
        switch heartbeat.type {
        case "file", nil, "":
            let name = (entity as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension
            if !ext.isEmpty { return ResponseBounds.name(".\(ext.lowercased())") }
            return ResponseBounds.name(name.isEmpty ? "Unnamed" : name)
        case "app": return "Applications"
        case "url", "domain": return "Web"
        case let other?: return ResponseBounds.name(other.capitalized)
        }
    }

    /// The days a drill-down should fetch for `range`, newest first, bounded.
    ///
    /// Newest first because a truncated sample should be the most recent days rather
    /// than an arbitrary slice, and because the newest day is the one a user is most
    /// likely to be asking about.
    public static func days(in range: ActivityRange, calendar: Calendar = .current) -> [Date] {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: range.timeZoneIdentifier) ?? calendar.timeZone
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: range.end)
        let first = calendar.startOfDay(for: range.start)
        while cursor >= first, days.count < maximumDays {
            days.append(cursor)
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return days
    }
}

/// The result of one drill-down, and whether it covers the whole period.
public struct BreakdownResult: Sendable, Equatable {
    /// File types inside the bucket, largest first.
    public let rows: [Usage]
    /// How many days were actually fetched.
    public let daysCovered: Int
    /// How many days the selected period holds.
    public let daysInPeriod: Int

    public init(rows: [Usage], daysCovered: Int, daysInPeriod: Int) {
        self.rows = rows
        self.daysCovered = daysCovered
        self.daysInPeriod = daysInPeriod
    }

    /// Whether the sample is shorter than the period the user is looking at.
    public var isPartial: Bool { daysCovered < daysInPeriod }

    /// The total the reconstruction accounts for.
    public var total: TimeInterval { rows.reduce(0) { $0 + $1.duration } }
}
