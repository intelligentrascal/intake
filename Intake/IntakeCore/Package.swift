// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IntakeCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "IntakeCore", targets: ["IntakeCore"]),
    ],
    targets: [
        .target(name: "IntakeCore"),
        .testTarget(
            name: "IntakeCoreTests",
            dependencies: ["IntakeCore"]
        ),
    ]
)
