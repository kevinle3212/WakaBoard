import Foundation

/// A normalized day of coding activity in the selected WakaTime time zone.
public struct ActivityDay: Codable, Hashable, Sendable, Identifiable {
    public let date: Date
    public let duration: TimeInterval
    public let projects: [Usage]
    public let languages: [Usage]
    /// Editors the day's coding time was spent in.
    public let editors: [Usage]
    /// Operating systems the day's coding time was spent on.
    public let operatingSystems: [Usage]
    /// WakaTime's own activity categories — coding, debugging, building, and so on.
    public let categories: [Usage]

    public var id: Date { date }

    /// Clamps a duration into a finite, non-negative value.
    ///
    /// `max(0, .nan)` evaluates to `.nan` because every comparison against NaN is
    /// false, so a non-finite value must be replaced rather than clamped.
    static func sanitized(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite else { return 0 }
        return max(0, duration)
    }

    public init(
        date: Date,
        duration: TimeInterval,
        projects: [Usage] = [],
        languages: [Usage] = [],
        editors: [Usage] = [],
        operatingSystems: [Usage] = [],
        categories: [Usage] = []
    ) {
        self.date = date
        self.duration = Self.sanitized(duration)
        self.projects = projects
        self.languages = languages
        self.editors = editors
        self.operatingSystems = operatingSystems
        self.categories = categories
    }

    /// Decodes tolerantly so a cache written before the three extra dimensions
    /// existed still loads.
    ///
    /// The cache schema version is bumped alongside this, so in practice an old
    /// envelope is discarded rather than read. This is the belt to that braces: a
    /// day that reaches here from any other source — a future format, a hand-written
    /// fixture — decodes rather than throwing, and simply has no editors.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            date: try container.decode(Date.self, forKey: .date),
            duration: try container.decode(TimeInterval.self, forKey: .duration),
            projects: try container.decodeIfPresent([Usage].self, forKey: .projects) ?? [],
            languages: try container.decodeIfPresent([Usage].self, forKey: .languages) ?? [],
            editors: try container.decodeIfPresent([Usage].self, forKey: .editors) ?? [],
            operatingSystems: try container.decodeIfPresent([Usage].self, forKey: .operatingSystems) ?? [],
            categories: try container.decodeIfPresent([Usage].self, forKey: .categories) ?? []
        )
    }
}

/// One of the dimensions WakaBoard can rank and chart a period by.
///
/// A single enum rather than five near-identical screens: the ranked list, the
/// share chart, and the comparison chart all take a dimension and read the matching
/// field, so adding a sixth dimension later is one case and no new view.
public enum ActivityDimension: String, CaseIterable, Identifiable, Sendable {
    case projects
    case languages
    case editors
    case operatingSystems
    case categories

    public var id: Self { self }

    /// The Title Cased name shown as a heading or a picker segment.
    public var title: String {
        switch self {
        case .projects: "Projects"
        case .languages: "Languages"
        case .editors: "Editors"
        case .operatingSystems: "Operating Systems"
        case .categories: "Categories"
        }
    }

    /// A sentence explaining what the dimension measures, shown under the heading.
    public var explanation: String {
        switch self {
        case .projects: "Sorted by coding time in the selected period."
        case .languages: "Usage time is not a measure of proficiency."
        case .editors: "Where you were typing, as reported by your WakaTime plugins."
        case .operatingSystems: "The systems your coding time was recorded on."
        case .categories: "WakaTime's own split of coding, debugging, building, and the rest."
        }
    }

    /// The SF Symbol that stands for this dimension throughout the app.
    public var icon: String {
        switch self {
        case .projects: "folder"
        case .languages: "chevron.left.forwardslash.chevron.right"
        case .editors: "macwindow"
        case .operatingSystems: "desktopcomputer"
        case .categories: "square.grid.3x3"
        }
    }

    /// This dimension's buckets for one day.
    public func usage(in day: ActivityDay) -> [Usage] {
        switch self {
        case .projects: day.projects
        case .languages: day.languages
        case .editors: day.editors
        case .operatingSystems: day.operatingSystems
        case .categories: day.categories
        }
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

    /// The identity of this range for caching and request coalescing.
    ///
    /// Defined once here rather than assembled at each call site: the cache and the
    /// coalescer have to agree on what "the same request" means, and two string
    /// interpolations that drift apart is exactly how a period switch starts
    /// returning the previous period's numbers.
    public var cacheKey: String {
        let dates = queryDates()
        return "\(dates.start)-\(dates.end)-\(timeZoneIdentifier)"
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
        if seconds > 0, seconds < 60 { return "<1m" }
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
    case breakdown
    case projects
    case languages
    case insights
    case settings

    public init?(url: URL, scheme: String) {
        guard url.scheme == scheme, url.host == "open", url.query == nil else { return nil }
        switch url.path {
        case "/overview": self = .overview
        case "/activity": self = .activity
        case "/breakdown": self = .breakdown
        case "/projects": self = .projects
        case "/languages": self = .languages
        case "/insights": self = .insights
        case "/settings": self = .settings
        default: return nil
        }
    }

    /// The dimension this link asks the breakdown screen to open on, if any.
    ///
    /// `/projects` and `/languages` predate the breakdown screen and are still live
    /// in shipped widgets, so they keep working: they land on the same screen with
    /// their own dimension already selected rather than 404-ing into the overview.
    public var dimension: ActivityDimension? {
        switch self {
        case .projects: .projects
        case .languages: .languages
        default: nil
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
        case .overview: "overview"; case .activity: "activity"; case .breakdown: "breakdown"
        case .projects: "projects"; case .languages: "languages"; case .insights: "insights"
        case .settings: "settings"
        }
    }
}
