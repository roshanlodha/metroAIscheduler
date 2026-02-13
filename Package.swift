// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EMShiftScheduler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "EMShiftSchedulerApp", targets: ["EMShiftSchedulerApp"])
    ],
    targets: [
        .executableTarget(
            name: "EMShiftSchedulerApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "EMShiftSchedulerTests",
            dependencies: ["EMShiftSchedulerApp"]
        )
    ]
)
