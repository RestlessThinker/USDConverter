// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "USDConverter",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "USDConverter",
            targets: ["USDConverter"]
        ),
        .executable(
            name: "usdconv",
            targets: ["USDConverterCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "USDConverter",
            dependencies: [],
            path: "Sources/USDConverter"
        ),
        .executableTarget(
            name: "USDConverterCLI",
            dependencies: [
                "USDConverter",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/USDConverterCLI"
        ),
        .testTarget(
            name: "USDConverterTests",
            dependencies: ["USDConverter"],
            path: "Tests/USDConverterTests"
        )
    ]
)
