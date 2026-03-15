// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuiteEcho",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "QuiteEcho",
            path: "Sources/QuiteEcho",
            resources: [.copy("../../Resources/Info.plist")],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ]
)
