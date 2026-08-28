// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WakaBoard",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "WakaCore", targets: ["WakaCore"])],
    targets: [
        .target(name: "WakaCore"),
        .testTarget(name: "WakaCoreTests", dependencies: ["WakaCore"])
    ]
)
