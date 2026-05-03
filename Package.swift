// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VoicePenCore",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .library(name: "VoicePenCore", targets: ["VoicePenCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(path: "Vendor/whisper.spm"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.2.0"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.11.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.1"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
        .package(url: "https://github.com/stencilproject/Stencil.git", from: "0.15.1")
    ],
    targets: [
        .target(
            name: "VoicePenCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "whisper", package: "whisper.spm"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Stencil", package: "Stencil")
            ],
            path: "VoicePen",
            exclude: [
                "VoicePenApp.swift",
                "App/VoicePenMainWindow.swift",
                "App/SettingsViews.swift",
                "Assets.xcassets"
            ],
            resources: [
                .process("Resources/model-manifest.json"),
                .process("Resources/default-config.toml")
            ],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
                .unsafeFlags([
                    "-Xfrontend", "-default-isolation=MainActor",
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-strict-concurrency=complete"
                ])
            ]
        ),
        .testTarget(
            name: "VoicePenUnitTests",
            dependencies: ["VoicePenCore"],
            path: "VoicePenTests",
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
                .unsafeFlags([
                    "-Xfrontend", "-default-isolation=MainActor",
                    "-Xfrontend", "-warn-concurrency",
                    "-Xfrontend", "-strict-concurrency=complete"
                ])
            ]
        )
    ]
)
