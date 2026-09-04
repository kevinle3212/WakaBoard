import Foundation
import Testing
@testable import WakaCore

@Suite("AdditionalAnalytics")
struct AdditionalAnalyticsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }

    private func range(_ start: String, _ end: String) -> ActivityRange {
        ActivityRange(start: date(start), end: date(end), timeZone: calendar.timeZone)
    }

    @Test("activity summary fills missing dates, aggregates duplicates, and computes an even median")
    func activitySummaryNormalizesCalendarDays() throws {
        let days = [
            ActivityDay(date: date("2026-03-07"), duration: 1_800),
            ActivityDay(date: date("2026-03-08"), duration: 3_600),
            ActivityDay(date: date("2026-03-08"), duration: 1_800),
            ActivityDay(date: date("2026-03-10"), duration: 7_200)
        ]

        let summary = try #require(AnalyticsEngine.activitySummary(
            days: days,
            range: range("2026-03-07", "2026-03-10"),
            calendar: calendar
        ))

        #expect(summary.dayCount == 4)
        #expect(summary.activeDayCount == 3)
        #expect(summary.activeShare == 0.75)
        #expect(summary.medianDuration == 3_600)
        #expect(summary.peak.date == date("2026-03-10"))
        #expect(summary.peak.duration == 7_200)
    }

    @Test("activity summary is absent for an empty range and stable for ties")
    func activitySummaryHandlesEmptyAndTiedInput() throws {
        #expect(AnalyticsEngine.activitySummary(
            days: [],
            range: range("2026-03-07", "2026-03-10"),
            calendar: calendar
        ) == nil)

        let tied = [
            ActivityDay(date: date("2026-03-08"), duration: 3_600),
            ActivityDay(date: date("2026-03-07"), duration: 3_600)
        ]
        let summary = try #require(AnalyticsEngine.activitySummary(
            days: tied,
            range: range("2026-03-07", "2026-03-08"),
            calendar: calendar
        ))
        #expect(summary.peak.date == date("2026-03-07"))
        #expect(summary.medianDuration == 3_600)
    }

    @Test("activity summary includes zero days, ignores out-of-range rows, and computes an odd median")
    func activitySummaryHandlesZerosAndRangeBoundaries() throws {
        let days = [
            ActivityDay(date: date("2026-03-06"), duration: 99_999),
            ActivityDay(date: date("2026-03-07"), duration: .nan),
            ActivityDay(date: date("2026-03-08"), duration: -60),
            ActivityDay(date: date("2026-03-09"), duration: 3_600),
            ActivityDay(date: date("2026-03-10"), duration: 7_200)
        ]
        let summary = try #require(AnalyticsEngine.activitySummary(
            days: days,
            range: range("2026-03-07", "2026-03-11"),
            calendar: calendar
        ))
        #expect(summary.dayCount == 5)
        #expect(summary.activeDayCount == 2)
        #expect(summary.medianDuration == 0)
        #expect(summary.peak.duration == 7_200)
    }

    @Test("reversed ranges cannot emit analytics")
    func reversedRangeIsEmpty() {
        let invalid = range("2026-03-10", "2026-03-07")
        let day = ActivityDay(date: date("2026-03-08"), duration: 600)
        #expect(AnalyticsEngine.activitySummary(days: [day], range: invalid, calendar: calendar) == nil)
        #expect(AnalyticsEngine.weeklyTotals(days: [day], range: invalid, calendar: calendar).isEmpty)
        #expect(AnalyticsEngine.dailyTrends(.projects, days: [day], range: invalid, calendar: calendar).isEmpty)
    }

    @Test("calendar weeks remain correct across daylight saving time and mark partial weeks")
    func weeklyTotalsHonorCalendarBoundaries() {
        let days = [
            ActivityDay(date: date("2026-03-07"), duration: 600),
            ActivityDay(date: date("2026-03-08"), duration: 1_200),
            ActivityDay(date: date("2026-03-09"), duration: 1_800),
            ActivityDay(date: date("2026-03-09"), duration: 600),
            ActivityDay(date: date("2026-03-16"), duration: 3_600)
        ]

        let totals = AnalyticsEngine.weeklyTotals(
            days: days,
            range: range("2026-03-07", "2026-03-16"),
            calendar: calendar
        )

        #expect(totals.count == 3)
        #expect(totals.map(\.dayCount) == [2, 7, 1])
        #expect(totals.map(\.isPartial) == [true, false, true])
        #expect(totals.map(\.duration) == [1_800, 2_400, 3_600])
        #expect(totals.map(\.start) == [date("2026-03-02"), date("2026-03-09"), date("2026-03-16")])
    }

    @Test("weekly totals include zero weeks and return nothing for no loaded data")
    func weeklyTotalsHandleSparseAndEmptyInput() {
        let sparse = AnalyticsEngine.weeklyTotals(
            days: [ActivityDay(date: date("2026-03-07"), duration: 900)],
            range: range("2026-03-07", "2026-03-22"),
            calendar: calendar
        )
        #expect(sparse.count == 3)
        #expect(sparse.map(\.duration) == [900, 0, 0])
        #expect(AnalyticsEngine.weeklyTotals(
            days: [],
            range: range("2026-03-07", "2026-03-22"),
            calendar: calendar
        ).isEmpty)
    }

    @Test("daily trends select a stable bounded top set and fill absent buckets with zero")
    func dailyTrendsAreStableAndBounded() {
        let days = [
            ActivityDay(
                date: date("2026-03-07"),
                duration: 120,
                projects: [Usage(name: "Ωmega", duration: 60), Usage(name: "Beta", duration: 60)]
            ),
            ActivityDay(
                date: date("2026-03-08"),
                duration: 150,
                projects: [Usage(name: "Alpha", duration: 90), Usage(name: "Beta", duration: 60)]
            )
        ]

        let points = AnalyticsEngine.dailyTrends(
            .projects,
            days: days,
            range: range("2026-03-07", "2026-03-09"),
            limit: 2,
            calendar: calendar
        )

        #expect(points.count == 6)
        #expect(Set(points.map(\.name)) == ["Beta", "Alpha"])
        #expect(points.filter { $0.name == "Beta" }.map(\.duration) == [60, 60, 0])
        #expect(points.filter { $0.name == "Alpha" }.map(\.duration) == [0, 90, 0])
        #expect(points.filter { $0.name == "Beta" }.allSatisfy { $0.seriesIndex == 0 })
        #expect(points.filter { $0.name == "Alpha" }.allSatisfy { $0.seriesIndex == 1 })
    }

    @Test("daily trends reject meaningless limits and empty input")
    func dailyTrendsHandleDegenerateInput() {
        let selected = range("2026-03-07", "2026-03-09")
        let day = ActivityDay(date: date("2026-03-07"), duration: 60, projects: [Usage(name: "A", duration: 60)])
        #expect(AnalyticsEngine.dailyTrends(.projects, days: [], range: selected, calendar: calendar).isEmpty)
        #expect(AnalyticsEngine.dailyTrends(.projects, days: [day], range: selected, limit: 0, calendar: calendar).isEmpty)
    }

    @Test("daily trends merge duplicate buckets and work for every dimension")
    func dailyTrendsMergeBucketsAcrossDimensions() {
        let selected = range("2026-03-07", "2026-03-07")
        let day = ActivityDay(
            date: date("2026-03-07"),
            duration: 180,
            projects: [Usage(name: "P", duration: 60), Usage(name: "P", duration: 30)],
            languages: [Usage(name: "Swift", duration: 90)],
            editors: [Usage(name: "Xcode", duration: 90)],
            operatingSystems: [Usage(name: "macOS", duration: 90)],
            categories: [Usage(name: "Coding", duration: 90)]
        )
        for dimension in ActivityDimension.allCases {
            let points = AnalyticsEngine.dailyTrends(dimension, days: [day], range: selected, calendar: calendar)
            #expect(points.count == 1)
            #expect(points[0].duration == 90)
        }
    }

    @Test("public analytics values sanitize hostile construction")
    func publicValuesAreSanitized() {
        let peak = AnalyticsEngine.DailyValue(date: date("2026-03-07"), duration: .infinity)
        #expect(peak.duration == 0)
        let summary = AnalyticsEngine.ActivitySummary(
            dayCount: -2,
            activeDayCount: 99,
            activeShare: .nan,
            peak: peak,
            medianDuration: -60
        )
        #expect(summary.dayCount == 0)
        #expect(summary.activeDayCount == 0)
        #expect(summary.activeShare == 0)
        #expect(summary.medianDuration == 0)

        let week = AnalyticsEngine.WeekTotal(start: date("2026-03-02"), duration: -.infinity, dayCount: 99, isPartial: false)
        #expect(week.duration == 0)
        #expect(week.dayCount == 7)
        let point = AnalyticsEngine.TrendPoint(
            date: date("2026-03-07"),
            name: String(repeating: "界", count: 400),
            duration: -.infinity,
            seriesIndex: -3
        )
        #expect(point.name.count == ResponseBounds.maximumNameLength)
        #expect(point.duration == 0)
        #expect(point.seriesIndex == 0)
    }
}
