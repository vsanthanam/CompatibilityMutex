// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
]

let package = Package(
    name: "CompatibilityMutex",
    platforms: [
        .macOS(.v12),
        .macCatalyst(.v15),
        .iOS(.v15),
        .watchOS(.v8),
        .tvOS(.v15),
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
