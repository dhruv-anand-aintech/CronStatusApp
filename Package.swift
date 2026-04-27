// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CronStatusApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CronStatusApp",
            path: "Sources/CronStatusApp",
            resources: [.copy("Resources/AppIcon.icns")]
        )
    ]
)
