import Foundation

final class MeetingPipeline {
    static let maximumMeetingDuration: TimeInterval = 120 * 60
    static let chunkDuration: TimeInterval = 60

    private let recorder: MeetingRecordingClient
    private let audioPreprocessor: AudioPreprocessingClient
    private let chunker: MeetingAudioChunker
    private let transcriber: TranscriptionClient
    private let historyStore: MeetingHistoryStore
    private let languageProvider: () -> String
    private let speechPreprocessingModeProvider: () -> SpeechPreprocessingMode
    private let fileManager: FileManager

    init(
        recorder: MeetingRecordingClient,
        audioPreprocessor: AudioPreprocessingClient = PassthroughAudioPreprocessingClient(),
        chunker: MeetingAudioChunker = PassthroughMeetingAudioChunker(),
        transcriber: TranscriptionClient,
        historyStore: MeetingHistoryStore,
        languageProvider: @escaping () -> String = { VoicePenConfig.defaultLanguage },
        speechPreprocessingModeProvider: @escaping () -> SpeechPreprocessingMode = { .off },
        fileManager: FileManager = .default
    ) {
        self.recorder = recorder
        self.audioPreprocessor = audioPreprocessor
        self.chunker = chunker
        self.transcriber = transcriber
        self.historyStore = historyStore
        self.languageProvider = languageProvider
        self.speechPreprocessingModeProvider = speechPreprocessingModeProvider
        self.fileManager = fileManager
    }

    var sourceStatus: MeetingSourceStatus {
        recorder.sourceStatus
    }

    func start() async throws {
        try await recorder.start()
    }

    func pause() async throws {
        try await recorder.pause()
    }

    func resume() async throws {
        try await recorder.resume()
    }

    func cancel() async throws {
        try await recorder.cancel()
    }

    func stopAndProcess() async throws -> MeetingHistoryEntry {
        let recording = try await recorder.stop()
        return try await process(recording)
    }

    func process(_ recording: MeetingRecordingResult) async throws -> MeetingHistoryEntry {
        var cleanupURLs = recording.temporaryAudioURLs
        do {
            let chunkingResult = try await chunker.split(
                recording.chunks,
                maximumDuration: Self.maximumMeetingDuration,
                chunkDuration: Self.chunkDuration
            )
            cleanupURLs.append(contentsOf: chunkingResult.temporaryURLs)
            let entry = try await processRecording(recording, chunks: chunkingResult.chunks)
            try removeTemporaryAudioFiles(cleanupURLs)
            return entry
        } catch is CancellationError {
            try removeTemporaryAudioFiles(cleanupURLs)
            throw CancellationError()
        } catch {
            let entry = try saveFailedEntry(recording: recording, error: error)
            try removeTemporaryAudioFiles(cleanupURLs)
            return entry
        }
    }

    private func processRecording(
        _ recording: MeetingRecordingResult,
        chunks: [MeetingAudioChunk]
    ) async throws -> MeetingHistoryEntry {
        let cappedChunks = chunks
        guard !cappedChunks.isEmpty else {
            throw MeetingRecordingError.noCapturedAudio
        }

        var timings = MeetingPipelineTimings(recording: cappedChunks.reduce(0) { $0 + $1.duration })
        let language = TranscriptionLanguageResolver.resolve(languageProvider())
        let mode = speechPreprocessingModeProvider()
        let orderedChunks = cappedChunks.sorted(by: chunkOrder)
        var transcriptParts: [String] = []
        var modelMetadata: VoiceTranscriptionModelMetadata?
        var skippedSilentChunkCount = 0

        for chunk in orderedChunks {
            try Task.checkCancellation()
            let preprocessed: (value: URL, elapsed: TimeInterval)
            do {
                preprocessed = try await measure {
                    try await audioPreprocessor.preprocess(audioURL: chunk.url, mode: mode)
                }
            } catch AudioPreprocessingError.noSpeechDetected {
                skippedSilentChunkCount += 1
                continue
            }
            timings.preprocessing = (timings.preprocessing ?? 0) + preprocessed.elapsed

            let transcription = try await measure {
                try await transcriber.transcribe(
                    audioURL: preprocessed.value,
                    glossaryPrompt: "",
                    language: language
                )
            }
            timings.transcription = (timings.transcription ?? 0) + transcription.elapsed
            modelMetadata = modelMetadata ?? transcription.value.modelMetadata

            let text = transcription.value.text.trimmed
            if !text.isEmpty {
                transcriptParts.append(text)
            }
        }

        guard skippedSilentChunkCount < orderedChunks.count else {
            throw AudioPreprocessingError.noSpeechDetected
        }

        let transcript = transcriptParts.joined(separator: "\n")
        let status: MeetingRecordingStatus = recording.sourceFlags.partial ? .partial : .completed
        let entry = MeetingHistoryEntry(
            id: UUID(),
            createdAt: recording.endedAt,
            duration: timings.recording ?? 0,
            transcriptText: transcript,
            status: status,
            sourceFlags: recording.sourceFlags,
            errorMessage: recording.errorMessage,
            timings: timings,
            modelMetadata: modelMetadata
        )
        try historyStore.append(entry)
        return entry
    }

    private func saveFailedEntry(
        recording: MeetingRecordingResult,
        error: Error
    ) throws -> MeetingHistoryEntry {
        let duration = cappedDuration(recording.duration)
        let flags = MeetingSourceFlags(
            microphoneCaptured: recording.sourceFlags.microphoneCaptured,
            systemAudioCaptured: recording.sourceFlags.systemAudioCaptured,
            partial: true
        )
        let entry = MeetingHistoryEntry(
            id: UUID(),
            createdAt: recording.endedAt,
            duration: duration,
            transcriptText: "",
            status: .failed,
            sourceFlags: flags,
            errorMessage: error.localizedDescription,
            timings: MeetingPipelineTimings(recording: duration),
            modelMetadata: nil
        )
        try historyStore.append(entry)
        return entry
    }

    private func cappedDuration(_ duration: TimeInterval) -> TimeInterval {
        min(duration, Self.maximumMeetingDuration)
    }

    private func chunkOrder(_ lhs: MeetingAudioChunk, _ rhs: MeetingAudioChunk) -> Bool {
        if lhs.startOffset != rhs.startOffset {
            return lhs.startOffset < rhs.startOffset
        }

        return sourceOrder(lhs.source) < sourceOrder(rhs.source)
    }

    private func sourceOrder(_ source: MeetingSourceKind) -> Int {
        switch source {
        case .microphone:
            return 0
        case .systemAudio:
            return 1
        }
    }

    private func removeTemporaryAudioFiles(_ urls: [URL]) throws {
        for url in urls where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func measure<T>(_ operation: () async throws -> T) async rethrows -> (value: T, elapsed: TimeInterval) {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try await operation()
        let end = DispatchTime.now().uptimeNanoseconds
        return (value, TimeInterval(end - start) / 1_000_000_000)
    }
}
