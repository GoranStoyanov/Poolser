// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Poolser",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PoolserKit", targets: ["PoolserKit"])
    ],
    targets: [
        .target(
            name: "PoolserKit",
            path: "Sources/PoolserKit"
        ),
        .executableTarget(
            name: "Poolser",
            dependencies: ["PoolserKit"],
            path: "Sources/Poolser",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("SPM_BUILD")
            ]
        ),
        .testTarget(
            name: "PoolserTests",
            dependencies: ["Poolser", "PoolserKit"],
            path: "Tests/PoolserTests"
        )
    ]
)
