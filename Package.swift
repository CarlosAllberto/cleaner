// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanerCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "CleanerCore", targets: ["CleanerCore"])],
    targets: [
        .target(name: "CleanerCore"),
        .testTarget(name: "CleanerCoreTests", dependencies: ["CleanerCore"]),
    ]
)
