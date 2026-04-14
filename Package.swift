// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DonkeyHorn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DonkeyHorn",
            path: "Sources/DonkeyHorn",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
