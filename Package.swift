// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FrameCut",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FrameCut", targets: ["FrameCut"])
    ],
    targets: [
        .executableTarget(
            name: "FrameCut",
            path: "Sources/FrameCut",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "FrameCutTests",
            dependencies: ["FrameCut"],
            path: "Tests/FrameCutTests"
        )
    ]
)
