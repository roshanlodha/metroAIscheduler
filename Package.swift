// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MetroAIScheduler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MetroAISchedulerApp", targets: ["MetroAISchedulerApp"])
    ],
    targets: [
        .executableTarget(
            name: "MetroAISchedulerApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MetroAISchedulerTests",
            dependencies: ["MetroAISchedulerApp"]
        )
    ]
)
