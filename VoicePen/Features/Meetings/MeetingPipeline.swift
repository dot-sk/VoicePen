import Foundation

final class MeetingPipeline {
    static let maximumMeetingDuration: TimeInterval = VoicePenConfig.meetingMaximumRecordingDuration
    static let chunkDuration: TimeInterval = 60

    private let recorder: MeetingRecordingClient
    private let audioPreprocessor: AudioPreprocessingClient
    private let voiceLevelingProcessor: VoiceLevelingProcessor
    private let chunker: MeetingAudioChunker
    private let transcriber: TranscriptionClient
    private let historyStore: MeetingHistoryStore
    private let recoveryAudioStore: MeetingRecoveryAudioStore?
    private let languageProvider: () -> String
    private let speechPreprocessingModeProvider: () -> SpeechPreprocessingMode
    private let meetingVoiceLevelingEnabledProvider: () -> Bool
    private let fileManager: FileManager
    private let chunkProcessingTimeout: Duration

    init(
        recorder: MeetingRecordingClient,
        audioPreprocessor: AudioPreprocessingClient = PassthroughAudioPreprocessingClient(),
        voiceLevelingProcessor: VoiceLevelingProcessor = PassthroughVoiceLevelingProcessor(),
        chunker: MeetingAudioChunker = PassthroughMeetingAudioChunker(),
        transcriber: TranscriptionClient,
        historyStore: MeetingHistoryStore,
        recoveryAudioStore: MeetingRecoveryAudioStore? = nil,
        languageProvider: @escaping () -> String = { VoicePenConfig.defaultLanguage },
        speechPreprocessingModeProvider: @escaping () -> SpeechPreprocessingMode = { .off },
        meetingVoiceLevelingEnabledProvider: @escaping () -> Bool = { false },
        chunkProcessingTimeout: Duration = VoicePenConfig.meetingChunkProcessingTimeout,
        fileManager: FileManager = .default
    ) {
        self.recorder = recorder
        self.audioPreprocessor = audioPreprocessor
        self.voiceLevelingProcessor = voiceLevelingProcessor
        self.chunker = chunker
        self.transcriber = transcriber
        self.historyStore = historyStore
        self.recoveryAudioStore = recoveryAudioStore
        self.languageProvider = languageProvider
        self.speechPreprocessingModeProvider = speechPreprocessingModeProvider
        self.meetingVoiceLevelingEnabledProvider = meetingVoiceLevelingEnabledProvider
        self.fileManager = fileManager
        self.chunkProcessingTimeout = chunkProcessingTimeout
    }

    var sourceStatus: MeetingSourceStatus {
        recorder.sourceStatus
    }

    func start() async throws {
        try await recorder.start()
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
            _ = try? saveFailedEntry(recording: recording, error: TranscriptionError.transcriptionTimedOut)
            try removeTemporaryAudioFiles(cleanupURLs)
            throw CancellationError()
        } catch {
            let entry = try saveFailedEntry(recording: recording, error: error)
            try removeTemporaryAudioFiles(cleanupURLs)
            return entry
        }
    }

    func retryProcessing(_ entry: MeetingHistoryEntry) async throws -> MeetingHistoryEntry {
        guard let recoveryAudio = entry.recoveryAudio else {
            throw MeetingRecordingError.recoveryAudioUnavailable
        }
        try recoveryAudioStore?.validate(recoveryAudio)

        let recording = MeetingRecordingResult(
            startedAt: entry.createdAt.addingTimeInterval(-recoveryAudio.duration),
            endedAt: entry.createdAt,
            chunks: recoveryAudio.chunks,
            sourceFlags: recoveryAudio.sourceFlags,
            errorMessage: nil,
            duration: recoveryAudio.duration
        )

        var cleanupURLs: [URL] = []
        do {
            let chunkingResult = try await chunker.split(
                recording.chunks,
                maximumDuration: Self.maximumMeetingDuration,
                chunkDuration: Self.chunkDuration
            )
            cleanupURLs.append(contentsOf: chunkingResult.temporaryURLs)
            let retryEntry = try await processRecording(
                recording,
                chunks: chunkingResult.chunks,
                entryID: entry.id,
                existingTranscript: entry.transcriptText,
                existingRecoveryAudio: recoveryAudio
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            if retryEntry.status == .completed {
                try recoveryAudioStore?.remove(recoveryAudio)
            }
            return retryEntry
        } catch is CancellationError {
            _ = try? saveFailedEntry(
                recording: recording,
                error: TranscriptionError.transcriptionTimedOut,
                entryID: entry.id,
                existingTranscript: entry.transcriptText,
                recoveryAudio: recoveryAudio
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            throw CancellationError()
        } catch {
            let failedEntry = try saveFailedEntry(
                recording: recording,
                error: error,
                entryID: entry.id,
                existingTranscript: entry.transcriptText,
                recoveryAudio: recoveryAudio
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            return failedEntry
        }
    }

    private func processRecording(
        _ recording: MeetingRecordingResult,
        chunks: [MeetingAudioChunk],
        entryID: UUID = UUID(),
        existingTranscript: String = "",
        existingRecoveryAudio: MeetingRecoveryAudioManifest? = nil
    ) async throws -> MeetingHistoryEntry {
        guard !chunks.isEmpty else {
            throw MeetingRecordingError.noCapturedAudio
        }

        var timings = MeetingPipelineTimings(recording: cappedDuration(recording.duration))
        let language = TranscriptionLanguageResolver.resolve(languageProvider())
        let mode = speechPreprocessingModeProvider()
        let meetingVoiceLevelingEnabled = meetingVoiceLevelingEnabledProvider()
        let orderedChunks = chunks.sorted(by: chunkOrder)
        var transcriptParts: [String] = []
        var modelMetadata: VoiceTranscriptionModelMetadata?
        var skippedChunkCount = 0

        for chunk in orderedChunks {
            try Task.checkCancellation()
            do {
                let processedChunk = try await AsyncOperationTimeout.run(
                    timeout: chunkProcessingTimeout,
                    timeoutError: { TranscriptionError.transcriptionTimedOut },
                    operation: {
                        try await self.processChunk(
                            chunk,
                            mode: mode,
                            language: language,
                            voiceLevelingEnabled: meetingVoiceLevelingEnabled
                        )
                    }
                )

                timings.preprocessing = (timings.preprocessing ?? 0) + processedChunk.preprocessing
                timings.transcription = (timings.transcription ?? 0) + processedChunk.transcription
                modelMetadata = modelMetadata ?? processedChunk.modelMetadata

                if processedChunk.text.isEmpty {
                    skippedChunkCount += 1
                } else {
                    transcriptParts.append(processedChunk.text)
                }
            } catch AudioPreprocessingError.noSpeechDetected {
                skippedChunkCount += 1
                continue
            } catch TranscriptionError.transcriptionTimedOut {
                guard !transcriptParts.isEmpty else {
                    throw TranscriptionError.transcriptionTimedOut
                }
                return try savePartialEntry(
                    recording: recording,
                    transcriptParts: transcriptParts,
                    error: TranscriptionError.transcriptionTimedOut,
                    timings: timings,
                    modelMetadata: modelMetadata,
                    entryID: entryID,
                    existingTranscript: existingTranscript,
                    existingRecoveryAudio: existingRecoveryAudio
                )
            }
        }

        guard skippedChunkCount < orderedChunks.count else {
            throw AudioPreprocessingError.noSpeechDetected
        }

        let transcript = transcriptParts.joined(separator: "\n")
        let durationExceeded = durationLimitExceeded(recording)
        let status: MeetingRecordingStatus = recording.sourceFlags.partial || durationExceeded ? .partial : .completed
        let sourceFlags = MeetingSourceFlags(
            microphoneCaptured: recording.sourceFlags.microphoneCaptured,
            systemAudioCaptured: recording.sourceFlags.systemAudioCaptured,
            partial: status == .partial
        )
        let recoveryAudio: MeetingRecoveryAudioManifest?
        if status == .completed {
            recoveryAudio = nil
        } else {
            recoveryAudio =
                try existingRecoveryAudio
                ?? recoveryAudioStore?.retain(recording: recording, entryID: entryID, createdAt: recording.endedAt)
        }
        let entry = MeetingHistoryEntry(
            id: entryID,
            createdAt: recording.endedAt,
            duration: timings.recording ?? 0,
            transcriptText: transcript,
            status: status,
            sourceFlags: sourceFlags,
            errorMessage: errorMessage(recording: recording, processingError: durationExceeded ? MeetingRecordingError.durationLimitExceeded : nil),
            timings: timings,
            modelMetadata: modelMetadata,
            recoveryAudio: recoveryAudio
        )
        try historyStore.append(entry)
        return entry
    }

    private func processChunk(
        _ chunk: MeetingAudioChunk,
        mode: SpeechPreprocessingMode,
        language: String,
        voiceLevelingEnabled: Bool
    ) async throws -> MeetingProcessedChunk {
        let preprocessed = try await measure {
            try await audioPreprocessor.preprocess(audioURL: chunk.url, mode: mode)
        }

        var transcriptionAudioURL = preprocessed.value
        if voiceLevelingEnabled {
            do {
                transcriptionAudioURL = try await voiceLevelingProcessor.process(audioURL: preprocessed.value)
            } catch {
                AppLogger.info("Meeting voice leveling skipped: \(error.localizedDescription)")
            }
        }

        let transcription = try await measure {
            defer {
                removeTemporaryAudioFileIfNeeded(transcriptionAudioURL, preserving: preprocessed.value)
            }

            return try await transcriber.transcribe(
                audioURL: transcriptionAudioURL,
                glossaryPrompt: "",
                language: language
            )
        }

        let sanitizedText = TranscriptionPostFilter.sanitize(transcription.value.text).trimmed
        return MeetingProcessedChunk(
            text: sanitizedText,
            preprocessing: preprocessed.elapsed,
            transcription: transcription.elapsed,
            modelMetadata: transcription.value.modelMetadata
        )
    }

    private func savePartialEntry(
        recording: MeetingRecordingResult,
        transcriptParts: [String],
        error: Error,
        timings: MeetingPipelineTimings,
        modelMetadata: VoiceTranscriptionModelMetadata?,
        entryID: UUID = UUID(),
        existingTranscript: String = "",
        existingRecoveryAudio: MeetingRecoveryAudioManifest? = nil
    ) throws -> MeetingHistoryEntry {
        let transcript = transcriptParts.joined(separator: "\n")
        let recoveryAudio =
            try existingRecoveryAudio
            ?? recoveryAudioStore?.retain(recording: recording, entryID: entryID, createdAt: recording.endedAt)
        let flags = MeetingSourceFlags(
            microphoneCaptured: recording.sourceFlags.microphoneCaptured,
            systemAudioCaptured: recording.sourceFlags.systemAudioCaptured,
            partial: true
        )
        let entry = MeetingHistoryEntry(
            id: entryID,
            createdAt: recording.endedAt,
            duration: timings.recording ?? cappedDuration(recording.duration),
            transcriptText: transcript.isEmpty ? existingTranscript : transcript,
            status: .partial,
            sourceFlags: flags,
            errorMessage: errorMessage(recording: recording, processingError: error),
            timings: timings,
            modelMetadata: modelMetadata,
            recoveryAudio: recoveryAudio
        )
        try historyStore.append(entry)
        return entry
    }

    private func saveFailedEntry(
        recording: MeetingRecordingResult,
        error: Error,
        entryID: UUID = UUID(),
        existingTranscript: String = "",
        recoveryAudio: MeetingRecoveryAudioManifest? = nil
    ) throws -> MeetingHistoryEntry {
        let duration = cappedDuration(recording.duration)
        let retainedAudio =
            try recoveryAudio
            ?? recoveryAudioStore?.retain(recording: recording, entryID: entryID, createdAt: recording.endedAt)
        let flags = MeetingSourceFlags(
            microphoneCaptured: recording.sourceFlags.microphoneCaptured,
            systemAudioCaptured: recording.sourceFlags.systemAudioCaptured,
            partial: true
        )
        let entry = MeetingHistoryEntry(
            id: entryID,
            createdAt: recording.endedAt,
            duration: duration,
            transcriptText: existingTranscript,
            status: .failed,
            sourceFlags: flags,
            errorMessage: errorMessage(recording: recording, processingError: error),
            timings: MeetingPipelineTimings(recording: duration),
            modelMetadata: nil,
            recoveryAudio: retainedAudio
        )
        try historyStore.append(entry)
        return entry
    }

    private func cappedDuration(_ duration: TimeInterval) -> TimeInterval {
        min(duration, Self.maximumMeetingDuration)
    }

    private func durationLimitExceeded(_ recording: MeetingRecordingResult) -> Bool {
        recording.duration > Self.maximumMeetingDuration
    }

    private func errorMessage(recording: MeetingRecordingResult, processingError: Error?) -> String? {
        let messages = [
            durationLimitExceeded(recording) ? MeetingRecordingError.durationLimitExceeded.localizedDescription : nil,
            recording.errorMessage,
            processingError?.localizedDescription
        ]
        .compactMap { $0?.trimmed }
        .filter { !$0.isEmpty }

        guard !messages.isEmpty else { return nil }
        return Array(NSOrderedSet(array: messages)).compactMap { $0 as? String }.joined(separator: " ")
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

    private func removeTemporaryAudioFileIfNeeded(_ url: URL, preserving preservedURL: URL) {
        guard url != preservedURL,
            fileManager.fileExists(atPath: url.path)
        else {
            return
        }

        try? fileManager.removeItem(at: url)
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

private struct MeetingProcessedChunk: Sendable {
    var text: String
    var preprocessing: TimeInterval
    var transcription: TimeInterval
    var modelMetadata: VoiceTranscriptionModelMetadata?
}
