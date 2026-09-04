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

    /// A dated duration used by period summaries and peak-day figures.
    public struct DailyValue: Hashable, Sendable, Identifiable {
        /// The calendar day in the selected WakaTime time zone.
        public let date: Date
        /// The sanitized coding duration accumulated on that day.
        public let duration: TimeInterval

        /// Creates a dated, sanitized duration.
        public init(date: Date, duration: TimeInterval) {
            self.date = date
            self.duration = ActivityDay.sanitized(duration)
        }

        public var id: Date { date }
    }

    /// Compact distribution figures for one selected period.
    public struct ActivitySummary: Hashable, Sendable {
        /// Number of calendar days in the selected range.
        public let dayCount: Int
        /// Number of days containing any recorded coding time.
        public let activeDayCount: Int
        /// Active calendar days divided by all calendar days in the range.
        public let activeShare: Double
        /// The earliest busiest day when multiple days tie.
        public let peak: DailyValue
        /// Median duration across every calendar day, including zero days.
        public let medianDuration: TimeInterval

        /// Creates the derived figures for a fully normalized period.
        public init(
            dayCount: Int,
            activeDayCount: Int,
            activeShare: Double,
            peak: DailyValue,
            medianDuration: TimeInterval
        ) {
            self.dayCount = max(0, dayCount)
            self.activeDayCount = min(max(0, activeDayCount), self.dayCount)
            self.activeShare = activeShare.isFinite ? min(1, max(0, activeShare)) : 0
            self.peak = peak
            self.medianDuration = ActivityDay.sanitized(medianDuration)
        }
    }

    /// One calendar week's contribution to the selected period.
    public struct WeekTotal: Hashable, Sendable, Identifiable {
        /// Start of the calendar week in the selected time zone.
        public let start: Date
        /// Coding time accumulated during the part of this week inside the range.
        public let duration: TimeInterval
        /// Calendar days from this week that fall inside the selected range.
        public let dayCount: Int
        /// Whether the selected range contains fewer than seven days of this week.
        public let isPartial: Bool

        /// Creates one calendar-week bucket.
        public init(start: Date, duration: TimeInterval, dayCount: Int, isPartial: Bool) {
            self.start = start
            self.duration = ActivityDay.sanitized(duration)
            self.dayCount = min(7, max(0, dayCount))
            self.isPartial = isPartial
        }

        public var id: Date { start }
    }

    /// One named series value for a single day in a bounded trend chart.
    public struct TrendPoint: Hashable, Sendable, Identifiable {
        /// Calendar day in the selected WakaTime time zone.
        public let date: Date
        /// Bucket name, such as a project or editor.
        public let name: String
        /// Sanitized time attributed to the bucket on this day.
        public let duration: TimeInterval
        /// Stable rank used to assign a palette slot without cycling colors.
        public let seriesIndex: Int

        /// Creates one safe, stable series point.
        public init(date: Date, name: String, duration: TimeInterval, seriesIndex: Int) {
            self.date = date
            self.name = String(name.prefix(ResponseBounds.maximumNameLength))
            self.duration = ActivityDay.sanitized(duration)
            self.seriesIndex = max(0, seriesIndex)
        }

        public var id: String { "\(date.timeIntervalSinceReferenceDate)-\(seriesIndex)-\(name)" }
    }

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

    /// Computes active-day, peak, and median figures over all calendar days in a range.
    ///
    /// Duplicate input dates are summed. Missing dates contribute zero because the
    /// selected range is a calendar interval, while a wholly empty response returns
    /// `nil` so the UI cannot mistake absence for a measured zero.
    public static func activitySummary(
        days: [ActivityDay],
        range: ActivityRange,
        calendar: Calendar = .current
    ) -> ActivitySummary? {
        guard !days.isEmpty else { return nil }
        let values = calendarDayValues(days: days, range: range, calendar: calendar)
        guard !values.isEmpty else { return nil }
        let activeDayCount = values.filter { $0.duration > 0 }.count
        let orderedDurations = values.map(\.duration).sorted()
        let middle = orderedDurations.count / 2
        let median = orderedDurations.count.isMultiple(of: 2)
            ? (orderedDurations[middle - 1] + orderedDurations[middle]) / 2
            : orderedDurations[middle]
        let peak = values.sorted {
            $0.duration == $1.duration ? $0.date < $1.date : $0.duration > $1.duration
        }[0]
        return ActivitySummary(
            dayCount: values.count,
            activeDayCount: activeDayCount,
            activeShare: Double(activeDayCount) / Double(values.count),
            peak: peak,
            medianDuration: median
        )
    }

    /// Groups the selected period into calendar weeks, including honest zero weeks.
    ///
    /// Returning no rows for a wholly empty response keeps a network or empty-state
    /// absence distinct from a measured period whose valid rows all happen to be zero.
    public static func weeklyTotals(
        days: [ActivityDay],
        range: ActivityRange,
        calendar: Calendar = .current
    ) -> [WeekTotal] {
        guard !days.isEmpty else { return [] }
        let calendar = configured(calendar, for: range)
        let values = calendarDayValues(days: days, range: range, calendar: calendar)
        let groups = Dictionary(grouping: values) { value in
            calendar.dateInterval(of: .weekOfYear, for: value.date)?.start
                ?? calendar.startOfDay(for: value.date)
        }
        return groups.map { start, values in
            WeekTotal(
                start: start,
                duration: values.reduce(0) { $0 + $1.duration },
                dayCount: values.count,
                isPartial: values.count < 7
            )
        }
        .sorted { $0.start < $1.start }
    }

    /// Builds daily values for the leading buckets of one dimension.
    ///
    /// Leaders are selected by whole-period duration with name-based tie breaking,
    /// then emitted oldest day first and stable series rank second. A missing bucket
    /// is a real zero for that date, while an entirely absent response emits no chart.
    public static func dailyTrends(
        _ dimension: ActivityDimension,
        days: [ActivityDay],
        range: ActivityRange,
        limit: Int = 3,
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        guard !days.isEmpty, limit > 0 else { return [] }
        let calendar = configured(calendar, for: range)
        let dates = calendarDayValues(days: days, range: range, calendar: calendar).map(\.date)
        guard !dates.isEmpty else { return [] }
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        let inRange = days.filter {
            let date = calendar.startOfDay(for: $0.date)
            return date >= start && date <= end
        }
        let leaders = ranked(dimension, in: inRange).prefix(limit)
        guard !leaders.isEmpty else { return [] }

        var valuesByDate: [Date: [String: TimeInterval]] = [:]
        for day in inRange {
            let date = calendar.startOfDay(for: day.date)
            for item in dimension.usage(in: day) {
                valuesByDate[date, default: [:]][item.name, default: 0] += item.duration
            }
        }
        return dates.flatMap { date in
            leaders.enumerated().map { index, leader in
                TrendPoint(
                    date: date,
                    name: leader.name,
                    duration: valuesByDate[date]?[leader.name] ?? 0,
                    seriesIndex: index
                )
            }
        }
    }

    /// Calendar-aligned daily totals for an inclusive range.
    private static func calendarDayValues(
        days: [ActivityDay],
        range: ActivityRange,
        calendar: Calendar
    ) -> [DailyValue] {
        let calendar = configured(calendar, for: range)
        let start = calendar.startOfDay(for: range.start)
        let end = calendar.startOfDay(for: range.end)
        guard start <= end else { return [] }
        let totals = Dictionary(grouping: days, by: { calendar.startOfDay(for: $0.date) })
            .mapValues { $0.reduce(0) { $0 + $1.duration } }
        var values: [DailyValue] = []
        var cursor = start
        while cursor <= end {
            values.append(DailyValue(date: cursor, duration: totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return values
    }

    /// Applies the selected range's time zone to a caller-supplied calendar.
    private static func configured(_ calendar: Calendar, for range: ActivityRange) -> Calendar {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: range.timeZoneIdentifier) ?? calendar.timeZone
        return calendar
    }

    /// Total and active-day count for one weekday across the period.
    public struct WeekdayTotal: Hashable, Sendable, Identifiable {
        /// `Calendar`'s weekday number, 1 for Sunday through 7 for Saturday.
        public let weekday: Int
        /// The weekday's name in the current locale, for the axis label.
        public let name: String
        public let total: TimeInterval
        /// How many days of this weekday fell in the period, so the mean is honest.
        public let dayCount: Int

        public var id: Int { weekday }

        /// Mean time on this weekday, or zero when the period contained none of them.
        public var average: TimeInterval { dayCount > 0 ? total / Double(dayCount) : 0 }
    }

    /// One cell of the activity ribbon: a single day placed on a week × weekday grid.
    public struct DensityCell: Hashable, Sendable, Identifiable {
        public let date: Date
        /// Weeks since the first week of the period, left to right.
        public let weekIndex: Int
        /// `Calendar`'s weekday number, 1 for Sunday through 7 for Saturday.
        public let weekday: Int
        public let duration: TimeInterval
        /// The day's share of the busiest day in the period, in `0...1`.
        public let intensity: Double

        public var id: Date { date }
    }

    /// Totals grouped by day of the week, in calendar order.
    ///
    /// Both the total and the number of days it is spread over are returned. A bar
    /// chart of raw weekday totals silently lies whenever a period does not contain
    /// a whole number of weeks — thirty days holds five Mondays and four Tuesdays —
    /// so the mean is the honest figure and the count is what makes it computable.
    public static func weekdayTotals(days: [ActivityDay], range: ActivityRange, calendar: Calendar = .current) -> [WeekdayTotal] {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: range.timeZoneIdentifier) ?? calendar.timeZone
        var totals: [Int: TimeInterval] = [:]
        var counts: [Int: Int] = [:]
        for day in days {
            let weekday = calendar.component(.weekday, from: day.date)
            totals[weekday, default: 0] += day.duration
            counts[weekday, default: 0] += 1
        }
        let symbols = calendar.shortWeekdaySymbols
        return (1 ... 7).map { weekday in
            WeekdayTotal(
                weekday: weekday,
                name: symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)",
                total: totals[weekday] ?? 0,
                dayCount: counts[weekday] ?? 0
            )
        }
    }

    /// A running total across the period, oldest day first.
    ///
    /// Returned as pairs rather than a bare array because an area chart needs the
    /// real dates on its x-axis; indexing by position would mislabel any period with
    /// a missing day.
    public static func cumulative(days: [ActivityDay]) -> [(date: Date, total: TimeInterval)] {
        var running: TimeInterval = 0
        return days.sorted { $0.date < $1.date }.map { day in
            running += day.duration
            return (day.date, running)
        }
    }

    /// A trailing mean over `window` days, aligned with the sorted daily series.
    ///
    /// The first `window - 1` entries average over the days that exist rather than
    /// padding with zeros, which would draw a downward slope at the start of every
    /// period that is an artefact of the window and not of the user's behaviour.
    public static func rollingAverage(days: [ActivityDay], window: Int = 7) -> [(date: Date, average: TimeInterval)] {
        guard window > 0 else { return [] }
        let sorted = days.sorted { $0.date < $1.date }
        return sorted.indices.map { index in
            let lower = max(0, index - window + 1)
            let slice = sorted[lower ... index]
            let mean = slice.reduce(0) { $0 + $1.duration } / Double(slice.count)
            return (sorted[index].date, mean)
        }
    }

    /// The period laid out as a week × weekday grid, oldest week first.
    ///
    /// Intensity is each day's share of the busiest day, so the ramp always uses its
    /// full range. When nothing was recorded every intensity is zero and the grid
    /// renders as empty cells rather than as the palest colour — absence is not a
    /// small amount.
    public static func density(days: [ActivityDay], range: ActivityRange, calendar: Calendar = .current) -> [DensityCell] {
        var calendar = calendar
        calendar.timeZone = TimeZone(identifier: range.timeZoneIdentifier) ?? calendar.timeZone
        let sorted = days.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        let peak = sorted.map(\.duration).max() ?? 0
        // Anchor on the start of the first day's week so every column holds one week
        // and the weekday rows line up, whatever day the period happens to begin on.
        let anchor = calendar.dateInterval(of: .weekOfYear, for: first.date)?.start ?? calendar.startOfDay(for: first.date)
        return sorted.map { day in
            let elapsed = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: day.date)).day ?? 0
            return DensityCell(
                date: day.date,
                weekIndex: elapsed / 7,
                weekday: calendar.component(.weekday, from: day.date),
                duration: day.duration,
                intensity: peak > 0 ? day.duration / peak : 0
            )
        }
    }

    /// The buckets of one dimension across the period, largest first.
    ///
    /// Ties break on name so the order is stable between refreshes; a list that
    /// reshuffles two equal rows every thirty seconds looks broken.
    public static func ranked(_ dimension: ActivityDimension, in days: [ActivityDay]) -> [Usage] {
        aggregate(days.flatMap { dimension.usage(in: $0) })
            .filter { $0.duration > 0 }
            .sorted { $0.duration == $1.duration ? $0.name < $1.name : $0.duration > $1.duration }
    }

    /// The largest `limit` buckets, with everything past them summed into one row.
    ///
    /// The categorical palette has eight slots and the ninth series is never a
    /// generated ninth hue, so the tail is folded rather than cycled. The folded row
    /// is named for how many buckets it holds, because "Other" on its own tells the
    /// reader nothing about whether it is two rows or two hundred.
    public static func topBuckets(_ usage: [Usage], limit: Int = 7) -> (top: [Usage], remainder: Usage?) {
        guard usage.count > limit else { return (usage, nil) }
        let top = Array(usage.prefix(limit))
        let tail = usage.dropFirst(limit)
        let total = tail.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return (top, nil) }
        return (top, Usage(name: "\(tail.count) More", duration: total))
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
    /// Builds the widget handoff from the days the app just loaded.
    ///
    /// - Parameter generatedAt: The moment the app produced this snapshot. The
    ///   widget uses it to decide whether the data is still inside the retention
    ///   window, so it must be the real write time, not the newest day's date.
    init(days: [ActivityDay], generatedAt: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: generatedAt)
        // `.day` arithmetic can legitimately fail across some calendars; fall back to
        // today rather than trapping, which is what the previous force-unwrap did.
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let current = days.filter { $0.date >= today }.reduce(0) { $0 + $1.duration }
        let week = days.filter { $0.date >= weekStart && $0.date <= generatedAt }.reduce(0) { $0 + $1.duration }
        let project = AnalyticsEngine.aggregate(days.flatMap(\.projects)).max(by: { $0.duration < $1.duration })?.name
        let series = days
            .filter { $0.date >= weekStart }
            .sorted { $0.date < $1.date }
            .map(\.duration)
        self.init(
            generatedAt: generatedAt,
            todayDuration: current,
            weekDuration: week,
            topProject: project,
            dailyDurations: series
        )
    }
}
