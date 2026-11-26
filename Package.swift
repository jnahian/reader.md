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
    targets: [
        .executableTarget(
            name: "ReaderMd",
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
