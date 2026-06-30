// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZenControl",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ZenControl",
            path: "Sources/ZenControl"
        )
    ]
)
