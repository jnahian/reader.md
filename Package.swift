// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ReaderMd",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ReaderMd",
            path: "Sources/ReaderMd",
            resources: [
                .copy("Resources/web"),
                .copy("Resources/AppIcon.png")
            ]
        )
    ]
)
