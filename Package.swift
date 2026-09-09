// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "FrameCut",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FrameCut", targets: ["FrameCut"])
    ],
    targets: [
        .executableTarget(
            name: "FrameCut",
            path: "Sources/FrameCut"
        ),
        .testTarget(
            name: "FrameCutTests",
            dependencies: ["FrameCut"],
            path: "Tests/FrameCutTests"
        )
    ]
)
