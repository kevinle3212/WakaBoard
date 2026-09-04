// swift-tools-version: 6.2
import PackageDescription

/// Strict settings applied to every target.
///
/// Warnings are errors so a warning cannot accumulate into noise that hides the
/// next real one, and the upcoming-feature flags opt in to the stricter Swift 7
/// semantics now rather than discovering them at migration time.
let strictSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .treatAllWarnings(as: .error)
]

let package = Package(
    name: "WakaBoard",
    // Every Apple platform WakaBoard ships on. The floors are the generation that
    // pairs with iOS 18 and macOS 15, which is what the Swift 6 concurrency model and
    // the SwiftUI APIs used here require.
    //
    // visionOS is the exception at 26.0: WidgetKit did not exist on visionOS before
    // then, so a visionOS build with a lower floor cannot carry the widget extension
    // at all — `WidgetCenter` is unavailable and the shared model does not compile.
    // `project.yml` declares the same set, and `node scripts/audit-checks.mjs
    // platforms` fails when the two disagree.
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS("26.0")],
    products: [
        .library(name: "WakaCore", targets: ["WakaCore"]),
        .library(name: "WakaUI", targets: ["WakaUI"])
    ],
    targets: [
        .target(name: "WakaCore", swiftSettings: strictSettings),
        .target(name: "WakaUI", dependencies: ["WakaCore"], swiftSettings: strictSettings),
        .testTarget(name: "WakaCoreTests", dependencies: ["WakaCore"], swiftSettings: strictSettings),
        .testTarget(name: "WakaUITests", dependencies: ["WakaUI", "WakaCore"], swiftSettings: strictSettings)
    ]
)
