// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReaderMd",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ReaderMd", targets: ["ReaderMd"]),
        .executable(name: "reader", targets: ["ReaderCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "ReaderMd",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/ReaderMd",
            resources: [
                .copy("Resources/web"),
                .copy("Resources/docs"),
                .copy("Resources/AppIcon.png")
            ]
        ),
        .executableTarget(
            name: "ReaderCLI",
            path: "Sources/ReaderCLI"
        ),
        .testTarget(
            name: "ReaderMdTests",
            dependencies: ["ReaderMd", "ReaderCLI"],
            path: "Tests/ReaderMdTests"
        )
    ]
)
