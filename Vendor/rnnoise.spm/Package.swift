// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "rnnoise.spm",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CRNNoise", targets: ["CRNNoise"])
    ],
    targets: [
        .target(
            name: "CRNNoise",
            path: "Sources/CRNNoise",
            sources: [
                "celt_lpc.c",
                "denoise.c",
                "kiss_fft.c",
                "nnet.c",
                "nnet_default.c",
                "parse_lpcnet_weights.c",
                "pitch.c",
                "rnn.c",
                "rnnoise_model.c",
                "rnnoise_tables.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("x86"),
                .define("DISABLE_DEBUG_FLOAT"),
                .define("RNNOISE_BUILD"),
                .define("USE_WEIGHTS_FILE"),
                .unsafeFlags(["-O3"], .when(configuration: .debug))
            ]
        )
    ],
    cLanguageStandard: .c11
)
