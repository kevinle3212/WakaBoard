import Foundation

/// A normalized day of coding activity in the selected WakaTime time zone.
public struct ActivityDay: Codable, Hashable, Sendable, Identifiable {
    public let date: Date
    public let duration: TimeInterval
    public let projects: [Usage]
    public let languages: [Usage]

    public var id: Date { date }

    public init(date: Date, duration: TimeInterval, projects: [Usage] = [], languages: [Usage] = []) {
        self.date = date
        self.duration = max(0, duration)
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
        self.duration = max(0, duration)
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
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public let generatedAt: Date
    public let todayDuration: TimeInterval
    public let weekDuration: TimeInterval
    public let topProject: String?

    public init(generatedAt: Date, todayDuration: TimeInterval, weekDuration: TimeInterval, topProject: String?) {
        self.generatedAt = generatedAt
        self.todayDuration = max(0, todayDuration)
        self.weekDuration = max(0, weekDuration)
        self.topProject = topProject
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

    public func url(scheme: String) -> URL {
        URL(string: "\(scheme)://open/\(path)")!
    }

    private var path: String {
        switch self {
        case .overview: "overview"; case .activity: "activity"; case .projects: "projects"
        case .languages: "languages"; case .insights: "insights"; case .settings: "settings"
        }
    }
}
