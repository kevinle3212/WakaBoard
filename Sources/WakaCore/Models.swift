import Foundation

/// A normalized day of coding activity in the selected WakaTime time zone.
public struct ActivityDay: Codable, Hashable, Sendable, Identifiable {
    public let date: Date
    public let duration: TimeInterval
    public let projects: [Usage]
    public let languages: [Usage]

    public var id: Date { date }

    /// Clamps a duration into a finite, non-negative value.
    ///
    /// `max(0, .nan)` evaluates to `.nan` because every comparison against NaN is
    /// false, so a non-finite value must be replaced rather than clamped.
    static func sanitized(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite else { return 0 }
        return max(0, duration)
    }

    public init(date: Date, duration: TimeInterval, projects: [Usage] = [], languages: [Usage] = []) {
        self.date = date
        self.duration = Self.sanitized(duration)
        self.projects = projects
        self.languages = languages
    }
}

/// A named duration bucket, such as a project or language.
public struct Usage: Codable, Hashable, Sendable, Identifiable {
    public let name: String
    public let duration: TimeInterval

    public var id: String { name }

    public init(name: String, duration: TimeInterval) {
        self.name = name
        self.duration = ActivityDay.sanitized(duration)
    }
}

/// A user-selected inclusive date interval that retains its calendar and time zone contract.
public struct ActivityRange: Codable, Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let timeZoneIdentifier: String

    public init(start: Date, end: Date, timeZone: TimeZone) {
        self.start = start
        self.end = end
        self.timeZoneIdentifier = timeZone.identifier
    }

    /// Produces API date query values using Gregorian calendar days in the chosen timezone.
    public func queryDates(calendar: Calendar = .current) -> (start: String, end: String) {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? calendar.timeZone
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    /// Counts inclusive calendar days instead of elapsed 24-hour windows, so DST does not distort averages.
    public func calendarDayCount(calendar: Calendar = .current) -> Int {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? calendar.timeZone
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return max(1, (calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0) + 1)
    }
}

/// Presents durations without exposing raw seconds to UI callers.
public struct DurationFormatter: Sendable {
    public init() {}

    public func string(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

/// A credential-free, minimal representation safe for widget persistence.
///
/// Every field is an aggregate. There is deliberately no field capable of holding
/// a credential, a username, or a raw API response, so the App Group container
/// cannot leak one even if a future caller is careless.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// Longest daily series carried, matching the widest widget family.
    public static let maximumDailyValues = 7

    public let generatedAt: Date
    public let todayDuration: TimeInterval
    public let weekDuration: TimeInterval
    public let topProject: String?
    /// Recent daily totals, oldest first, for the weekly widget's bar row.
    public let dailyDurations: [TimeInterval]

    public init(
        generatedAt: Date,
        todayDuration: TimeInterval,
        weekDuration: TimeInterval,
        topProject: String?,
        dailyDurations: [TimeInterval] = []
    ) {
        self.generatedAt = generatedAt
        self.todayDuration = ActivityDay.sanitized(todayDuration)
        self.weekDuration = ActivityDay.sanitized(weekDuration)
        self.topProject = topProject.map { String($0.prefix(ResponseBounds.maximumNameLength)) }
        self.dailyDurations = dailyDurations.suffix(Self.maximumDailyValues).map(ActivityDay.sanitized)
    }

    /// Decodes tolerantly so a snapshot written by an older build still renders.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            todayDuration: try container.decode(TimeInterval.self, forKey: .todayDuration),
            weekDuration: try container.decode(TimeInterval.self, forKey: .weekDuration),
            topProject: try container.decodeIfPresent(String.self, forKey: .topProject),
            dailyDurations: try container.decodeIfPresent([TimeInterval].self, forKey: .dailyDurations) ?? []
        )
    }
}

/// Supported in-app routes. Unknown routes intentionally fail closed.
public enum DeepLink: Hashable, Sendable {
    case overview
    case activity
    case projects
    case languages
    case insights
    case settings

    public init?(url: URL, scheme: String) {
        guard url.scheme == scheme, url.host == "open", url.query == nil else { return nil }
        switch url.path {
        case "/overview": self = .overview
        case "/activity": self = .activity
        case "/projects": self = .projects
        case "/languages": self = .languages
        case "/insights": self = .insights
        case "/settings": self = .settings
        default: return nil
        }
    }

    /// Builds the canonical link for this route.
    ///
    /// Returns `nil` rather than trapping on a scheme that cannot form a URL: the
    /// scheme is a constant today, but a force-unwrap here would turn any future
    /// configuration mistake into a crash on launch.
    public func url(scheme: String) -> URL? {
        URL(string: "\(scheme)://open/\(path)")
    }

    private var path: String {
        switch self {
        case .overview: "overview"; case .activity: "activity"; case .projects: "projects"
        case .languages: "languages"; case .insights: "insights"; case .settings: "settings"
        }
    }
}
