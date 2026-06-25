// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Overhear",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
    ],
    targets: [
        .executableTarget(
            name: "Overhear",
            path: "Sources/Overhear"
        ),
    ]
)
