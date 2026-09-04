import Foundation
import SwiftUI
import WakaCore

/// Every user-facing accessibility string, built by pure functions.
///
/// These live apart from the views for one reason: a claim of WCAG 2.2 AA
/// conformance has to be checkable. View bodies cannot be asserted against in a
/// unit test, but these can, so the label text that VoiceOver actually speaks is
/// covered by the suite rather than only by a manual pass.
public enum WakaAccessibility {
    /// Minimum hit target, per WCAG 2.2 SC 2.5.8 (24×24 CSS px) and Apple's stricter
    /// 44×44 point guidance. The larger of the two is used.
    public static let minimumTargetSize: CGFloat = 44

    /// The dashboard's hero figure, spoken as a sentence.
    public static func todayLabel(duration: TimeInterval) -> String {
        "Today, \(DurationFormatter().string(duration)) of coding time"
    }

    /// A metric card, spoken as its title, its value, and what the value means.
    public static func metricLabel(title: String, value: String, detail: String) -> String {
        "\(title): \(value). \(detail)."
    }

    /// One row of a ranked list, spoken with its unit and its share.
    public static func usageLabel(name: String, duration: TimeInterval, percentage: Int) -> String {
        "\(name), \(DurationFormatter().string(duration)), \(percentage)% of the selected period"
    }

    /// A compact share that distinguishes genuine activity below one percent
    /// from an actual zero without adding spoken word clutter.
    public static func sharePercentage(duration: TimeInterval, total: TimeInterval) -> String {
        guard duration > 0, total > 0 else { return "0%" }
        let rounded = Int((duration / total * 100).rounded())
        return rounded > 0 ? "\(rounded)%" : "<1%"
    }

    /// One ranked row using the calculated compact share.
    public static func usageLabel(name: String, duration: TimeInterval, total: TimeInterval) -> String {
        "\(name), \(DurationFormatter().string(duration)), "
            + "\(sharePercentage(duration: duration, total: total)) of the selected period"
    }

    /// Text alternative for the activity chart.
    ///
    /// A `Chart` is invisible to VoiceOver without one. This sentence is the chart's
    /// content, not a description of it, which is what SC 1.1.1 requires.
    public static func chartSummary(durations: [TimeInterval]) -> String {
        guard !durations.isEmpty else { return "No activity recorded in this period." }
        let formatter = DurationFormatter()
        let total = durations.reduce(0, +)
        let activeDays = durations.filter { $0 > 0 }.count
        guard let peak = durations.max(), peak > 0 else {
            return "No activity recorded across \(durations.count) days."
        }
        return "\(formatter.string(total)) across \(durations.count) days, "
            + "\(activeDays) with activity. Busiest day, \(formatter.string(peak))."
    }

    /// Text alternative for any chart of named buckets — a share ring, a comparison
    /// bar chart, a category breakdown.
    ///
    /// Names the leaders and their shares rather than saying "a chart of languages",
    /// because the content is the information and the shape is not.
    public static func shareSummary(title: String, usage: [Usage], spoken: Int = 3) -> String {
        let total = usage.reduce(0) { $0 + $1.duration }
        guard !usage.isEmpty, total > 0 else { return "\(title): nothing recorded in this period." }
        let formatter = DurationFormatter()
        let leaders = usage.prefix(spoken).map { item in
            "\(item.name), \(formatter.string(item.duration)), "
                + sharePercentage(duration: item.duration, total: total)
        }
        let remainder = usage.count - min(spoken, usage.count)
        let tail = remainder > 0 ? " Plus \(remainder) more." : ""
        return "\(title): \(usage.count) in total, \(formatter.string(total)). "
            + leaders.joined(separator: ". ") + "." + tail
    }

    /// Text alternative for the weekday distribution chart.
    public static func weekdaySummary(_ totals: [AnalyticsEngine.WeekdayTotal]) -> String {
        let active = totals.filter { $0.dayCount > 0 && $0.total > 0 }
        guard let busiest = active.max(by: { $0.average < $1.average }) else {
            return "Weekday averages: nothing recorded in this period."
        }
        let formatter = DurationFormatter()
        let spoken = totals
            .filter { $0.dayCount > 0 }
            .map { "\($0.name), \(formatter.string($0.average)) on average" }
            .joined(separator: ". ")
        return "Average coding time by weekday. Busiest is \(busiest.name), "
            + "\(formatter.string(busiest.average)). \(spoken)."
    }

    /// Text alternative for the cumulative-time chart.
    public static func cumulativeSummary(_ running: [(date: Date, total: TimeInterval)]) -> String {
        guard let last = running.last, last.total > 0 else {
            return "Cumulative coding time: nothing recorded in this period."
        }
        let formatter = DurationFormatter()
        return "Cumulative coding time across \(running.count) days, reaching "
            + "\(formatter.string(last.total)) by the end of the period."
    }

    /// Text alternative for the activity ribbon.
    ///
    /// A density grid is the least accessible chart form there is, so its
    /// alternative carries the actual counts rather than a description of a grid.
    public static func densitySummary(_ cells: [AnalyticsEngine.DensityCell]) -> String {
        guard !cells.isEmpty else { return "Activity ribbon: nothing recorded in this period." }
        let formatter = DurationFormatter()
        let active = cells.filter { $0.duration > 0 }
        guard let busiest = cells.max(by: { $0.duration < $1.duration }), busiest.duration > 0 else {
            return "Activity ribbon: no coding recorded across \(cells.count) days."
        }
        return "Activity ribbon. \(active.count) of \(cells.count) days had coding time. "
            + "The busiest was \(formatter.string(busiest.duration))."
    }

    /// Text alternative for the active-day ring and its companion figures.
    public static func activityBalanceSummary(_ summary: AnalyticsEngine.ActivitySummary?) -> String {
        guard let summary, summary.peak.duration > 0 else {
            return "Active day balance: nothing recorded in this period."
        }
        let formatter = DurationFormatter()
        return "\(summary.activeDayCount) of \(summary.dayCount) days had coding time. "
            + "The busiest day was \(formatter.string(summary.peak.duration)), and the median day was "
            + "\(formatter.string(summary.medianDuration))."
    }

    /// Text alternative for calendar-week totals.
    public static func weeklySummary(_ totals: [AnalyticsEngine.WeekTotal]) -> String {
        guard !totals.isEmpty, let peak = totals.max(by: { $0.duration < $1.duration }), peak.duration > 0 else {
            return "Weekly totals: nothing recorded in this period."
        }
        let formatter = DurationFormatter()
        let partialCount = totals.filter(\.isPartial).count
        return "\(totals.count) calendar weeks, totaling \(formatter.string(totals.reduce(0) { $0 + $1.duration })). "
            + "The busiest week recorded \(formatter.string(peak.duration)). "
            + "\(partialCount) weeks cover only part of the selected period."
    }

    /// Text alternative for a bounded collection of daily named-series points.
    public static func trendSummary(title: String, points: [AnalyticsEngine.TrendPoint]) -> String {
        let pointsByName: [String: [AnalyticsEngine.TrendPoint]] = Dictionary(grouping: points, by: \.name)
        let grouped: [Usage] = pointsByName.map { name, values in
            Usage(name: name, duration: values.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.duration == $1.duration ? $0.name < $1.name : $0.duration > $1.duration }
        guard !grouped.isEmpty, grouped.contains(where: { $0.duration > 0 }) else {
            return "\(title): nothing recorded in this period."
        }
        return shareSummary(title: title, usage: grouped, spoken: grouped.count)
    }

    /// Text alternative for a file-type breakdown of one language bucket.
    public static func breakdownSummary(bucket: String, rows: [Usage]) -> String {
        guard !rows.isEmpty else {
            return "No file types could be resolved for \(bucket)."
        }
        let formatter = DurationFormatter()
        let spoken = rows.prefix(5).map { "\($0.name), \(formatter.string($0.duration))" }.joined(separator: ". ")
        return "\(rows.count) file types inside \(bucket). \(spoken)."
    }

    /// What the current load state should say out loud.
    public static func stateLabel(_ state: WakaLoadState) -> String {
        switch state {
        case .signedOut: "Not signed in. Enter a WakaTime API key to continue."
        case .loading: "Loading your analytics."
        case .loaded: "Analytics up to date."
        case .empty: "No coding activity recorded in this period."
        case .stale(let reason): "Showing saved data. \(reason)"
        case .rateLimited: "Refresh paused at WakaTime's request. Saved data is still shown."
        case .expired: "Your WakaTime key was rejected. Sign in again."
        case .credentialUnavailable(let message): "Saved sign-in unavailable. \(message)"
        case .failed(let message): "Could not load analytics. \(message)"
        }
    }
}
