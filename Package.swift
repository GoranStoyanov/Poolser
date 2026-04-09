// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DonkeyCorn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DonkeyCorn",
            path: "Sources/DonkeyCorn"
        )
    ]
)
