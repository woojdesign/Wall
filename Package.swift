// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Wall",
    platforms: [.macOS(.v15)],
    dependencies: [
        // The shared Wooj design system (colors, type, spacing, motion).
        .package(path: "../wooj-tokens"),
        // Sparkle — in-app auto-updates from the GitHub Releases appcast.
        // Same major.minor StickySync ships (2.9.x).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
        // Snapshot testing — visual regression for key views (test target only).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: [
        .executableTarget(
            name: "Wall",
            dependencies: [
                "WallShared",
                .product(name: "WoojTokens", package: "wooj-tokens"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Wall"
        ),
        .executableTarget(
            name: "WallHelper",
            dependencies: ["WallShared"],
            path: "Sources/WallHelper"
        ),
        .target(
            name: "WallShared",
            path: "Sources/WallShared"
        ),
        .testTarget(
            name: "WallTests",
            dependencies: [
                "Wall",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            path: "Tests/WallTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
