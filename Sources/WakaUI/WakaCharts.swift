import Charts
import SwiftUI
import WakaCore

// MARK: - Units

/// The unit a chart's value axis is drawn in.
///
/// Durations arrive in seconds and no chart should ever plot seconds: a thirty-hour
/// month becomes 108,000 on the axis, which is unreadable, and a twenty-minute day
/// becomes 1,200, which is worse. The unit is chosen from the data, once, and every
/// mark and label in that chart uses it — mixing units inside one plot is the
/// fastest way to make a chart lie.
enum ChartUnit {
    case minutes
    case hours

    /// Picks the unit that keeps the largest value in a readable range.
    static func fitting(_ maximum: TimeInterval) -> ChartUnit {
        maximum >= 2 * 3_600 ? .hours : .minutes
    }

    /// The axis title. Title Cased, because it is a label rather than a sentence.
    var axisTitle: String {
        switch self {
        case .minutes: "Minutes"
        case .hours: "Hours"
        }
    }

    /// Converts a duration in seconds into this unit.
    func value(_ duration: TimeInterval) -> Double {
        switch self {
        case .minutes: duration / 60
        case .hours: duration / 3_600
        }
    }
}

/// A chart's frame: a Title Cased heading, the plot, and the text alternative.
///
/// Every chart in WakaBoard is wrapped in this. It is what guarantees the three
/// things a chart cannot ship without — a title that names the content, a caption
/// carrying the same information as prose, and an accessibility label that replaces
/// the plot rather than describing it.
struct ChartFrame<Plot: View>: View {
    let title: String
    let summary: String
    /// An optional sentence under the title explaining what is being measured.
    var note: String?
    @ViewBuilder let plot: Plot

    var body: some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.tight) {
            Text(title).font(.wakaSectionTitle)
            if let note {
                Text(note).font(.wakaCaption).foregroundStyle(.secondary)
            }
            plot
            Text(summary).font(.wakaCaption).foregroundStyle(.secondary)
        }
        .wakaCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(summary)")
    }
}

// MARK: - Daily activity

/// One day on the daily chart.
private struct DailyPoint: Identifiable {
    let date: Date
    let duration: TimeInterval
    let average: TimeInterval
    var id: Date { date }
}

/// Daily coding time, with a trailing seven-day mean drawn over it.
///
/// Two series on one shared value axis, never two axes: a second scale is the single
/// most common way a chart is made to imply a correlation the data does not contain.
public struct ActivityChart: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private let points: [DailyPoint]
    private let unit: ChartUnit

    /// - Parameters:
    ///   - daily: Daily totals, oldest first, paired with their dates.
    ///   - rollingAverage: The trailing mean for the same days, in the same order.
    public init(daily: [(date: Date, duration: TimeInterval)], rollingAverage: [(date: Date, average: TimeInterval)]) {
        let means = Dictionary(rollingAverage.map { ($0.date, $0.average) }, uniquingKeysWith: { first, _ in first })
        self.points = daily.map { DailyPoint(date: $0.date, duration: $0.duration, average: means[$0.date] ?? 0) }
        self.unit = ChartUnit.fitting(daily.map(\.duration).max() ?? 0)
    }

    private var summary: String { WakaAccessibility.chartSummary(durations: points.map(\.duration)) }

    /// The two series names, which are also the legend entries.
    private static let dailyLabel = "Daily Total"
    private static let averageLabel = "7-Day Average"

    public var body: some View {
        ChartFrame(title: "Daily Activity", summary: summary) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(unit.axisTitle, unit.value(point.duration))
                )
                // A rounded top on the data end only, anchored to the baseline: a
                // fully rounded bar detaches from its own axis.
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: WakaDesign.Radius.mark, topTrailingRadius: WakaDesign.Radius.mark))
                .foregroundStyle(by: .value("Series", Self.dailyLabel))

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value(unit.axisTitle, unit.value(point.average))
                )
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
                .foregroundStyle(by: .value("Series", Self.averageLabel))
            }
            .chartForegroundStyleScale(
                domain: [Self.dailyLabel, Self.averageLabel],
                range: [WakaDesign.Palette.series(0, scheme: scheme), WakaDesign.Palette.series(1, scheme: scheme)]
            )
            .chartLegend(position: .top, alignment: .leading, spacing: WakaDesign.Spacing.tight)
            .chartYAxisLabel(unit.axisTitle)
            // Bound the tick count: ninety bars in a narrow window otherwise renders a
            // smear of overlapping date labels.
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: WakaDesign.ChartHeight.regular)
            // Respect Reduce Motion: the transition between periods is animated only
            // when the user has not asked the system to stop animating things.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: points.map(\.duration))
        }
    }
}

// MARK: - Share

/// How one dimension's time divides, drawn as a ring.
///
/// A ring rather than a pie: the hole is where the total goes, which is the number a
/// reader wants first and would otherwise need a second element to find. The tail
/// past the palette's eight slots is folded into one labelled row upstream, never
/// cycled back onto the first hue.
public struct ShareChart: View {
    @Environment(\.colorScheme) private var scheme

    private let title: String
    private let usage: [Usage]
    private let total: TimeInterval

    /// - Parameters:
    ///   - title: A Title Cased heading naming the dimension.
    ///   - usage: Buckets, largest first, already folded to at most eight rows.
    public init(title: String, usage: [Usage]) {
        self.title = title
        self.usage = usage
        self.total = usage.reduce(0) { $0 + $1.duration }
    }

    private var summary: String { WakaAccessibility.shareSummary(title: title, usage: usage) }

    public var body: some View {
        ChartFrame(title: title, summary: summary) {
            if usage.isEmpty || total <= 0 {
                ChartEmptyState()
            } else {
                Chart(Array(usage.enumerated()), id: \.element.id) { index, item in
                    SectorMark(
                        angle: .value("Share", item.duration),
                        innerRadius: .ratio(0.62),
                        // A two-point gap between segments, so adjacent hues never
                        // touch and the boundary is visible without relying on colour.
                        angularInset: 2
                    )
                    .cornerRadius(WakaDesign.Radius.mark)
                    .foregroundStyle(by: .value("Name", item.name))
                    .accessibilityHidden(true)
                    .opacity(index == 0 ? 1 : 0.98)
                }
                .chartForegroundStyleScale(
                    domain: usage.map(\.name),
                    range: usage.indices.map { WakaDesign.Palette.series($0, scheme: scheme) }
                )
                .chartLegend(position: .trailing, alignment: .top, spacing: WakaDesign.Spacing.tight)
                .frame(height: WakaDesign.ChartHeight.regular)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotFrame = proxy.plotFrame {
                            VStack(spacing: WakaDesign.Spacing.hairline) {
                                Text(DurationFormatter().string(total)).font(.wakaMetricNumeral)
                                Text("Total").font(.wakaCaption).foregroundStyle(.secondary)
                            }
                            .position(
                                x: geometry[plotFrame].midX,
                                y: geometry[plotFrame].midY
                            )
                        }
                    }
                }
                .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Comparison

/// Ranked buckets as horizontal bars, each labelled with its own figure.
///
/// Horizontal because the labels are names of arbitrary length, and a vertical bar
/// chart of long names produces rotated axis text that nobody reads. The direct
/// labels are also what satisfies the palette's light-mode relief requirement.
public struct ComparisonChart: View {
    @Environment(\.colorScheme) private var scheme

    private let title: String
    private let usage: [Usage]
    private let unit: ChartUnit

    public init(title: String, usage: [Usage]) {
        self.title = title
        self.usage = usage
        self.unit = ChartUnit.fitting(usage.map(\.duration).max() ?? 0)
    }

    private var summary: String { WakaAccessibility.shareSummary(title: title, usage: usage) }

    public var body: some View {
        ChartFrame(title: title, summary: summary) {
            if usage.isEmpty {
                ChartEmptyState()
            } else {
                Chart(Array(usage.enumerated()), id: \.element.id) { index, item in
                    BarMark(
                        x: .value(unit.axisTitle, unit.value(item.duration)),
                        y: .value("Name", item.name),
                        // Explicit, because the default thickness on a categorical
                        // axis of two or three rows resolves to a hairline that reads
                        // as a rule rather than as a bar.
                        height: .fixed(18)
                    )
                    .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: WakaDesign.Radius.mark, topTrailingRadius: WakaDesign.Radius.mark))
                    .foregroundStyle(WakaDesign.Palette.series(index, scheme: scheme))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(DurationFormatter().string(item.duration))
                            .font(.wakaCaption)
                            .monospacedDigit()
                            // Text wears text tokens, never the series colour.
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .chartXAxisLabel(unit.axisTitle)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: min(WakaDesign.ChartHeight.tall, CGFloat(usage.count) * 38 + 28))
                // Leave room on the trailing edge for the value annotations, which
                // otherwise clip against the plot's own boundary.
                .padding(.trailing, WakaDesign.Spacing.loose)
            }
        }
    }
}

// MARK: - Cumulative

/// Total time accumulated across the period.
public struct CumulativeChart: View {
    @Environment(\.colorScheme) private var scheme

    private let running: [(date: Date, total: TimeInterval)]
    private let unit: ChartUnit

    public init(running: [(date: Date, total: TimeInterval)]) {
        self.running = running
        self.unit = ChartUnit.fitting(running.last?.total ?? 0)
    }

    private var summary: String { WakaAccessibility.cumulativeSummary(running) }

    public var body: some View {
        ChartFrame(
            title: "Cumulative Time",
            summary: summary,
            note: "Every day's coding time added to the days before it."
        ) {
            if running.isEmpty {
                ChartEmptyState()
            } else {
                Chart(running, id: \.date) { point in
                    AreaMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(unit.axisTitle, unit.value(point.total))
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [
                                WakaDesign.Palette.accent(scheme).opacity(0.35),
                                WakaDesign.Palette.accent(scheme).opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(unit.axisTitle, unit.value(point.total))
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(WakaDesign.Palette.accent(scheme))
                }
                .chartYAxisLabel(unit.axisTitle)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: WakaDesign.ChartHeight.regular)
            }
        }
    }
}

// MARK: - Weekday

/// Mean coding time for each day of the week.
public struct WeekdayChart: View {
    @Environment(\.colorScheme) private var scheme

    private let totals: [AnalyticsEngine.WeekdayTotal]
    private let unit: ChartUnit

    public init(totals: [AnalyticsEngine.WeekdayTotal]) {
        self.totals = totals
        self.unit = ChartUnit.fitting(totals.map(\.average).max() ?? 0)
    }

    private var summary: String { WakaAccessibility.weekdaySummary(totals) }

    public var body: some View {
        ChartFrame(
            title: "Weekday Pattern",
            summary: summary,
            note: "The average, not the total, so a period holding five Mondays and four Tuesdays still compares fairly."
        ) {
            Chart(totals) { total in
                BarMark(
                    x: .value("Weekday", total.name),
                    y: .value(unit.axisTitle, unit.value(total.average))
                )
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: WakaDesign.Radius.mark, topTrailingRadius: WakaDesign.Radius.mark))
                .foregroundStyle(WakaDesign.Palette.accent(scheme))
            }
            .chartYAxisLabel(unit.axisTitle)
            .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .frame(height: WakaDesign.ChartHeight.compact)
        }
    }
}

// MARK: - Activity ribbon

/// The period as a week-by-weekday density grid.
///
/// WakaBoard's signature figure, and the one place the app is allowed to be bold.
/// The vernacular is borrowed deliberately from the contribution graph every
/// developer already reads fluently, so the grid needs no explaining. A day with no
/// coding is drawn as an empty cell rather than as the palest step of the ramp:
/// absence is not a small amount, and colouring it would claim activity that did not
/// happen.
public struct ActivityRibbon: View {
    @Environment(\.colorScheme) private var scheme

    private let cells: [AnalyticsEngine.DensityCell]

    public init(cells: [AnalyticsEngine.DensityCell]) { self.cells = cells }

    private var summary: String { WakaAccessibility.densitySummary(cells) }

    /// Weekday row labels, Sunday first.
    ///
    /// The short symbols rather than the very short ones: the very short set is
    /// `S M T W T F S`, and two of those are the same string.
    private var weekdaySymbols: [String] { Calendar.current.shortWeekdaySymbols }

    /// The grid, indexed by weekday row and then by week column.
    private var grid: [[AnalyticsEngine.DensityCell?]] {
        let weeks = (cells.map(\.weekIndex).max() ?? 0) + 1
        var rows = Array(repeating: Array(repeating: AnalyticsEngine.DensityCell?.none, count: weeks), count: 7)
        for cell in cells where (1 ... 7).contains(cell.weekday) && cell.weekIndex < weeks {
            rows[cell.weekday - 1][cell.weekIndex] = cell
        }
        return rows
    }

    public var body: some View {
        ChartFrame(
            title: "Activity Ribbon",
            summary: summary,
            note: "One square per day, darker for more coding time."
        ) {
            if cells.isEmpty {
                ChartEmptyState()
            } else {
                // Plain layout rather than a `Chart`. Swift Charts draws a heatmap of
                // one or two columns as hairlines — the ratio-sized `RectangleMark`
                // collapses — and fighting that produced a grid with no squares in it.
                // A grid of rounded rectangles is fewer lines and renders correctly at
                // every width, which is the whole job here.
                Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                    ForEach(Array(grid.enumerated()), id: \.offset) { row, week in
                        GridRow {
                            Text(weekdaySymbols.indices.contains(row) ? weekdaySymbols[row] : "")
                                .font(.wakaCaption)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                                RoundedRectangle(cornerRadius: WakaDesign.Radius.mark)
                                    .fill(fill(for: cell))
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: 22)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                DensityLegend()
            }
        }
    }

    /// The colour for one cell, or the empty surface where a day holds no coding.
    private func fill(for cell: AnalyticsEngine.DensityCell?) -> Color {
        guard let cell, cell.duration > 0 else {
            return Color.secondary.opacity(scheme == .dark ? 0.16 : 0.10)
        }
        return WakaDesign.Palette.densityStep(for: cell.intensity, scheme: scheme)
    }
}

/// The ribbon's ramp legend: less on the left, more on the right.
private struct DensityLegend: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: WakaDesign.Spacing.hairline) {
            Text("Less").font(.wakaCaption).foregroundStyle(.secondary)
            ForEach(Array(WakaDesign.Palette.density(scheme).enumerated()), id: \.offset) { _, colour in
                RoundedRectangle(cornerRadius: WakaDesign.Radius.swatch).fill(colour).frame(width: 10, height: 10)
            }
            Text("More").font(.wakaCaption).foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Active-day balance

/// Active calendar days versus inactive calendar days, paired with distribution figures.
///
/// This is a proportional ring, not a progress goal: inactive days are context, not
/// failure. Peak and median values sit beside it so the circle never stands in for
/// the numbers a reader came to understand.
public struct ActivityBalanceChart: View {
    @Environment(\.colorScheme) private var scheme

    private struct Slice: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
    }

    private let summary: AnalyticsEngine.ActivitySummary?

    public init(summary: AnalyticsEngine.ActivitySummary?) { self.summary = summary }

    private var spokenSummary: String { WakaAccessibility.activityBalanceSummary(summary) }

    public var body: some View {
        ChartFrame(
            title: "Active Day Balance",
            summary: spokenSummary,
            note: "Days with any coding time compared with the full selected period."
        ) {
            if let summary, summary.peak.duration > 0 {
                VStack(spacing: WakaDesign.Spacing.regular) {
                    Chart([
                        Slice(name: "Active", count: summary.activeDayCount),
                        Slice(name: "Inactive", count: summary.dayCount - summary.activeDayCount)
                    ]) { slice in
                        SectorMark(
                            angle: .value("Days", slice.count),
                            innerRadius: .ratio(0.68),
                            angularInset: 2
                        )
                        .cornerRadius(WakaDesign.Radius.mark)
                        .foregroundStyle(by: .value("Status", slice.name))
                    }
                    .chartForegroundStyleScale(
                        domain: ["Active", "Inactive"],
                        range: [WakaDesign.Palette.accent(scheme), Color.secondary.opacity(0.18)]
                    )
                    .chartLegend(.hidden)
                    .frame(height: WakaDesign.ChartHeight.compact)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(summary.activeDayCount)/\(summary.dayCount)")
                                .font(.wakaMetricNumeral)
                            Text("Active Days").font(.wakaCaption).foregroundStyle(.secondary)
                        }
                    }

                    HStack(alignment: .top, spacing: WakaDesign.Spacing.loose) {
                        figure(
                            title: "Peak Day",
                            value: DurationFormatter().string(summary.peak.duration),
                            detail: summary.peak.date.formatted(.dateTime.month(.abbreviated).day())
                        )
                        figure(
                            title: "Median Day",
                            value: DurationFormatter().string(summary.medianDuration),
                            detail: "Across all calendar days"
                        )
                    }
                }
            } else {
                ChartEmptyState()
            }
        }
    }

    /// One direct numeric figure beneath the proportional ring.
    private func figure(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: WakaDesign.Spacing.hairline) {
            Text(title).font(.wakaCardTitle).foregroundStyle(.secondary)
            Text(value).font(.wakaMetricNumeral)
            Text(detail)
                .font(.wakaCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Calendar weeks

/// Coding time grouped by calendar week in the selected WakaTime time zone.
public struct WeeklyTotalsChart: View {
    @Environment(\.colorScheme) private var scheme

    private let totals: [AnalyticsEngine.WeekTotal]
    private let unit: ChartUnit

    public init(totals: [AnalyticsEngine.WeekTotal]) {
        self.totals = totals
        self.unit = ChartUnit.fitting(totals.map(\.duration).max() ?? 0)
    }

    private var summary: String { WakaAccessibility.weeklySummary(totals) }

    public var body: some View {
        ChartFrame(
            title: "Calendar Weeks",
            summary: summary,
            note: "Edge weeks may cover only part of the selected period."
        ) {
            if totals.isEmpty || !totals.contains(where: { $0.duration > 0 }) {
                ChartEmptyState()
            } else {
                Chart(totals) { week in
                    BarMark(
                        x: .value("Week", week.start, unit: .weekOfYear),
                        y: .value(unit.axisTitle, unit.value(week.duration))
                    )
                    .clipShape(UnevenRoundedRectangle(
                        topLeadingRadius: WakaDesign.Radius.mark,
                        topTrailingRadius: WakaDesign.Radius.mark
                    ))
                    .foregroundStyle(WakaDesign.Palette.accent(scheme))
                    .opacity(week.isPartial ? 0.55 : 1)
                }
                .chartYAxisLabel(unit.axisTitle)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: WakaDesign.ChartHeight.regular)
            }
        }
    }
}

// MARK: - Daily trends

/// Daily movement for the leading buckets of a selected dimension.
public struct DailyTrendChart: View {
    @Environment(\.colorScheme) private var scheme

    private let title: String
    private let points: [AnalyticsEngine.TrendPoint]
    private let series: [String]
    private let unit: ChartUnit

    public init(title: String, points: [AnalyticsEngine.TrendPoint]) {
        self.title = title
        self.points = points
        let pointsByName: [String: [AnalyticsEngine.TrendPoint]] = Dictionary(grouping: points, by: \.name)
        var rankedSeries: [(name: String, index: Int)] = []
        for (name, values) in pointsByName {
            var lowestIndex = Int.max
            for value in values { lowestIndex = min(lowestIndex, value.seriesIndex) }
            rankedSeries.append((name, lowestIndex == Int.max ? 0 : lowestIndex))
        }
        rankedSeries.sort { $0.index == $1.index ? $0.name < $1.name : $0.index < $1.index }
        self.series = rankedSeries.map(\.name)
        self.unit = ChartUnit.fitting(points.map(\.duration).max() ?? 0)
    }

    private var summary: String { WakaAccessibility.trendSummary(title: title, points: points) }

    public var body: some View {
        ChartFrame(
            title: title,
            summary: summary,
            note: "Daily movement for the three largest buckets in this period."
        ) {
            if points.isEmpty || !points.contains(where: { $0.duration > 0 }) {
                ChartEmptyState()
            } else {
                Chart(points) { point in
                    LineMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(unit.axisTitle, unit.value(point.duration))
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(by: .value("Series", point.name))
                    .symbol(by: .value("Series", point.name))

                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value(unit.axisTitle, unit.value(point.duration))
                    )
                    .foregroundStyle(by: .value("Series", point.name))
                    .symbol(by: .value("Series", point.name))
                }
                .chartForegroundStyleScale(
                    domain: series,
                    range: series.indices.map { WakaDesign.Palette.series($0, scheme: scheme) }
                )
                .chartLegend(position: .top, alignment: .leading, spacing: WakaDesign.Spacing.tight)
                .chartYAxisLabel(unit.axisTitle)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: WakaDesign.ChartHeight.regular)
            }
        }
    }
}

// MARK: - Empty plot

/// What a chart shows when the period holds nothing to plot.
///
/// A blank rectangle reads as a rendering failure. This says which it is.
struct ChartEmptyState: View {
    var body: some View {
        Text("Nothing recorded in this period.")
            .font(.wakaCaption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: WakaDesign.ChartHeight.compact)
            .accessibilityHidden(true)
    }
}
