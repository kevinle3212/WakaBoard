import Foundation

/// Derived overview values computed locally from normalized daily activity.
public struct AnalyticsOverview: Hashable, Sendable {
    public let total: TimeInterval
    public let calendarDayAverage: TimeInterval
    public let activeDayAverage: TimeInterval?
    public let percentChange: Double?
    public let streak: Int
    public let consistencyScore: Double?
    public let topProject: Usage?
    public let topLanguage: Usage?
}

/// Short, evidence-based statements. UI may hide this collection when empty.
public enum Insight: Hashable, Sendable {
    case streak(days: Int)
    case strongestProject(name: String, share: Double)
    case consistency(score: Double)
}

/// Pure deterministic analytics formulas shared by all Apple-platform clients.
public enum AnalyticsEngine {
    public static let activeDayThreshold: TimeInterval = 15 * 60

    public static func overview(days: [ActivityDay], previousTotal: TimeInterval?, range: ActivityRange, calendar: Calendar = .current) -> AnalyticsOverview {
        let total = days.reduce(0) { $0 + $1.duration }
        let active = days.filter { $0.duration > 0 }
        let buckets = aggregate(days.flatMap(\.projects))
        let languages = aggregate(days.flatMap(\.languages))
        return AnalyticsOverview(
            total: total,
            calendarDayAverage: total / Double(range.calendarDayCount(calendar: calendar)),
            activeDayAverage: active.isEmpty ? nil : total / Double(active.count),
            percentChange: percentageChange(current: total, previous: previousTotal),
            streak: streak(days: days, range: range, calendar: calendar),
            consistencyScore: consistency(days.map(\.duration)),
            topProject: buckets.max(by: { $0.duration < $1.duration }),
            topLanguage: languages.max(by: { $0.duration < $1.duration })
        )
    }

    public static func aggregate(_ values: [Usage]) -> [Usage] {
        Dictionary(grouping: values, by: \.name).map { Usage(name: $0.key, duration: $0.value.reduce(0) { $0 + $1.duration }) }
    }

    public static func percentageChange(current: TimeInterval, previous: TimeInterval?) -> Double? {
        guard let previous, previous > 0 else { return nil }
        return ((current - previous) / previous) * 100
    }

    public static func consistency(_ durations: [TimeInterval]) -> Double? {
        guard durations.count >= 2 else { return nil }
        let positive = durations.filter { $0 > 0 }
        guard !positive.isEmpty else { return nil }
        let mean = positive.reduce(0, +) / Double(positive.count)
        let variance = positive.reduce(0) { $0 + pow($1 - mean, 2) } / Double(positive.count)
        return min(100, max(0, 100 * (1 - sqrt(variance) / mean)))
    }

    public static func streak(days: [ActivityDay], range: ActivityRange, calendar: Calendar = .current) -> Int {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: range.timeZoneIdentifier) ?? calendar.timeZone
        let totals = Dictionary(grouping: days, by: { calendar.startOfDay(for: $0.date) }).mapValues { $0.reduce(0) { $0 + $1.duration } }
        var cursor = calendar.startOfDay(for: range.end)
        var result = 0
        while (totals[cursor] ?? 0) >= activeDayThreshold {
            result += 1
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prior
        }
        return result
    }

    public static func insights(overview: AnalyticsOverview) -> [Insight] {
        var result: [Insight] = []
        if overview.streak >= 2 { result.append(.streak(days: overview.streak)) }
        if let project = overview.topProject, overview.total > 0 { result.append(.strongestProject(name: project.name, share: project.duration / overview.total)) }
        if let score = overview.consistencyScore, score >= 60 { result.append(.consistency(score: score)) }
        return result
    }
}

public extension WidgetSnapshot {
    init(days: [ActivityDay], generatedAt: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: generatedAt)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today)!
        let current = days.filter { $0.date >= today }.reduce(0) { $0 + $1.duration }
        let week = days.filter { $0.date >= weekStart && $0.date <= generatedAt }.reduce(0) { $0 + $1.duration }
        let project = AnalyticsEngine.aggregate(days.flatMap(\.projects)).max(by: { $0.duration < $1.duration })?.name
        self.init(generatedAt: generatedAt, todayDuration: current, weekDuration: week, topProject: project)
    }
}
