// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pq-menubar",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "PQCore", targets: ["PQCore"]),
        .executable(name: "PQMenuBarApp", targets: ["PQMenuBarApp"]),
    ],
    targets: [
        .target(
            name: "PQCore"
        ),
        .executableTarget(
            name: "PQMenuBarApp",
            dependencies: ["PQCore"],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
