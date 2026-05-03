import Foundation

struct DictationPipelineResult: Equatable {
    let rawText: String
    let finalText: String
    let recording: RecordingResult?
    let didAttemptInsertion: Bool
    let timings: VoicePipelineTimings?
    let modelMetadata: VoiceTranscriptionModelMetadata?
    let diagnosticNotes: [String]
    let insertionAction: TextInsertionAction

    init(
        rawText: String,
        finalText: String,
        recording: RecordingResult? = nil,
        didAttemptInsertion: Bool = false,
        timings: VoicePipelineTimings? = nil,
        modelMetadata: VoiceTranscriptionModelMetadata? = nil,
        diagnosticNotes: [String] = [],
        insertionAction: TextInsertionAction = .paste
    ) {
        self.rawText = rawText
        self.finalText = finalText
        self.recording = recording
        self.didAttemptInsertion = didAttemptInsertion
        self.timings = timings
        self.modelMetadata = modelMetadata
        self.diagnosticNotes = diagnosticNotes
        self.insertionAction = insertionAction
    }
}

final class DictationPipeline {
    private let recorder: AudioRecordingClient
    private let audioPreprocessor: AudioPreprocessingClient
    private let transcriber: TranscriptionClient
    private let dictionaryStore: DictionaryStore
    private let inserter: TextInsertionClient
    private let overlay: OverlayPresenter
    private let userConfigStore: UserConfigStore
    private let languageProvider: () -> String
    private let speechPreprocessingModeProvider: () -> SpeechPreprocessingMode
    private let developerModeOverrideProvider: () -> DeveloperMode?
    private let activeApplicationProvider: () -> ActiveApplicationInfo?
    private let minimumRecordingDuration: TimeInterval
    private var recordingLevelTask: Task<Void, Never>?

    init(
        recorder: AudioRecordingClient,
        audioPreprocessor: AudioPreprocessingClient = PassthroughAudioPreprocessingClient(),
        transcriber: TranscriptionClient,
        dictionaryStore: DictionaryStore,
        inserter: TextInsertionClient,
        overlay: OverlayPresenter,
        userConfigStore: UserConfigStore = UserConfigStore(),
        languageProvider: @escaping () -> String = { VoicePenConfig.defaultLanguage },
        speechPreprocessingModeProvider: @escaping () -> SpeechPreprocessingMode = { .off },
        developerModeOverrideProvider: @escaping () -> DeveloperMode? = { nil },
        activeApplicationProvider: @escaping () -> ActiveApplicationInfo? = { nil },
        minimumRecordingDuration: TimeInterval = VoicePenConfig.minimumRecordingDuration
    ) {
        self.recorder = recorder
        self.audioPreprocessor = audioPreprocessor
        self.transcriber = transcriber
        self.dictionaryStore = dictionaryStore
        self.inserter = inserter
        self.overlay = overlay
        self.userConfigStore = userConfigStore
        self.languageProvider = languageProvider
        self.speechPreprocessingModeProvider = speechPreprocessingModeProvider
        self.developerModeOverrideProvider = developerModeOverrideProvider
        self.activeApplicationProvider = activeApplicationProvider
        self.minimumRecordingDuration = minimumRecordingDuration
    }

    func start() async throws {
        try recorder.startRecording()
        let startedAt = Date()
        await overlay.show(.recording(startedAt: startedAt, level: nil))
        startRecordingLevelUpdates(startedAt: startedAt)
    }

    func stopAndProcess() async throws -> DictationPipelineResult {
        stopRecordingLevelUpdates()

        guard let recording = try recorder.stopRecording() else {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "")
        }
        var timings = VoicePipelineTimings(recording: recording.duration)

        guard recording.duration >= minimumRecordingDuration else {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "")
        }

        await overlay.update(.transcribing(stage: .preparingAudio, progress: nil))
        let transcriptionAudioURL: URL
        do {
            let measured = try await measure {
                try await audioPreprocessor.preprocess(
                    audioURL: recording.url,
                    mode: speechPreprocessingModeProvider()
                )
            }
            transcriptionAudioURL = measured.value
            timings.preprocessing = measured.elapsed
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
        let transcriptionResult: TranscriptionClientResult
        do {
            let measured = try await measure {
                try await transcriber.transcribe(
                    audioURL: transcriptionAudioURL,
                    glossaryPrompt: glossary,
                    language: language
                )
            }
            transcriptionResult = measured.value
            timings.transcription = measured.elapsed
        } catch TranscriptionError.emptyResult {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(rawText: "", finalText: "", recording: nil)
        }
        let rawText = transcriptionResult.text
        try Task.checkCancellation()

        await overlay.update(.transcribing(stage: .normalizing, progress: nil))
        let normalized = try measure { () throws -> DeveloperModeProcessingResult in
            let configResult = userConfigStore.loadConfig()
            let commandResult = DeveloperModeProcessor.process(
                text: rawText,
                config: configResult.config,
                uiOverride: developerModeOverrideProvider(),
                activeApplication: activeApplicationProvider(),
                configDiagnosticNotes: configResult.diagnosticNotes
            )

            guard commandResult.matchedCommandID == nil else {
                return commandResult
            }

            let dictionaryText = try dictionaryStore.makeNormalizer()
                .normalize(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let aliases = configResult.config.aliases.aliases(for: commandResult.activeContext)
            let finalText = AliasNormalizer.normalize(dictionaryText, aliases: aliases)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return DeveloperModeProcessingResult(
                text: finalText,
                diagnosticNotes: commandResult.diagnosticNotes,
                activeContext: commandResult.activeContext
            )
        }
        timings.normalization = normalized.elapsed
        try Task.checkCancellation()
        let developerModeResult = normalized.value
        let processedFinalText = TextOutputNormalizer.normalize(developerModeResult.text)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !processedFinalText.isEmpty else {
            overlay.hide(after: 0.1)
            return DictationPipelineResult(
                rawText: rawText,
                finalText: processedFinalText,
                recording: nil,
                didAttemptInsertion: false,
                modelMetadata: transcriptionResult.modelMetadata,
                diagnosticNotes: developerModeResult.diagnosticNotes,
                insertionAction: developerModeResult.insertionAction
            )
        }

        await overlay.update(.transcribing(stage: .pasting, progress: nil))
        try Task.checkCancellation()
        let insertion = measure {
            inserter.insert(processedFinalText, action: developerModeResult.insertionAction)
        }
        timings.insertion = insertion.elapsed

        overlay.hide(after: 0.1)

        return DictationPipelineResult(
            rawText: rawText,
            finalText: processedFinalText,
            recording: recording,
            didAttemptInsertion: true,
            timings: timings,
            modelMetadata: transcriptionResult.modelMetadata,
            diagnosticNotes: developerModeResult.diagnosticNotes,
            insertionAction: developerModeResult.insertionAction
        )
    }

    private func measure<T>(_ operation: () throws -> T) rethrows -> (value: T, elapsed: TimeInterval) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try operation()
        let end = DispatchTime.now().uptimeNanoseconds
        return (value, TimeInterval(end - start) / 1_000_000_000)
    }

    private func measure<T>(_ operation: () async throws -> T) async rethrows -> (value: T, elapsed: TimeInterval) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try await operation()
        let end = DispatchTime.now().uptimeNanoseconds
        return (value, TimeInterval(end - start) / 1_000_000_000)
    }

    private func startRecordingLevelUpdates(startedAt: Date) {
        recordingLevelTask?.cancel()
        recordingLevelTask = Task { [recorder, overlay] in
            while !Task.isCancelled {
                let level = recorder.currentLevel()
                await overlay.update(.recording(startedAt: startedAt, level: level))

                do {
                    try await Task.sleep(for: VoicePenConfig.recordingLevelRefreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func stopRecordingLevelUpdates() {
        recordingLevelTask?.cancel()
        recordingLevelTask = nil
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
