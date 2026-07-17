// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ChihiroActivityMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ChihiroMonitor", targets: ["ChihiroMonitor"])
    ],
    targets: [
        .target(
            name: "MediaRemoteBridge",
            path: "Sources/MediaRemoteBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "ChihiroMonitor",
            dependencies: ["MediaRemoteBridge"],
            path: "Sources/ChihiroMonitor"
        ),
        .testTarget(
            name: "ChihiroMonitorTests",
            dependencies: ["ChihiroMonitor"],
            path: "Tests/ChihiroMonitorTests"
        )
    ]
)
