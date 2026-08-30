// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Overhear",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.58.0"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.0"),
    ],
    targets: [
        .executableTarget(
            name: "Overhear",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
            ],
            path: "Sources/Overhear"
        ),
        .testTarget(
            name: "OverhearTests",
            dependencies: ["Overhear"],
            path: "Tests/OverhearTests"
        ),
    ]
)
