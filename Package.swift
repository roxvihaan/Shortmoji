// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Shortmoji",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Shortmoji", targets: ["Shortmoji"]),
        .library(name: "ShortmojiCore", targets: ["ShortmojiCore"]),
    ],
    targets: [
        .target(
            name: "ShortmojiCore",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Shortmoji",
            dependencies: ["ShortmojiCore"]
        ),
        .testTarget(
            name: "ShortmojiUITests",
            dependencies: ["Shortmoji", "ShortmojiCore"]
        ),
        .testTarget(
            name: "ShortmojiCoreTests",
            dependencies: ["ShortmojiCore"]
        ),
    ]
)
