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
            ],
            // Swift 6.4 builds into .build/out/Products/<config>, where
            // Sparkle.framework sits beside the executable, and stopped adding
            // the rpath that used to find it — `swift run ReaderMd` aborted in
            // dyld before reaching main. In the packaged .app nothing is beside
            // the executable, so this falls through to the
            // @executable_path/../Frameworks rpath make-app.sh adds.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path"])
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
