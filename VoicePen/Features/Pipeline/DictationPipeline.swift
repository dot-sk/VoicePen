import Foundation

struct DictationPipelineResult: Equatable {
    let rawText: String
    let finalText: String
    let recording: RecordingResult?
    let didAttemptInsertion: Bool

    init(
        rawText: String,
        finalText: String,
        recording: RecordingResult? = nil,
        didAttemptInsertion: Bool = false
    ) {
        self.rawText = rawText
        self.finalText = finalText
        self.recording = recording
        self.didAttemptInsertion = didAttemptInsertion
    }
}

final class DictationPipeline {
    private let recorder: AudioRecordingClient
    private let audioPreprocessor: AudioPreprocessingClient
    private let transcriber: TranscriptionClient
    private let dictionaryStore: DictionaryStore
    private let inserter: TextInsertionClient
    private let overlay: OverlayPresenter
    private let languageProvider: () -> String
    private let speechPreprocessingModeProvider: () -> SpeechPreprocessingMode
    private let minimumRecordingDuration: TimeInterval

    init(
        recorder: AudioRecordingClient,
        audioPreprocessor: AudioPreprocessingClient = PassthroughAudioPreprocessingClient(),
        transcriber: TranscriptionClient,
        dictionaryStore: DictionaryStore,
        inserter: TextInsertionClient,
        overlay: OverlayPresenter,
        languageProvider: @escaping () -> String = { VoicePenConfig.defaultLanguage },
        speechPreprocessingModeProvider: @escaping () -> SpeechPreprocessingMode = { .off },
        minimumRecordingDuration: TimeInterval = VoicePenConfig.minimumRecordingDuration
    ) {
        self.recorder = recorder
        self.audioPreprocessor = audioPreprocessor
        self.transcriber = transcriber
        self.dictionaryStore = dictionaryStore
        self.inserter = inserter
        self.overlay = overlay
        self.languageProvider = languageProvider
        self.speechPreprocessingModeProvider = speechPreprocessingModeProvider
        self.minimumRecordingDuration = minimumRecordingDuration
    }

    func start() async throws {
        try recorder.startRecording()
        await overlay.show(.recording(startedAt: Date(), level: nil))
    }

    func stopAndProcess() async throws -> DictationPipelineResult {
        guard let recording = try recorder.stopRecording() else {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "")
        }

        guard recording.duration >= minimumRecordingDuration else {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "")
        }

        await overlay.update(.transcribing(stage: .preparingAudio, progress: nil))
        let transcriptionAudioURL: URL
        do {
            transcriptionAudioURL = try await audioPreprocessor.preprocess(
                audioURL: recording.url,
                mode: speechPreprocessingModeProvider()
            )
        } catch AudioPreprocessingError.noSpeechDetected {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "", recording: nil)
        }

        try Task.checkCancellation()
        let language = TranscriptionLanguageResolver.resolve(languageProvider())
        let glossary = try glossaryPrompt(
            recording: recording,
            language: language
        )

        await overlay.update(.transcribing(stage: .transcribing, progress: nil))
        let rawText: String
        do {
            rawText = try await transcriber.transcribe(
                audioURL: transcriptionAudioURL,
                glossaryPrompt: glossary,
                language: language
            )
        } catch TranscriptionError.emptyResult {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "", recording: nil)
        }
        try Task.checkCancellation()

        await overlay.update(.transcribing(stage: .normalizing, progress: nil))
        let finalText = try dictionaryStore.makeNormalizer()
            .normalize(rawText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try Task.checkCancellation()

        guard !finalText.isEmpty else {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(
                rawText: rawText,
                finalText: finalText,
                recording: nil,
                didAttemptInsertion: false
            )
        }

        await overlay.update(.transcribing(stage: .pasting, progress: nil))
        try Task.checkCancellation()
        inserter.insert(finalText)

        overlay.update(.done(message: "Inserted"))
        overlay.hide(after: 0.7)

        return DictationPipelineResult(
            rawText: rawText,
            finalText: finalText,
            recording: recording,
            didAttemptInsertion: true
        )
    }

    private func glossaryPrompt(recording: RecordingResult, language: String) throws -> String {
        guard recording.duration > VoicePenConfig.shortRecordingPromptMaximumDuration else {
            return ""
        }

        return try dictionaryStore.promptGlossary(
            limit: VoicePenConfig.glossaryLimit,
            language: language
        )
    }
}
