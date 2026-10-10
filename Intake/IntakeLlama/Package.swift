// swift-tools-version: 6.0
import PackageDescription

// llama.cpp's prebuilt Apple xcframework (universal arm64 + x86_64, Metal
// embedded), pinned to one release tag and its SHA-256. To update: change the
// tag in the URL and the checksum together (`swift package compute-checksum`
// on the downloaded zip, or the GitHub release asset digest), then rerun the
// offline-model self-test and eval on a Mac. Kept out of IntakeCore so the
// core package stays model-free and builds and tests anywhere.
let package = Package(
    name: "IntakeLlama",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "IntakeLlama", targets: ["IntakeLlama"]),
    ],
    dependencies: [
        .package(path: "../IntakeCore"),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11552/llama-b11552-xcframework.zip",
            checksum: "ac195b4693da8e250ed778bc66a137912b912c0a6733f9c3e52153d7258172b8"
        ),
        .target(
            name: "IntakeLlama",
            dependencies: [
                "llama",
                .product(name: "IntakeCore", package: "IntakeCore"),
            ]
        ),
    ]
)
