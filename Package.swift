// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ClaudeCodeRunner", targets: ["ClaudeCodeRunner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "c79c4106b954f81205113c3343e5a7e59a1089b5", traits: []),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.1"),
    ],
    targets: [
        .target(name: "MurmurCore"),
        .target(name: "ClaudeCodeRunner"),
        .target(name: "MurmurEngine",
                dependencies: ["MurmurCore", .product(name: "FluidAudio", package: "FluidAudio")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Murmur",
                          dependencies: ["MurmurEngine", .product(name: "Sparkle", package: "Sparkle")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "murmur-bench", dependencies: ["MurmurEngine"]),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
        .testTarget(name: "ClaudeCodeRunnerTests", dependencies: ["ClaudeCodeRunner"]),
        .testTarget(name: "MurmurTests", dependencies: ["Murmur"]),
    ]
)
