// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Overhear",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Overhear",
            path: "Sources/Overhear"
        ),
    ]
)
