// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SerialMonitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SerialCore", targets: ["SerialCore"]),
        .executable(name: "SerialMonitor", targets: ["SerialMonitor"])
    ],
    targets: [
        .target(name: "SerialCore"),
        .executableTarget(
            name: "SerialMonitor",
            dependencies: ["SerialCore"]
        ),
        .testTarget(
            name: "SerialCoreTests",
            dependencies: ["SerialCore"]
        )
    ]
)
