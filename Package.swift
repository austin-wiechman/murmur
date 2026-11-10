// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ClaudeCodeRunner", targets: ["ClaudeCodeRunner"]),
        .library(name: "TranscriptCleanup", targets: ["TranscriptCleanup"]),
        .library(name: "SpeechModels", targets: ["SpeechModels"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git",
                 revision: "c79c4106b954f81205113c3343e5a7e59a1089b5", traits: []),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.10.1"),
    ],
    targets: [
        .target(name: "MurmurCore"),
        .target(name: "ClaudeCodeRunner"),
        .target(name: "TranscriptCleanup"),
        .target(name: "SpeechModels", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]),
        .target(name: "MurmurEngine",
                dependencies: ["TranscriptCleanup", "ClaudeCodeRunner", "SpeechModels",
                              .product(name: "FluidAudio", package: "FluidAudio")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Murmur",
                          dependencies: ["MurmurCore", "MurmurEngine", "TranscriptCleanup", "ClaudeCodeRunner",
                                         .product(name: "Sparkle", package: "Sparkle")],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "murmur-bench", dependencies: ["MurmurCore", "MurmurEngine", "TranscriptCleanup",
                                                                 "ClaudeCodeRunner"]),
        .testTarget(name: "MurmurCoreTests", dependencies: ["MurmurCore"]),
        .testTarget(name: "ClaudeCodeRunnerTests", dependencies: ["ClaudeCodeRunner"]),
        .testTarget(name: "TranscriptCleanupTests", dependencies: ["TranscriptCleanup"]),
        .testTarget(name: "SpeechModelsTests",
                    dependencies: ["SpeechModels", .product(name: "FluidAudio", package: "FluidAudio")]),
        .testTarget(name: "MurmurTests", dependencies: ["Murmur"]),
    ]
)
