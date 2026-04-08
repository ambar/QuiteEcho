// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "QuiteEcho",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "fcbd04d"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "QuiteEcho",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/QuiteEcho",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
