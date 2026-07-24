import Foundation

nonisolated enum WhisperCppVoiceActivityDetection {
    private static let resourceName = "ggml-silero-v6.2.0"

    static func bundledModelURL() -> URL? {
        #if SWIFT_PACKAGE
            modelURL(in: .module)
        #else
            modelURL(in: .main)
        #endif
    }

    static func modelURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: resourceName, withExtension: "bin")
            ?? bundle.url(forResource: resourceName, withExtension: "bin", subdirectory: "Resources")
    }

    static func existingModelPath(requested: Bool, modelURL: URL?) -> String? {
        guard requested,
            let modelURL,
            FileManager.default.fileExists(atPath: modelURL.path)
        else {
            return nil
        }
        return modelURL.path
    }

    static func runDecode(
        modelPath: String?,
        decode: (String?) -> Int32
    ) -> Int32 {
        let initialStatus = decode(modelPath)
        guard initialStatus != 0, modelPath != nil else {
            return initialStatus
        }

        AppLogger.info(
            "Whisper VAD decoding failed with status \(initialStatus); retrying without VAD."
        )
        return decode(nil)
    }
}
