// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "transcribe.spm",
    platforms: [.macOS("15.0")],
    products: [.library(name: "VoicePenGigaAM", targets: ["VoicePenGigaAM"])],
    targets: [.binaryTarget(name: "VoicePenGigaAM", path: "Artifacts/VoicePenGigaAM.xcframework")]
)
