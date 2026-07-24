// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "whisper.spm",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "whisper",
            targets: ["whisper"])
    ],
    targets: [
        .binaryTarget(
            name: "whisper",
            url: "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.5/whisper-v1.8.5-xcframework.zip",
            checksum: "6e7ffd33abc447758d05546c2c151c0bd58cc1ebd495e0bf17583178845b34bd"
        )
    ]
)
