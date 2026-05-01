// swift-tools-version:5.3
import PackageDescription

// old target
//.target(name: "whisper", dependencies:[], cSettings: [
//    .unsafeFlags([
//        "-O3",
//        "-fno-objc-arc",
//        "-DGGML_USE_ACCELERATE",
//        "-DGGML_USE_METAL",
//        "-DWHISPER_USE_COREML",
//        "-DWHISPER_COREML_ALLOW_FALLBACK"])
//]),

#if arch(arm) || arch(arm64)
let platforms: [SupportedPlatform]? = [
    .macOS(.v11),
    .iOS(.v14),
    .watchOS(.v4),
    .tvOS(.v14)
]

let exclude: [String] = ["Sources/whisper/ggml-metal.m", "Sources/whisper/ggml-metal.metal"]
let additionalSources: [String] = []
let additionalSettings: [CSetting] = [
    .define("GGML_USE_METAL")
]

#else
let platforms: [SupportedPlatform]? = nil
let exclude: [String] = ["Sources/whisper/ggml-metal.m", "Sources/whisper/ggml-metal.metal"]
let additionalSources: [String] = []
let additionalSettings: [CSetting] = []
#endif

let package = Package(
    name: "whisper.spm",
    platforms: platforms,
    products: [
        .library(
            name: "whisper",
            targets: ["whisper"])
    ],
    targets: [
        .target(
            name: "whisper",
            dependencies: ["ggml-metal"],
            path: ".",
            exclude: exclude,
            sources: [
                "Sources/whisper/ggml.c",
                "Sources/whisper/ggml-alloc.c",
                "Sources/whisper/ggml-backend.c",
                "Sources/whisper/ggml-quants.c",
                "Sources/whisper/coreml/whisper-encoder-impl.m",
                "Sources/whisper/coreml/whisper-encoder.mm",
                "Sources/whisper/whisper.cpp",
            ] + additionalSources,
            publicHeadersPath: "Sources/whisper/include",
            cSettings: [
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
                .define("GGML_USE_ACCELERATE"),
                .define("WHISPER_USE_COREML"),
                .define("WHISPER_COREML_ALLOW_FALLBACK")
            ] + additionalSettings,
            linkerSettings: [
                .linkedFramework("Accelerate")
            ]
        ),
        .target(
            name: "ggml-metal",
            path: ".",
            exclude: [
                "Sources/whisper/ggml.c",
                "Sources/whisper/ggml-alloc.c",
                "Sources/whisper/ggml-backend.c",
                "Sources/whisper/ggml-quants.c",
                "Sources/whisper/coreml",
                "Sources/whisper/whisper.cpp",
                "Sources/whisper/include",
                "Sources/test-objc",
                "Sources/test-swift"
            ],
            sources: [
                "Sources/whisper/ggml-metal.m"
            ],
            resources: [
                .copy("Sources/whisper/ggml-metal.metal")
            ],
            cSettings: [
                .unsafeFlags(["-fno-objc-arc"]),
                .headerSearchPath("Sources/whisper/include"),
                .define("GGML_SWIFT"),
                .define("GGML_USE_METAL")
            ],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(name: "test-objc",  dependencies:["whisper"]),
        .target(name: "test-swift", dependencies:["whisper"])
    ],
    cxxLanguageStandard: CXXLanguageStandard.cxx11
)
