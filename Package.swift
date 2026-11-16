// swift-tools-version: 6.0
import PackageDescription

let v6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Halodeck",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates from the public GitHub release feed.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "HalodeckCore", swiftSettings: v6),
        .executableTarget(name: "Halodeck",
                          dependencies: ["HalodeckCore", .product(name: "Sparkle", package: "Sparkle")],
                          swiftSettings: v6),
        .testTarget(name: "HalodeckCoreTests", dependencies: ["HalodeckCore"], swiftSettings: v6),
        .testTarget(name: "HalodeckTests", dependencies: ["Halodeck", "HalodeckCore"], swiftSettings: v6),
    ]
)
