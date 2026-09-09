// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TouchGuard",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TouchGuard",
            path: "Sources/TouchGuard",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
