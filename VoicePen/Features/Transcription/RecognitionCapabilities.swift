import Foundation

nonisolated struct RecognitionCapabilities: Equatable, Sendable {
    let timestamps: Bool
    let forcedLanguage: Bool
    let decoderPrompt: Bool
    let configurableDecoding: Bool
    let voiceActivityDetection: Bool

    static let whisper = Self(timestamps: true, forcedLanguage: true, decoderPrompt: true, configurableDecoding: true, voiceActivityDetection: true)
    static let gigaAM = Self(timestamps: true, forcedLanguage: false, decoderPrompt: false, configurableDecoding: false, voiceActivityDetection: false)

    init(model: ModelManifestModel) {
        self = model.backendKind == .gigaAM ? .gigaAM : .whisper
    }

    private init(timestamps: Bool, forcedLanguage: Bool, decoderPrompt: Bool, configurableDecoding: Bool, voiceActivityDetection: Bool) {
        self.timestamps = timestamps
        self.forcedLanguage = forcedLanguage
        self.decoderPrompt = decoderPrompt
        self.configurableDecoding = configurableDecoding
        self.voiceActivityDetection = voiceActivityDetection
    }

    func effectiveProfile(_ saved: LocalDecodingProfile) -> LocalDecodingProfile {
        configurableDecoding ? saved : .standard
    }

    func languageMenuOptions(_ options: [VoicePenMenuLanguageOption]) -> [VoicePenMenuLanguageOption] {
        guard !forcedLanguage else { return options }
        return options.filter { $0.code == "auto" }.map { VoicePenMenuLanguageOption(code: $0.code, name: $0.name, isEnabled: false) }
    }

    func effectiveRequest(_ saved: TranscriptionRequest) -> TranscriptionRequest {
        var options = saved.options
        if !timestamps { options.remove(.timestamps) }
        if !voiceActivityDetection { options.remove(.voiceActivityDetection) }
        return TranscriptionRequest(
            audioURL: saved.audioURL, glossaryPrompt: decoderPrompt ? saved.glossaryPrompt : "", language: forcedLanguage ? saved.language : "auto", options: options)
    }
}
