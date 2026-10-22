// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoicePenDiarization",
    platforms: [.macOS(.v15)],
    products: [.library(name: "VoicePenDiarization", targets: ["VoicePenDiarization"])],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7", traits: [])
    ],
    targets: [
        .target(name: "VoicePenDiarization", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])
    ]
)
