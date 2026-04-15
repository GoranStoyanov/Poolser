// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Poolser",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Poolser",
            path: "Sources/Poolser",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("SPM_BUILD")
            ]
        )
    ]
)
