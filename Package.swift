// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "CompatibilityMutex",
    platforms: [
        .macOS(.v13),
        .macCatalyst(.v16),
        .iOS(.v16),
        .watchOS(.v9),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "CompatibilityMutex",
            targets: [
                "CompatibilityMutex"
            ]
        ),
    ],
    targets: [
        .target(
            name: "CompatibilityMutex",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CompatibilityMutexTests",
            dependencies: ["CompatibilityMutex"],
            swiftSettings: swiftSettings
        )
    ]
)
