// swift-tools-version:6.2
//
// Standalone memory profiler for Qwen3-ASR variants.
// See ../../meta/asr-memory-profiling.md for background and results.
//
// IMPORTANT: The `mlx-audio-swift` revision pinned here MUST match the one
// in the main QuiteEcho Package.swift. If they drift, the compiled Metal
// shaders in the main project's mlx.metallib will not match this package's
// mlx-swift checkout, and model loading will fail at runtime.
import PackageDescription

let package = Package(
    name: "ASRMemProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "fcbd04d"),
    ],
    targets: [
        .executableTarget(
            name: "ASRMemProbe",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
            ],
            path: "Sources/ASRMemProbe"
        ),
    ],
    swiftLanguageModes: [.v5]
)
