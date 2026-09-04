// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Overhear",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.0"),
        // Pinned to a minor: on a 0.x package `from:` admits every minor, and
        // FluidAudio's minors move files and change its dependency graph.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.15.6")),
    ],
    targets: [
        .executableTarget(
            name: "Overhear",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Overhear",
            plugins: [.plugin(name: "GenerateAcknowledgements")]
        ),
        // Builds the bundled third-party license notice from the resolved
        // dependency graph, and fails the build when a dependency is added
        // without saying whether it ships. See Resources/acknowledgements.json.
        .plugin(
            name: "GenerateAcknowledgements",
            capability: .buildTool()
        ),
        .testTarget(
            name: "OverhearTests",
            dependencies: ["Overhear"],
            path: "Tests/OverhearTests"
        ),
    ]
)
