// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SPMDependencyTracker",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DependencyTrackerCore", targets: ["DependencyTrackerCore"]),
        .executable(name: "spm-dep-tracker", targets: ["DependencyTrackerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/mxcl/Version.git", from: "2.1.0"),
        .package(url: "https://github.com/tuist/XcodeProj.git", from: "9.10.1"),
        .package(url: "https://github.com/kylef/PathKit.git", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "DependencyTrackerCore",
            dependencies: [
                .product(name: "Version", package: "Version"),
                .product(name: "XcodeProj", package: "XcodeProj"),
                .product(name: "PathKit", package: "PathKit"),
            ]
        ),
        .executableTarget(
            name: "DependencyTrackerCLI",
            dependencies: [
                "DependencyTrackerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "DependencyTrackerCoreTests",
            dependencies: ["DependencyTrackerCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "DependencyTrackerCLITests",
            dependencies: ["DependencyTrackerCLI", "DependencyTrackerCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
