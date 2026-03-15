// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "QuiteEcho",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git", revision: "fcbd04d"),
    ],
    targets: [
        .executableTarget(
            name: "QuiteEcho",
            dependencies: [
                .product(name: "MLXAudioSTT", package: "mlx-audio-swift"),
                .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
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
