// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FirehawkFocus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FirehawkFocus", targets: ["FirehawkFocus"]),
    ],
    targets: [
        .executableTarget(
            name: "FirehawkFocus",
            path: "Sources/FirehawkFocus",
            resources: [
                .copy("Resources/FocusModel.js"),
                .copy("Resources/Sounds"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "FirehawkFocusTests",
            dependencies: ["FirehawkFocus"],
            path: "Tests/FirehawkFocusTests"
        ),
    ]
)
