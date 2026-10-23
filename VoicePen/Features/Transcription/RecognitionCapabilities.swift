import Foundation

nonisolated struct RecognitionCapabilities: Equatable, Sendable {
    let timestamps: Bool
    let forcedLanguage: Bool
    let decoderPrompt: Bool
    let configurableDecoding: Bool
    let voiceActivityDetection: Bool
    let fixedLanguageCode: String?

    static let whisper = Self(timestamps: true, forcedLanguage: true, decoderPrompt: true, configurableDecoding: true, voiceActivityDetection: true)
    static let gigaAM = Self(timestamps: true, forcedLanguage: false, decoderPrompt: false, configurableDecoding: false, voiceActivityDetection: false)
    static let nemotron = Self(timestamps: false, forcedLanguage: false, decoderPrompt: false, configurableDecoding: false, voiceActivityDetection: false, fixedLanguageCode: "en")

    init(model: ModelManifestModel) {
        switch model.backendKind {
        case .gigaAM: self = .gigaAM
        case .nemotron: self = .nemotron
        default: self = .whisper
        }
    }

    private init(timestamps: Bool, forcedLanguage: Bool, decoderPrompt: Bool, configurableDecoding: Bool, voiceActivityDetection: Bool, fixedLanguageCode: String? = nil) {
        self.timestamps = timestamps
        self.forcedLanguage = forcedLanguage
        self.decoderPrompt = decoderPrompt
        self.configurableDecoding = configurableDecoding
        self.voiceActivityDetection = voiceActivityDetection
        self.fixedLanguageCode = fixedLanguageCode
    }

    func effectiveLanguage(_ saved: String) -> String {
        fixedLanguageCode ?? (forcedLanguage ? saved : "auto")
    }

    func effectiveDecoding(_ saved: LocalDecodingProfile) -> String {
        configurableDecoding ? saved.rawValue : (fixedLanguageCode == "en" ? "greedy-rnnt" : "greedy-ctc")
    }

    var fixedRecognitionDescription: String {
        fixedLanguageCode == "en" ? "English only, greedy RNNT" : "Automatic multilingual, greedy CTC"
    }

    func effectiveProfile(_ saved: LocalDecodingProfile) -> LocalDecodingProfile {
        configurableDecoding ? saved : .standard
    }

    func effectiveRequest(_ saved: TranscriptionRequest) -> TranscriptionRequest {
        var options = saved.options
        if !timestamps { options.remove(.timestamps) }
        if !voiceActivityDetection { options.remove(.voiceActivityDetection) }
        return TranscriptionRequest(
            audioURL: saved.audioURL, glossaryPrompt: decoderPrompt ? saved.glossaryPrompt : "", language: effectiveLanguage(saved.language), options: options)
    }
}
