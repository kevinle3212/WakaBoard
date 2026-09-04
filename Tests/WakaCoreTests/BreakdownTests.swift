import Foundation
import Testing
@testable import WakaCore

@Suite("Breakdown")
struct BreakdownTests {
    private let base: Double = 1_800_000_000

    private func beat(_ offsetMinutes: Double, entity: String, language: String?, type: String? = "file") -> WakaTimeHeartbeat {
        WakaTimeHeartbeat(entity: entity, type: type, language: language, time: base + offsetMinutes * 60)
    }

    @Test("only WakaTime's unresolved buckets can be opened")
    func unresolvedBuckets() {
        #expect(FileTypeBreakdown.isUnresolvedBucket("Other"))
        #expect(FileTypeBreakdown.isUnresolvedBucket("other"))
        #expect(FileTypeBreakdown.isUnresolvedBucket("Unknown"))
        // A real language whose name merely starts with "Other" is not the bucket.
        // A prefix match here would misattribute somebody's actual coding time.
        #expect(!FileTypeBreakdown.isUnresolvedBucket("OtherLang"))
        #expect(!FileTypeBreakdown.isUnresolvedBucket("Swift"))
    }

    @Test("a heartbeat is credited with the gap to the next one, capped at the timeout")
    func attributionJoinsWithinTheTimeout() {
        let beats = [
            beat(0, entity: "/a.mdx", language: "Other"),
            beat(5, entity: "/a.mdx", language: "Other"),
            beat(9, entity: "/a.mdx", language: "Other")
        ]
        let attributed = FileTypeBreakdown.attribute(beats)
        #expect(attributed[0].seconds == 5 * 60)
        #expect(attributed[1].seconds == 4 * 60)
        // Nothing follows the last heartbeat, so there is no evidence of how long it
        // lasted and it is credited with nothing.
        #expect(attributed[2].seconds == 0)
    }

    @Test("a gap longer than the timeout ends the session instead of being counted")
    func attributionDoesNotCountTimeAway() {
        let beats = [
            beat(0, entity: "/a.mdx", language: "Other"),
            // Four hours later. Counting this would credit the user with an afternoon
            // they spent away from the machine.
            beat(240, entity: "/a.mdx", language: "Other"),
            beat(245, entity: "/a.mdx", language: "Other")
        ]
        let attributed = FileTypeBreakdown.attribute(beats)
        #expect(attributed[0].seconds == 0)
        #expect(attributed[1].seconds == 5 * 60)
    }

    @Test("heartbeats arriving out of order are still joined in time order")
    func attributionSortsFirst() {
        let attributed = FileTypeBreakdown.attribute([
            beat(10, entity: "/a.mdx", language: "Other"),
            beat(0, entity: "/a.mdx", language: "Other")
        ])
        #expect(attributed.first?.heartbeat.time == base)
        #expect(attributed.first?.seconds == 600.0)
    }

    @Test("the bucket is broken down by file extension")
    func rowsGroupByExtension() {
        let beats = [
            beat(0, entity: "/repo/docs/guide.mdx", language: "Other"),
            beat(10, entity: "/repo/docs/intro.mdx", language: "Other"),
            beat(14, entity: "/repo/Cargo.toml", language: "Other"),
            beat(20, entity: "/repo/main.swift", language: "Swift"),
            beat(25, entity: "/repo/end.mdx", language: "Other")
        ]
        let rows = FileTypeBreakdown.rows(from: beats, bucket: "Other")
        #expect(rows.map(\.name) == [".mdx", ".toml"])
        // Ten minutes on the first .mdx plus four on the second; six on the .toml.
        #expect(rows.first?.duration == 840.0)
        #expect(rows.last?.duration == 360.0)
    }

    @Test("a file with no extension keeps its own name")
    func extensionlessFilesAreNamed() {
        let rows = FileTypeBreakdown.rows(from: [
            beat(0, entity: "/repo/Makefile", language: nil),
            beat(5, entity: "/repo/Dockerfile", language: nil),
            beat(9, entity: "/repo/Dockerfile", language: nil)
        ], bucket: "Other")
        #expect(rows.map(\.name).sorted() == ["Dockerfile", "Makefile"])
    }

    @Test("a heartbeat with no language belongs to the unresolved bucket")
    func nilLanguageIsUnresolved() {
        let rows = FileTypeBreakdown.rows(from: [
            beat(0, entity: "/a.conf", language: nil),
            beat(5, entity: "/b.swift", language: "Swift")
        ], bucket: "Other")
        #expect(rows.map(\.name) == [".conf"])
        // …and it does not leak into a named language's breakdown.
        #expect(FileTypeBreakdown.rows(from: [beat(0, entity: "/a.conf", language: nil), beat(5, entity: "/b", language: nil)], bucket: "Swift").isEmpty)
    }

    @Test("non-file activity is grouped by what it actually is")
    func nonFileEntities() {
        let rows = FileTypeBreakdown.rows(from: [
            beat(0, entity: "Xcode", language: nil, type: "app"),
            beat(5, entity: "developer.apple.com", language: nil, type: "domain"),
            beat(9, entity: "x", language: nil, type: "app")
        ], bucket: "Other")
        #expect(Set(rows.map(\.name)) == ["Applications", "Web"])
    }

    @Test("the day fan-out is bounded and newest first")
    func dayFanOutIsBounded() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let quarter = ActivityRange(start: end.addingTimeInterval(-89 * 86_400), end: end, timeZone: .gmt)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let days = FileTypeBreakdown.days(in: quarter, calendar: calendar)
        // A ninety-day period must not become ninety requests behind one tap.
        #expect(days.count == FileTypeBreakdown.maximumDays)
        #expect(days.first == calendar.startOfDay(for: end))
        #expect(zip(days, days.dropFirst()).allSatisfy { $0 > $1 })

        let week = ActivityRange(start: end.addingTimeInterval(-6 * 86_400), end: end, timeZone: .gmt)
        #expect(FileTypeBreakdown.days(in: week, calendar: calendar).count == 7)
    }

    @Test("a partial result knows that it is partial")
    func partialResult() {
        let whole = BreakdownResult(rows: [Usage(name: ".mdx", duration: 60)], daysCovered: 7, daysInPeriod: 7)
        let partial = BreakdownResult(rows: [Usage(name: ".mdx", duration: 60)], daysCovered: 14, daysInPeriod: 90)
        #expect(!whole.isPartial)
        #expect(partial.isPartial)
        #expect(whole.total == 60)
    }

    @Test("the heartbeats endpoint validates its day and carries the credential")
    func endpointIsValidated() throws {
        let request = try WakaTimeEndpoint.heartbeats(day: "2026-08-29").request(credential: .personalAPIKey("k"))
        #expect(request.url?.absoluteString == "https://api.wakatime.com/api/v1/users/current/heartbeats?date=2026-08-29")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
        // Anything that is not a calendar day is rejected before a credential is
        // attached to it.
        for bad in ["2026-8-9", "../../etc", "2026-08-29 ", "", "2026-08-2x"] {
            #expect(throws: WakaTimeError.invalidEndpoint) {
                _ = try WakaTimeEndpoint.heartbeats(day: bad).request(credential: .personalAPIKey("k"))
            }
        }
    }

    @Test("a heartbeats response decodes with every optional field absent")
    func decodesSparseHeartbeats() throws {
        let json = #"{"data":[{"time":1800000000},{"entity":"/a.mdx","type":"file","language":null,"time":1800000060}]}"#
        let decoded = try JSONDecoder().decode(WakaTimeHeartbeatsResponse.self, from: Data(json.utf8))
        #expect(decoded.data.count == 2)
        #expect(decoded.data[0].entity == nil)
        #expect(decoded.data[1].language == nil)
    }
}
