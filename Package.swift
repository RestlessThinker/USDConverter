// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "USDConverter",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "USDConverter",
            targets: ["USDConverter"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "USDConverter",
            dependencies: [],
            path: "Sources/USDConverter"
        ),
        .testTarget(
            name: "USDConverterTests",
            dependencies: ["USDConverter"],
            path: "Tests/USDConverterTests"
        )
    ]
)
