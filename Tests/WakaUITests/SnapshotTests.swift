#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
import WakaCore
@testable import WakaUI

/// Renders every screen across widths, Dynamic Type sizes, and both appearances,
/// writes the images to `docs/screenshots/`, and fails when one overflows.
///
/// "Does it look right" is a human judgement and this does not replace it. What it
/// does replace is the part that was being done by hand and therefore not at all:
/// opening five screens at three widths in two appearances and checking that nothing
/// runs off the edge. That is sixty renders, it takes a second, and the images are
/// committed so a person can flip through them instead of rebuilding the app.
///
/// macOS only. `ImageRenderer` needs a real AppKit or UIKit context, and the other
/// platforms' simulator runtimes are not installed — which is the same reason
/// `scripts/build-all.sh` stops at compiling them.
@Suite("Snapshots", .serialized)
@MainActor
struct SnapshotTests {
    /// Widths that matter: a narrow iPhone, an iPad or narrow Mac window, and a wide Mac.
    private static let widths: [(name: String, value: CGFloat)] = [
        ("compact", 320),
        ("regular", 700),
        ("wide", 1_000)
    ]

    /// The default size and an accessibility size. The middle of the range never
    /// breaks a layout; the ends do.
    private static let typeSizes: [(name: String, value: DynamicTypeSize)] = [
        ("default", .large),
        ("accessibility", .accessibility3)
    ]

    private static let schemes: [(name: String, value: ColorScheme)] = [
        ("light", .light),
        ("dark", .dark)
    ]

    /// Where the images land. Committed, so the check produces something a person
    /// can actually look at rather than only a pass or a fail.
    private static var outputDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WakaUITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("docs/screenshots", isDirectory: true)
    }

    /// A model holding a week of plausible activity, matching the default period.
    ///
    /// Built here in the test target and reachable from nowhere else, which is the
    /// same rule the fixture-leak gate enforces: a screen a user sees must never be
    /// able to render invented numbers.
    private func loadedModel() async -> WakaUIModel {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let days = (0 ..< 7).map { offset -> [String: Any] in
            let date = now.addingTimeInterval(Double(offset - 6) * 86_400)
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .gmt
            formatter.dateFormat = "yyyy-MM-dd"
            let seconds = [0, 1_800, 5_400, 9_000, 12_600, 3_600, 7_200][offset % 7]
            return [
                "range": ["date": formatter.string(from: date)],
                "grand_total": ["total_seconds": seconds],
                "projects": [
                    ["name": "WakaBoard", "total_seconds": seconds * 2 / 3],
                    ["name": "dotfiles", "total_seconds": seconds / 3]
                ],
                "languages": [
                    ["name": "Swift", "total_seconds": seconds / 2],
                    ["name": "Markdown", "total_seconds": seconds / 4],
                    ["name": "Other", "total_seconds": seconds / 4]
                ],
                "editors": [["name": "Xcode", "total_seconds": seconds]],
                "operating_systems": [["name": "Mac", "total_seconds": seconds]],
                "categories": [
                    ["name": "Coding", "total_seconds": seconds * 3 / 4],
                    ["name": "Debugging", "total_seconds": seconds / 4]
                ]
            ]
        }
        let body = try! JSONSerialization.data(withJSONObject: ["data": days])
        let client = WakaTimeClient(
            http: CannedHTTPClient(body: body),
            bucket: TokenBucket(capacity: 1_000, refillPerSecond: 1_000, sleep: { _ in }),
            retryPolicy: .none,
            sleep: { _ in },
            jitter: { 1 }
        )
        let cacheURL = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = WakaEnvironment(
            repository: AnalyticsRepository(
                client: client,
                cache: JSONCache(fileURL: cacheURL, version: AnalyticsRepository.cacheSchemaVersion),
                now: { now }
            ),
            client: client,
            credentials: InMemoryCredentialStore(seeded: .personalAPIKey("snapshot-key")),
            snapshots: WidgetSnapshotStore(suiteName: "snapshot.\(UUID().uuidString)")
        )
        let model = WakaUIModel(environment: environment, timeZone: .gmt, now: { now }, reloadWidgets: {})
        await model.refresh()
        return model
    }

    /// The screens this check can rasterize.
    ///
    /// Settings is a platform `Form`, which `ImageRenderer` returns `nil` for — it is
    /// backed by AppKit rather than by SwiftUI primitives, and no amount of framing
    /// changes that. It is not unverified: `scripts/ax-audit.swift` walks the real
    /// Settings screen in the running app and audits its live accessibility tree,
    /// which is a stronger check than a picture of it. Every other screen renders here.
    static var renderableRoutes: [WakaRoute] { WakaRoute.allCases.filter { $0 != .settings } }

    @Test("every screen renders at every width, type size, and appearance without overflowing")
    func rendersEveryScreen() async throws {
        let model = await loadedModel()
        #expect(!model.days.isEmpty, "the snapshot model loaded no data, so the renders would be empty states")

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)

        var written: [String: [NSImage]] = [:]
        for route in Self.renderableRoutes {
            for (widthName, width) in Self.widths {
                for (typeName, typeSize) in Self.typeSizes {
                    for (schemeName, scheme) in Self.schemes {
                        // `wakaFlatLayout` is not a convenience. Every data screen is a
                        // `ScrollView`, and `ImageRenderer` lays a `ScrollView` out at
                        // full height but draws none of its content — the first run of
                        // this check produced sixty blank white images and passed,
                        // because "did not overflow" is trivially true of an empty
                        // picture. The flag swaps the scroll view for a plain stack, and
                        // `isBlank` below is the assertion that would have caught it.
                        let view = WakaDetailView(model: model, selection: route, onConnect: {})
                            .frame(width: width)
                            .environment(\.wakaFlatLayout, true)
                            .environment(\.dynamicTypeSize, typeSize)
                            .environment(\.colorScheme, scheme)
                            .background(scheme == .dark ? Color.black : Color.white)

                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        let image = try #require(
                            renderer.nsImage,
                            "\(route.rawValue) at \(widthName)/\(typeName)/\(schemeName) rendered nothing"
                        )

                        // The one thing a machine can judge here: content that runs
                        // wider than the width it was given has overflowed, and on a
                        // real device that is a clipped card or a truncated number.
                        let where_ = "\(route.rawValue) at \(widthName)/\(typeName)/\(schemeName)"
                        #expect(
                            image.size.width <= width + 1,
                            "\(where_) overflows: \(image.size.width)pt of content in \(width)pt"
                        )
                        #expect(image.size.height > 0)
                        #expect(!Self.isBlank(image), "\(where_) rendered as a blank image")

                        let name = "\(route.rawValue.lowercased())-\(widthName)-\(typeName)-\(schemeName).png"
                        try Self.write(image, to: Self.outputDirectory.appendingPathComponent(name))
                        written[route.rawValue, default: []].append(image)
                    }
                }
            }
        }

        // One sheet per screen, so reviewing a change is opening five files rather
        // than sixty.
        for (route, images) in written {
            let sheet = try #require(Self.contactSheet(images, columns: Self.schemes.count * Self.typeSizes.count))
            try Self.write(sheet, to: Self.outputDirectory.appendingPathComponent("contact-\(route.lowercased()).png"))
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: Self.outputDirectory.path)
        #expect(files.filter { $0.hasSuffix(".png") }.count >= Self.renderableRoutes.count)
    }

    @Test("additional analytics render loaded, empty, and boundary states without clipping")
    func rendersAdditionalAnalyticsStates() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let loadedSummary = AnalyticsEngine.ActivitySummary(
            dayCount: 7,
            activeDayCount: 4,
            activeShare: 4.0 / 7.0,
            peak: AnalyticsEngine.DailyValue(date: start, duration: 7_200),
            medianDuration: 1_800
        )
        let zeroSummary = AnalyticsEngine.ActivitySummary(
            dayCount: 7,
            activeDayCount: 0,
            activeShare: 0,
            peak: AnalyticsEngine.DailyValue(date: start, duration: 0),
            medianDuration: 0
        )
        let loadedWeeks = [
            AnalyticsEngine.WeekTotal(start: start, duration: 3_600, dayCount: 4, isPartial: true),
            AnalyticsEngine.WeekTotal(start: start.addingTimeInterval(604_800), duration: 7_200, dayCount: 7, isPartial: false)
        ]
        let oneWeek = [AnalyticsEngine.WeekTotal(start: start, duration: 900, dayCount: 1, isPartial: true)]
        let loadedTrend = [
            AnalyticsEngine.TrendPoint(date: start, name: "A Very Long Project Name", duration: 900, seriesIndex: 0),
            AnalyticsEngine.TrendPoint(date: start, name: "Ωmega", duration: 600, seriesIndex: 1),
            AnalyticsEngine.TrendPoint(date: start.addingTimeInterval(86_400), name: "A Very Long Project Name", duration: 1_800, seriesIndex: 0),
            AnalyticsEngine.TrendPoint(date: start.addingTimeInterval(86_400), name: "Ωmega", duration: 0, seriesIndex: 1)
        ]
        let onePoint = [AnalyticsEngine.TrendPoint(date: start, name: "Solo", duration: 300, seriesIndex: 0)]
        let cases: [(String, AnyView)] = [
            ("balance-loaded", AnyView(ActivityBalanceChart(summary: loadedSummary))),
            ("balance-empty", AnyView(ActivityBalanceChart(summary: nil))),
            ("balance-zero", AnyView(ActivityBalanceChart(summary: zeroSummary))),
            ("weeks-loaded", AnyView(WeeklyTotalsChart(totals: loadedWeeks))),
            ("weeks-empty", AnyView(WeeklyTotalsChart(totals: []))),
            ("weeks-single", AnyView(WeeklyTotalsChart(totals: oneWeek))),
            ("trend-loaded", AnyView(DailyTrendChart(title: "Projects Trend", points: loadedTrend))),
            ("trend-empty", AnyView(DailyTrendChart(title: "Projects Trend", points: []))),
            ("trend-single", AnyView(DailyTrendChart(title: "Projects Trend", points: onePoint)))
        ]

        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (name, content) in cases {
            let view = content
                .frame(width: 320)
                .environment(\.dynamicTypeSize, .accessibility3)
                .environment(\.colorScheme, .dark)
                .background(Color.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.nsImage, "\(name) rendered nothing")
            #expect(image.size.width <= 321, "\(name) overflows a compact screen")
            #expect(image.size.height > 0)
            #expect(!Self.isBlank(image), "\(name) rendered blank")
            try Self.write(image, to: Self.outputDirectory.appendingPathComponent("additional-\(name).png"))
        }
    }

    /// Whether the render is a single flat colour.
    ///
    /// The check that stops this whole suite from certifying nothing. A blank image
    /// satisfies every geometric assertion here, so without this the suite is a very
    /// thorough way of proving that white rectangles do not overflow.
    private static func isBlank(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return true }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return true }
        var seen: Set<Int> = []
        // A coarse grid rather than every pixel: a screen that is not blank differs
        // somewhere in a 24-point sweep, and reading four megapixels per render would
        // make the suite slower than the thing it is checking.
        for x in stride(from: 0, to: width, by: max(1, width / 24)) {
            for y in stride(from: 0, to: height, by: max(1, height / 24)) {
                guard let colour = bitmap.colorAt(x: x, y: y) else { continue }
                let packed = Int(colour.redComponent * 255) << 16
                    | Int(colour.greenComponent * 255) << 8
                    | Int(colour.blueComponent * 255)
                seen.insert(packed)
                if seen.count > 3 { return false }
            }
        }
        return true
    }

    /// Writes `image` as a PNG.
    private static func write(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed(url.lastPathComponent)
        }
        try png.write(to: url, options: .atomic)
    }

    /// Tiles renders into one reviewable sheet.
    ///
    /// Cells are scaled down to a thumbnail width. At full size a sheet of twelve
    /// two-times renders is an eight-thousand-pixel image several megabytes large, and
    /// the point of the sheet is to be opened and scrolled, not to be the archive —
    /// the individual PNGs beside it are that.
    private static func contactSheet(_ images: [NSImage], columns: Int) -> NSImage? {
        guard !images.isEmpty, columns > 0 else { return nil }
        let gap: CGFloat = 12
        let thumbnailWidth: CGFloat = 320
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let scale = min(1, thumbnailWidth / (images.map(\.size.width).max() ?? thumbnailWidth))
        let cellWidth = (images.map(\.size.width).max() ?? 0) * scale
        let cellHeight = (images.map(\.size.height).max() ?? 0) * scale
        let size = NSSize(
            width: cellWidth * CGFloat(columns) + gap * CGFloat(columns + 1),
            height: cellHeight * CGFloat(rows) + gap * CGFloat(rows + 1)
        )
        guard size.width > 0, size.height > 0 else { return nil }

        let sheet = NSImage(size: size)
        sheet.lockFocus()
        NSColor.darkGray.setFill()
        NSRect(origin: .zero, size: size).fill()
        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = index / columns
            let origin = NSPoint(
                x: gap + CGFloat(column) * (cellWidth + gap),
                // Top-left origin, so the sheet reads in the order the renders were made.
                y: size.height - gap - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap
            )
            image.draw(
                in: NSRect(origin: origin, size: NSSize(width: image.size.width * scale, height: image.size.height * scale)),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        sheet.unlockFocus()
        return sheet
    }

    private enum SnapshotError: Error { case encodingFailed(String) }
}

/// Returns one canned 200 response for every request.
private struct CannedHTTPClient: HTTPClient {
    let body: Data

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.wakatime.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (body, response)
    }
}
#endif
