import Foundation

final class MeetingPipeline {
    static let maximumMeetingDuration: TimeInterval = VoicePenConfig.meetingMaximumRecordingDuration
    static let chunkDuration: TimeInterval = 60
    private static let asrProgressFractionWhenDiarizing = 0.85
    private static let finishingProgressFractionWhenDiarizing = 0.98

    private let recorder: MeetingRecordingClient
    private let audioPreprocessor: AudioPreprocessingClient
    private let voiceLevelingProcessor: VoiceLevelingProcessor
    private let chunker: MeetingAudioChunker
    private let audioFileIO: MeetingAudioFileIO
    private let transcriber: TranscriptionClient
    private let diarizer: MeetingDiarizationClient?
    private let historyStore: MeetingHistoryStore
    private let recoveryAudioStore: MeetingRecoveryAudioStore?
    private let savedAudioScheduler: SavedAudioArchiveScheduling
    private let languageProvider: () -> String
    private let speechPreprocessingModeProvider: () -> SpeechPreprocessingMode
    private let meetingVoiceLevelingEnabledProvider: () -> Bool
    private let saveMeetingAudioEnabledProvider: () -> Bool
    private let savedAudioStorageLimitGBProvider: () -> Int
    private let meetingTranscriptTimecodesEnabledProvider: () -> Bool
    private let meetingDiarizationEnabledProvider: () -> Bool
    private let meetingDiarizationBackendProvider: @MainActor () -> MeetingDiarizationBackend
    private let appVersionProvider: () -> String
    private let nowProvider: () -> Date
    private var processingProgressHandler: @MainActor (MeetingProcessingProgress?) -> Void = { _ in }
    private let fileManager: FileManager
    private let chunkProcessingTimeout: Duration
    private let processingCancellationState = MeetingProcessingCancellationState()

    init(
        recorder: MeetingRecordingClient,
        audioPreprocessor: AudioPreprocessingClient = PassthroughAudioPreprocessingClient(),
        voiceLevelingProcessor: VoiceLevelingProcessor = PassthroughVoiceLevelingProcessor(),
        chunker: MeetingAudioChunker = PassthroughMeetingAudioChunker(),
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO(),
        transcriber: TranscriptionClient,
        diarizer: MeetingDiarizationClient? = nil,
        historyStore: MeetingHistoryStore,
        recoveryAudioStore: MeetingRecoveryAudioStore? = nil,
        savedAudioScheduler: SavedAudioArchiveScheduling = NoOpSavedAudioArchiveScheduler(),
        languageProvider: @escaping () -> String = { VoicePenConfig.defaultLanguage },
        speechPreprocessingModeProvider: @escaping () -> SpeechPreprocessingMode = { .off },
        meetingVoiceLevelingEnabledProvider: @escaping () -> Bool = { false },
        saveMeetingAudioEnabledProvider: @escaping () -> Bool = { false },
        savedAudioStorageLimitGBProvider: @escaping () -> Int = { VoicePenConfig.defaultSavedAudioStorageLimitGB },
        meetingTranscriptTimecodesEnabledProvider: @escaping () -> Bool = { true },
        meetingDiarizationEnabledProvider: @escaping () -> Bool = { false },
        meetingDiarizationBackendProvider: @escaping @MainActor () -> MeetingDiarizationBackend = { .speakerKit },
        appVersionProvider: @escaping () -> String = { VoicePenConfig.appVersion },
        nowProvider: @escaping () -> Date = Date.init,
        chunkProcessingTimeout: Duration = VoicePenConfig.meetingChunkProcessingTimeout,
        fileManager: FileManager = .default
    ) {
        self.recorder = recorder
        self.audioPreprocessor = audioPreprocessor
        self.voiceLevelingProcessor = voiceLevelingProcessor
        self.chunker = chunker
        self.audioFileIO = audioFileIO
        self.transcriber = transcriber
        self.diarizer = diarizer
        self.historyStore = historyStore
        self.recoveryAudioStore = recoveryAudioStore
        self.savedAudioScheduler = savedAudioScheduler
        self.languageProvider = languageProvider
        self.speechPreprocessingModeProvider = speechPreprocessingModeProvider
        self.meetingVoiceLevelingEnabledProvider = meetingVoiceLevelingEnabledProvider
        self.saveMeetingAudioEnabledProvider = saveMeetingAudioEnabledProvider
        self.savedAudioStorageLimitGBProvider = savedAudioStorageLimitGBProvider
        self.meetingTranscriptTimecodesEnabledProvider = meetingTranscriptTimecodesEnabledProvider
        self.meetingDiarizationEnabledProvider = meetingDiarizationEnabledProvider
        self.meetingDiarizationBackendProvider = meetingDiarizationBackendProvider
        self.appVersionProvider = appVersionProvider
        self.nowProvider = nowProvider
        self.fileManager = fileManager
        self.chunkProcessingTimeout = chunkProcessingTimeout
    }

    func setProcessingProgressHandler(_ handler: @escaping @MainActor (MeetingProcessingProgress?) -> Void) {
        processingProgressHandler = handler
    }

    func prepareForProcessingCancellation(_ reason: MeetingProcessingCancellationReason) {
        processingCancellationState.set(reason)
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

    func process(
        _ recording: MeetingRecordingResult
    ) async throws -> MeetingHistoryEntry {
        processingCancellationState.clear()
        var cleanupURLs = recording.temporaryAudioURLs
        let meetingDiarizationBackend = await MainActor.run { meetingDiarizationBackendProvider() }
        let entryID = UUID()
        do {
            let chunkingResult = try await chunker.split(
                recording.chunks,
                maximumDuration: Self.processingDuration(for: recording),
                chunkDuration: Self.chunkDuration
            )
            cleanupURLs.append(contentsOf: chunkingResult.temporaryURLs)
            archiveSavedMeetingAudio(
                chunks: chunkingResult.chunks,
                sourceSpans: chunkingResult.sourceSpans,
                capturedAt: recording.startedAt,
                owner: .meetingHistory(entryID)
            )
            let meetingDiarizationEnabled = meetingDiarizationEnabledProvider()
            let entry = try await processRecording(
                recording,
                chunks: chunkingResult.chunks,
                sourceSpans: chunkingResult.sourceSpans,
                meetingDiarizationEnabled: meetingDiarizationEnabled,
                meetingDiarizationBackend: meetingDiarizationBackend,
                entryID: entryID
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            return entry
        } catch is CancellationError {
            let cancellationError = Self.processingCancellationError(
                for: processingCancellationState.take(default: .timedOut)
            )
            _ = try? saveFailedEntry(
                recording: recording,
                error: cancellationError,
                entryID: entryID
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            throw CancellationError()
        } catch MeetingPipelineNoSpeechError.noSpeechDetected {
            try removeTemporaryAudioFiles(cleanupURLs)
            throw MeetingPipelineNoSpeechError.noSpeechDetected
        } catch {
            let entry = try saveFailedEntry(
                recording: recording,
                error: error,
                entryID: entryID,
                speakerCount: nil
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            return entry
        }
    }

    func retryProcessing(_ entry: MeetingHistoryEntry) async throws -> MeetingHistoryEntry {
        processingCancellationState.clear()
        guard let recoveryAudio = entry.recoveryAudio else {
            throw MeetingRecordingError.recoveryAudioUnavailable
        }
        try recoveryAudioStore?.validate(recoveryAudio, now: nowProvider())

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
            let meetingDiarizationBackend = await MainActor.run { meetingDiarizationBackendProvider() }
            let chunkingResult = try await chunker.split(
                recording.chunks,
                maximumDuration: Self.processingDuration(for: recording),
                chunkDuration: Self.chunkDuration
            )
            cleanupURLs.append(contentsOf: chunkingResult.temporaryURLs)
            let meetingDiarizationEnabled = meetingDiarizationEnabledProvider()
            let retryEntry = try await processRecording(
                recording,
                chunks: chunkingResult.chunks,
                sourceSpans: chunkingResult.sourceSpans,
                meetingDiarizationEnabled: meetingDiarizationEnabled,
                meetingDiarizationBackend: meetingDiarizationBackend,
                entryID: entry.id,
                existingTranscript: entry.transcriptText,
                existingRecoveryAudio: recoveryAudio,
                existingSpeakerCount: entry.speakerCount
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            return retryEntry
        } catch is CancellationError {
            let cancellationReason = processingCancellationState.take(default: .timedOut)
            guard cancellationReason != .userCancelled else {
                try removeTemporaryAudioFiles(cleanupURLs)
                throw CancellationError()
            }
            let cancellationError = Self.processingCancellationError(for: cancellationReason)
            _ = try? saveFailedEntry(
                recording: recording,
                error: cancellationError,
                entryID: entry.id,
                existingTranscript: entry.transcriptText,
                recoveryAudio: recoveryAudio,
                speakerCount: entry.speakerCount
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            throw CancellationError()
        } catch {
            let failedEntry = try saveFailedEntry(
                recording: recording,
                error: error,
                entryID: entry.id,
                existingTranscript: entry.transcriptText,
                recoveryAudio: recoveryAudio,
                speakerCount: entry.speakerCount
            )
            try removeTemporaryAudioFiles(cleanupURLs)
            return failedEntry
        }
    }

    private func processRecording(
        _ recording: MeetingRecordingResult,
        chunks: [MeetingAudioChunk],
        sourceSpans: [MeetingAudioSourceSpan],
        meetingDiarizationEnabled: Bool,
        meetingDiarizationBackend: MeetingDiarizationBackend,
        entryID: UUID = UUID(),
        existingTranscript: String = "",
        existingRecoveryAudio: MeetingRecoveryAudioManifest? = nil,
        existingSpeakerCount: Int? = nil
    ) async throws -> MeetingHistoryEntry {
        guard !chunks.isEmpty else {
            throw MeetingRecordingError.noCapturedAudio
        }

        var timings = MeetingPipelineTimings(recording: recording.duration)
        let language = TranscriptionLanguageResolver.resolve(languageProvider())
        let mode = speechPreprocessingModeProvider()
        let meetingVoiceLevelingEnabled = meetingVoiceLevelingEnabledProvider()
        let meetingTranscriptTimecodesEnabled = meetingTranscriptTimecodesEnabledProvider()
        let orderedChunks = chunks.sorted(by: chunkOrder)
        let timelineDuration = Self.processingDuration(for: recording)
        let reservesDiarizationProgress = meetingDiarizationEnabled && diarizer != nil
        let sourceSpansByChunkURL = Dictionary(grouping: sourceSpans, by: \.chunkURL)
        var processedChunks: [MeetingProcessedChunk] = []
        var modelMetadata: VoiceTranscriptionModelMetadata?
        var noSpeechChunkCount = 0
        await reportTranscriptionProgress(
            completedChunks: 0,
            totalChunks: orderedChunks.count,
            reservesDiarizationProgress: reservesDiarizationProgress
        )

        for (index, chunk) in orderedChunks.enumerated() {
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
                            voiceLevelingEnabled: meetingVoiceLevelingEnabled,
                            timecodesEnabled: meetingTranscriptTimecodesEnabled,
                            diarizationEnabled: meetingDiarizationEnabled,
                            sourceSpans: sourceSpansByChunkURL[chunk.url] ?? Self.fallbackSourceSpans(for: chunk)
                        )
                    }
                )

                timings.preprocessing = (timings.preprocessing ?? 0) + processedChunk.preprocessing
                timings.transcription = (timings.transcription ?? 0) + processedChunk.transcription
                modelMetadata = modelMetadata ?? processedChunk.modelMetadata
                AppLogger.info(
                    "Meeting chunk processed: chunk=\(MeetingDiarizationDebug.interval(chunk.startOffset, chunk.startOffset + chunk.duration)), preprocessing=\(Self.elapsedTime(processedChunk.preprocessing)), transcription=\(Self.elapsedTime(processedChunk.transcription)), textChars=\(processedChunk.text.count)"
                )

                if !processedChunk.text.isEmpty {
                    processedChunks.append(processedChunk)
                }
                await reportTranscriptionProgress(
                    completedChunks: index + 1,
                    totalChunks: orderedChunks.count,
                    reservesDiarizationProgress: reservesDiarizationProgress
                )
            } catch AudioPreprocessingError.noSpeechDetected {
                noSpeechChunkCount += 1
                await reportTranscriptionProgress(
                    completedChunks: index + 1,
                    totalChunks: orderedChunks.count,
                    reservesDiarizationProgress: reservesDiarizationProgress
                )
                continue
            } catch TranscriptionError.transcriptionTimedOut {
                guard !processedChunks.isEmpty else {
                    throw TranscriptionError.transcriptionTimedOut
                }
                await reportSpeakerLabelingProgressIfNeeded(
                    reservesDiarizationProgress: reservesDiarizationProgress,
                    completedChunks: index,
                    totalChunks: orderedChunks.count
                )
                let speakerAnalysis = await self.measuredMeetingSpeakerAnalysis(
                    processedChunks: processedChunks,
                    fullTimelineChunks: chunks,
                    fullTimelineDuration: timelineDuration,
                    enabled: meetingDiarizationEnabled,
                    backend: meetingDiarizationBackend
                )
                if speakerAnalysis.value.didRunDiarization {
                    timings.diarization = speakerAnalysis.elapsed
                }
                logSpeakerAnalysisTiming(speakerAnalysis, enabled: meetingDiarizationEnabled)
                let transcriptParts = self.formatProcessedChunks(
                    processedChunks,
                    speakerTurns: speakerAnalysis.value.turns,
                    timecodesEnabled: meetingTranscriptTimecodesEnabled,
                    diarizationEnabled: meetingDiarizationEnabled
                )
                await reportFinishingProgressIfNeeded(
                    reservesDiarizationProgress: reservesDiarizationProgress,
                    completedChunks: index,
                    totalChunks: orderedChunks.count
                )

                let entry = try savePartialEntry(
                    recording: recording,
                    transcriptParts: transcriptParts,
                    error: TranscriptionError.transcriptionTimedOut,
                    timings: timings,
                    modelMetadata: modelMetadata,
                    speakerCount: speakerAnalysis.value.speakerCount ?? existingSpeakerCount,
                    entryID: entryID,
                    existingTranscript: existingTranscript,
                    existingRecoveryAudio: existingRecoveryAudio
                )
                await reportProcessingCompleteIfNeeded(
                    reservesDiarizationProgress: reservesDiarizationProgress,
                    totalChunks: orderedChunks.count
                )
                return entry
            }
        }

        await reportSpeakerLabelingProgressIfNeeded(
            reservesDiarizationProgress: reservesDiarizationProgress,
            completedChunks: orderedChunks.count,
            totalChunks: orderedChunks.count
        )
        let speakerAnalysis = await self.measuredMeetingSpeakerAnalysis(
            processedChunks: processedChunks,
            fullTimelineChunks: chunks,
            fullTimelineDuration: timelineDuration,
            enabled: meetingDiarizationEnabled,
            backend: meetingDiarizationBackend
        )
        if speakerAnalysis.value.didRunDiarization {
            timings.diarization = speakerAnalysis.elapsed
        }
        logSpeakerAnalysisTiming(speakerAnalysis, enabled: meetingDiarizationEnabled)
        let transcriptParts = self.formatProcessedChunks(
            processedChunks,
            speakerTurns: speakerAnalysis.value.turns,
            timecodesEnabled: meetingTranscriptTimecodesEnabled,
            diarizationEnabled: meetingDiarizationEnabled
        )
        await reportFinishingProgressIfNeeded(
            reservesDiarizationProgress: reservesDiarizationProgress,
            completedChunks: orderedChunks.count,
            totalChunks: orderedChunks.count
        )

        guard !transcriptParts.isEmpty else {
            if noSpeechChunkCount == orderedChunks.count {
                throw MeetingPipelineNoSpeechError.noSpeechDetected
            }
            throw AudioPreprocessingError.noSpeechDetected
        }

        let transcript = transcriptParts.joined(separator: "\n")
        let status: MeetingRecordingStatus = .completed
        let sourceFlags = MeetingSourceFlags(
            microphoneCaptured: recording.sourceFlags.microphoneCaptured,
            systemAudioCaptured: recording.sourceFlags.systemAudioCaptured,
            partial: recording.sourceFlags.partial
        )
        let recoveryAudio: MeetingRecoveryAudioManifest?
        if status == .completed {
            recoveryAudio = try completedRecoveryAudio(
                recording: recording,
                entryID: entryID,
                existingRecoveryAudio: existingRecoveryAudio
            )
        } else {
            recoveryAudio =
                try existingRecoveryAudio
                ?? recoveryAudioStore?.retain(
                    recording: recording,
                    entryID: entryID,
                    createdAt: recording.endedAt
                )
        }
        let entry = MeetingHistoryEntry(
            id: entryID,
            createdAt: recording.endedAt,
            duration: timings.recording ?? 0,
            transcriptText: transcript,
            status: status,
            sourceFlags: sourceFlags,
            errorMessage: errorMessage(recording: recording, processingError: nil),
            timings: timings,
            modelMetadata: metadataWithAppVersion(modelMetadata),
            speakerCount: speakerAnalysis.value.speakerCount ?? existingSpeakerCount,
            recoveryAudio: recoveryAudio
        )
        try historyStore.append(entry)
        await reportProcessingCompleteIfNeeded(
            reservesDiarizationProgress: reservesDiarizationProgress,
            totalChunks: orderedChunks.count
        )
        return entry
    }

    private func completedRecoveryAudio(
        recording: MeetingRecordingResult,
        entryID: UUID,
        existingRecoveryAudio: MeetingRecoveryAudioManifest?
    ) throws -> MeetingRecoveryAudioManifest? {
        let completedAt = nowProvider()
        if let existingRecoveryAudio {
            return existingRecoveryAudio.refreshingRetention(
                createdAt: completedAt,
                retentionDuration: VoicePenConfig.meetingCompletedRecoveryAudioTTL
            )
        }
        return try recoveryAudioStore?.retain(
            recording: recording,
            entryID: entryID,
            createdAt: completedAt,
            retentionDuration: VoicePenConfig.meetingCompletedRecoveryAudioTTL
        )
    }

    private func reportTranscriptionProgress(
        completedChunks: Int,
        totalChunks: Int,
        reservesDiarizationProgress: Bool
    ) async {
        let chunkFraction = Self.chunkProgressFraction(completedChunks: completedChunks, totalChunks: totalChunks)
        let aggregateFraction =
            reservesDiarizationProgress
            ? chunkFraction * Self.asrProgressFractionWhenDiarizing
            : chunkFraction
        await reportProcessingProgress(
            completedChunks: completedChunks,
            totalChunks: totalChunks,
            stage: .transcribing,
            fraction: aggregateFraction
        )
    }

    private func reportSpeakerLabelingProgressIfNeeded(
        reservesDiarizationProgress: Bool,
        completedChunks: Int,
        totalChunks: Int
    ) async {
        guard reservesDiarizationProgress else { return }
        await reportProcessingProgress(
            completedChunks: completedChunks,
            totalChunks: totalChunks,
            stage: .labelingSpeakers,
            fraction: Self.asrProgressFractionWhenDiarizing
        )
    }

    private func reportFinishingProgressIfNeeded(
        reservesDiarizationProgress: Bool,
        completedChunks: Int,
        totalChunks: Int
    ) async {
        guard reservesDiarizationProgress else { return }
        await reportProcessingProgress(
            completedChunks: completedChunks,
            totalChunks: totalChunks,
            stage: .finishing,
            fraction: Self.finishingProgressFractionWhenDiarizing
        )
    }

    private func reportProcessingCompleteIfNeeded(
        reservesDiarizationProgress: Bool,
        totalChunks: Int
    ) async {
        guard reservesDiarizationProgress else { return }
        await reportProcessingProgress(
            completedChunks: totalChunks,
            totalChunks: totalChunks,
            stage: .finishing,
            fraction: 1
        )
    }

    private func reportProcessingProgress(
        completedChunks: Int,
        totalChunks: Int,
        stage: MeetingProcessingStage,
        fraction: Double
    ) async {
        let progress = MeetingProcessingProgress(
            completedChunks: completedChunks,
            totalChunks: totalChunks,
            stage: stage,
            fraction: fraction
        )
        await MainActor.run { [processingProgressHandler] in
            processingProgressHandler(progress)
        }
    }

    private static func chunkProgressFraction(completedChunks: Int, totalChunks: Int) -> Double {
        guard totalChunks > 0 else { return 0 }
        return Double(min(max(0, completedChunks), totalChunks)) / Double(totalChunks)
    }

    private func archiveSavedMeetingAudio(
        chunks: [MeetingAudioChunk],
        sourceSpans: [MeetingAudioSourceSpan],
        capturedAt: Date,
        owner: SavedAudioArchiveOwner
    ) {
        guard saveMeetingAudioEnabledProvider() else { return }
        let spansByChunkURL = Dictionary(grouping: sourceSpans, by: \.chunkURL)
        let storageLimitGB = savedAudioStorageLimitGBProvider()
        for (index, chunk) in chunks.sorted(by: chunkOrder).enumerated() {
            let request = SavedAudioArchiveRequest(
                sourceURL: chunk.url,
                kind: .meeting,
                capturedAt: capturedAt,
                sourceLabel: savedAudioSourceLabel(
                    for: chunk,
                    sourceSpans: spansByChunkURL[chunk.url] ?? []
                ),
                sequenceIndex: index,
                owner: owner
            )
            savedAudioScheduler.archiveBestEffort(request, storageLimitGB: storageLimitGB)
        }
    }

    private static func processingCancellationError(for reason: MeetingProcessingCancellationReason) -> Error {
        switch reason {
        case .userCancelled:
            return MeetingRecordingError.processingCanceled
        case .timedOut:
            return TranscriptionError.transcriptionTimedOut
        }
    }

    private func savedAudioSourceLabel(
        for chunk: MeetingAudioChunk,
        sourceSpans: [MeetingAudioSourceSpan]
    ) -> String {
        let sourceKinds = Set(sourceSpans.map(\.source))
        guard sourceKinds.count <= 1 else { return "merged" }
        switch chunk.source {
        case .microphone:
            return "microphone"
        case .systemAudio:
            return "system-audio"
        }
    }

    private func meetingSpeakerAnalysis(
        processedChunks: [MeetingProcessedChunk],
        fullTimelineChunks: [MeetingAudioChunk],
        fullTimelineDuration: TimeInterval,
        enabled: Bool,
        backend: MeetingDiarizationBackend
    ) async -> MeetingSpeakerAnalysis {
        guard enabled else {
            AppLogger.debug("Meeting diarization disabled for this meeting")
            return .empty
        }
        guard let diarizer else {
            AppLogger.info("Meeting diarization unavailable: no diarizer configured")
            return .empty
        }
        guard Self.hasUsableDiarizationTimestamps(in: processedChunks) else {
            AppLogger.info("Meeting diarization skipped: ASR did not provide usable segment timestamps")
            return .empty
        }

        let fullTimelineInput = try? buildFullTimelineDiarizationInput(
            from: fullTimelineChunks,
            timelineDuration: fullTimelineDuration
        )
        guard let fullTimelineInput else {
            AppLogger.info("Meeting diarization skipped: no readable full-timeline audio for diarization")
            return .empty
        }
        defer {
            removeTemporaryAudioFileIfNeeded(fullTimelineInput.temporaryURL)
        }

        AppLogger.info(
            "Meeting diarization requested: path=\(fullTimelineInput.temporaryURL.lastPathComponent), duration=\(Self.elapsedTime(fullTimelineInput.recording.duration)), strategy=\(MeetingDiarizationStrategy.fullTimeline.rawValue)"
        )
        do {
            let result = try await diarizer.diarize(
                recording: MeetingDiarizationRecording(
                    chunks: [fullTimelineInput.recording],
                    maximumDuration: fullTimelineDuration,
                    backend: backend,
                    strategy: .fullTimeline
                ))
            AppLogger.info(
                "Meeting diarization returned: backend=\(result.backend), returnedTurns=\(result.turns.count), speakers=\(MeetingDiarizationDebug.speakerCounts(result.turns))"
            )
            return MeetingSpeakerAnalysis(result: result)
        } catch {
            AppLogger.info("Meeting diarization skipped: \(error.localizedDescription)")
            return MeetingSpeakerAnalysis(turns: [], speakerCount: nil, didRunDiarization: true)
        }
    }

    private func buildFullTimelineDiarizationInput(
        from chunks: [MeetingAudioChunk],
        timelineDuration: TimeInterval
    ) throws -> (recording: MeetingAudioChunk, temporaryURL: URL)? {
        guard timelineDuration > 0 else { return nil }
        let orderedChunks = chunks.sorted(by: chunkOrder)
        guard !orderedChunks.isEmpty else { return nil }
        let sampleRate = Int(audioFileIO.sampleRate)
        guard sampleRate > 0 else { return nil }
        let totalSamples = max(1, Int((timelineDuration * Double(sampleRate)).rounded(.up)))
        var timelineSamples = Array(repeating: Float(0), count: totalSamples)
        for chunk in orderedChunks where chunk.duration > 0 {
            guard chunk.startOffset < timelineDuration else { continue }
            let startOffset = max(0, chunk.startOffset)
            let startFrame = min(
                totalSamples,
                max(0, Int((startOffset * Double(sampleRate)).rounded(.down)))
            )
            guard startFrame < totalSamples else { continue }

            let sourceSamples = try audioFileIO.readMonoSamples(
                from: chunk.url,
                targetSampleRate: sampleRate
            )
            guard !sourceSamples.isEmpty else { continue }
            let sampleWindowDuration = min(
                chunk.duration,
                Double(totalSamples - startFrame) / Double(sampleRate),
                timelineDuration - startOffset
            )
            let sampleCountToWrite = min(
                sourceSamples.count,
                Int((sampleWindowDuration * Double(sampleRate)).rounded(.down))
            )
            guard sampleCountToWrite > 0 else { continue }

            for index in 0..<sampleCountToWrite {
                let outputIndex = startFrame + index
                timelineSamples[outputIndex] = min(1, max(-1, timelineSamples[outputIndex] + sourceSamples[index]))
            }
        }

        let outputURL =
            fileManager.temporaryDirectory
            .appendingPathComponent("voicepen-meeting-diarization-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let recordedDuration = try audioFileIO.writeMonoSamples(timelineSamples, to: outputURL)
        guard recordedDuration > 0 else { return nil }
        let source = orderedChunks.first?.source ?? .microphone
        return (
            recording: MeetingAudioChunk(
                url: outputURL,
                source: source,
                startOffset: 0,
                duration: recordedDuration
            ),
            temporaryURL: outputURL
        )
    }

    private static func hasUsableDiarizationTimestamps(in processedChunks: [MeetingProcessedChunk]) -> Bool {
        let minimumDuration: TimeInterval = 0.005
        return processedChunks.contains { processedChunk in
            processedChunk.segments.contains { segment in
                if segment.endTime - segment.startTime >= minimumDuration {
                    return true
                }
                return segment.words.contains { word in
                    word.endTime - word.startTime >= minimumDuration
                }
            }
        }
    }

    private static func detectedSpeakerCount(in turns: [SpeakerTurn]) -> Int? {
        let count = Set(turns.map(\.speakerId)).count
        return count > 0 ? count : nil
    }

    private static func fallbackSourceSpans(for chunk: MeetingAudioChunk) -> [MeetingAudioSourceSpan] {
        [
            MeetingAudioSourceSpan(
                chunkURL: chunk.url,
                source: chunk.source,
                sourceURL: chunk.url,
                sourceStartOffset: chunk.startOffset,
                startOffset: chunk.startOffset,
                duration: chunk.duration
            )
        ]
    }

    private func processChunk(
        _ chunk: MeetingAudioChunk,
        mode: SpeechPreprocessingMode,
        language: String,
        voiceLevelingEnabled: Bool,
        timecodesEnabled: Bool,
        diarizationEnabled: Bool,
        sourceSpans: [MeetingAudioSourceSpan]
    ) async throws -> MeetingProcessedChunk {
        let preprocessed = try await measure {
            try await audioPreprocessor.preprocess(audioURL: chunk.url, mode: mode)
        }

        let shouldPreserveTimeline = timecodesEnabled || diarizationEnabled
        var transcriptionAudioURL = shouldPreserveTimeline ? chunk.url : preprocessed.value
        if voiceLevelingEnabled {
            do {
                transcriptionAudioURL = try await voiceLevelingProcessor.process(audioURL: transcriptionAudioURL)
            } catch {
                AppLogger.info("Meeting voice leveling skipped: \(error.localizedDescription)")
            }
        }

        let transcription = try await measure {
            defer {
                removeTemporaryAudioFileIfNeeded(transcriptionAudioURL, preserving: shouldPreserveTimeline ? chunk.url : preprocessed.value)
                if shouldPreserveTimeline {
                    removeTemporaryAudioFileIfNeeded(preprocessed.value, preserving: chunk.url)
                }
            }

            return try await transcriber.transcribe(
                audioURL: transcriptionAudioURL,
                glossaryPrompt: "",
                language: language,
                includeTimestamps: timecodesEnabled || diarizationEnabled
            )
        }

        let sanitizedText = TranscriptionPostFilter.sanitize(transcription.value.text).trimmed
        return MeetingProcessedChunk(
            text: sanitizedText,
            segments: transcription.value.segments,
            chunk: chunk,
            sourceSpans: sourceSpans,
            preprocessing: preprocessed.elapsed,
            transcription: transcription.elapsed,
            modelMetadata: transcription.value.modelMetadata
        )
    }

    private func measuredMeetingSpeakerAnalysis(
        processedChunks: [MeetingProcessedChunk],
        fullTimelineChunks: [MeetingAudioChunk],
        fullTimelineDuration: TimeInterval,
        enabled: Bool,
        backend: MeetingDiarizationBackend
    ) async -> (value: MeetingSpeakerAnalysis, elapsed: TimeInterval) {
        await measure {
            await meetingSpeakerAnalysis(
                processedChunks: processedChunks,
                fullTimelineChunks: fullTimelineChunks,
                fullTimelineDuration: fullTimelineDuration,
                enabled: enabled,
                backend: backend
            )
        }
    }

    private func logSpeakerAnalysisTiming(
        _ speakerAnalysis: (value: MeetingSpeakerAnalysis, elapsed: TimeInterval),
        enabled: Bool
    ) {
        guard enabled else { return }
        AppLogger.info(
            "Meeting diarization timing: elapsed=\(Self.elapsedTime(speakerAnalysis.elapsed)), turns=\(speakerAnalysis.value.turns.count)"
        )
    }

    private func formatProcessedChunks(
        _ chunks: [MeetingProcessedChunk],
        speakerTurns: [SpeakerTurn],
        timecodesEnabled: Bool,
        diarizationEnabled: Bool
    ) -> [String] {
        let results = chunks.map { chunk in
            MeetingTranscriptFormatter.format(
                text: chunk.text,
                segments: chunk.segments,
                chunk: chunk.chunk,
                sourceSpans: chunk.sourceSpans,
                timecodesEnabled: timecodesEnabled,
                diarizationEnabled: diarizationEnabled,
                speakerTurns: speakerTurns,
                audioFileIO: audioFileIO
            )
        }
        return results.filter { !$0.isEmpty }
    }

    private func savePartialEntry(
        recording: MeetingRecordingResult,
        transcriptParts: [String],
        error: Error,
        timings: MeetingPipelineTimings,
        modelMetadata: VoiceTranscriptionModelMetadata?,
        speakerCount: Int?,
        entryID: UUID = UUID(),
        existingTranscript: String = "",
        existingRecoveryAudio: MeetingRecoveryAudioManifest? = nil
    ) throws -> MeetingHistoryEntry {
        let transcript = transcriptParts.joined(separator: "\n")
        let recoveryAudio =
            try existingRecoveryAudio
            ?? recoveryAudioStore?.retain(
                recording: recording,
                entryID: entryID,
                createdAt: recording.endedAt
            )
        let flags = MeetingSourceFlags(
            microphoneCaptured: recording.sourceFlags.microphoneCaptured,
            systemAudioCaptured: recording.sourceFlags.systemAudioCaptured,
            partial: true
        )
        let entry = MeetingHistoryEntry(
            id: entryID,
            createdAt: recording.endedAt,
            duration: timings.recording ?? recording.duration,
            transcriptText: transcript.isEmpty ? existingTranscript : transcript,
            status: .partial,
            sourceFlags: flags,
            errorMessage: errorMessage(recording: recording, processingError: error),
            timings: timings,
            modelMetadata: metadataWithAppVersion(modelMetadata),
            speakerCount: speakerCount,
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
        recoveryAudio: MeetingRecoveryAudioManifest? = nil,
        speakerCount: Int? = nil
    ) throws -> MeetingHistoryEntry {
        let duration = recording.duration
        let retainedAudio =
            try recoveryAudio
            ?? recoveryAudioStore?.retain(
                recording: recording,
                entryID: entryID,
                createdAt: recording.endedAt
            )
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
            speakerCount: speakerCount,
            recoveryAudio: retainedAudio
        )
        try historyStore.append(entry)
        return entry
    }

    private func metadataWithAppVersion(_ metadata: VoiceTranscriptionModelMetadata?) -> VoiceTranscriptionModelMetadata? {
        metadata?.withAppVersion(appVersionProvider())
    }

    private func errorMessage(recording: MeetingRecordingResult, processingError: Error?) -> String? {
        let messages = [
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

    private func removeTemporaryAudioFileIfNeeded(_ url: URL, preserving preservedURL: URL? = nil) {
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

    private static func processingDuration(for recording: MeetingRecordingResult) -> TimeInterval {
        max(recording.duration, recordingDuration(for: recording.chunks))
    }

    private static func recordingDuration(for chunks: [MeetingAudioChunk]) -> TimeInterval {
        chunks.map { $0.startOffset + $0.duration }.max() ?? 0
    }

    private static func elapsedTime(_ elapsed: TimeInterval) -> String {
        String(format: "%.2fs", elapsed)
    }
}

private final class MeetingProcessingCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: MeetingProcessingCancellationReason?

    func set(_ reason: MeetingProcessingCancellationReason) {
        lock.lock()
        self.reason = reason
        lock.unlock()
    }

    func clear() {
        lock.lock()
        reason = nil
        lock.unlock()
    }

    func take(default defaultReason: MeetingProcessingCancellationReason) -> MeetingProcessingCancellationReason {
        lock.lock()
        defer {
            reason = nil
            lock.unlock()
        }
        return reason ?? defaultReason
    }
}

private struct MeetingProcessedChunk: Sendable {
    var text: String
    var segments: [TranscriptionSegment]
    var chunk: MeetingAudioChunk
    var sourceSpans: [MeetingAudioSourceSpan]
    var preprocessing: TimeInterval
    var transcription: TimeInterval
    var modelMetadata: VoiceTranscriptionModelMetadata?
}

private struct MeetingSpeakerAnalysis: Sendable {
    var turns: [SpeakerTurn]
    var speakerCount: Int?
    var didRunDiarization: Bool

    static let empty = MeetingSpeakerAnalysis(turns: [], speakerCount: nil, didRunDiarization: false)

    init(turns: [SpeakerTurn], speakerCount: Int?, didRunDiarization: Bool = false) {
        self.turns = turns
        self.speakerCount = speakerCount
        self.didRunDiarization = didRunDiarization
    }

    init(result: MeetingDiarizationResult) {
        self.turns = result.turns
        self.speakerCount = Self.detectedSpeakerCount(in: result)
        self.didRunDiarization = true
    }

    private static func detectedSpeakerCount(in result: MeetingDiarizationResult) -> Int? {
        if !result.speakers.isEmpty {
            return result.speakers.count
        }

        let count = Set(result.turns.map(\.speakerId)).count
        return count > 0 ? count : nil
    }
}

enum MeetingTranscriptFormatter {
    static func format(
        text: String,
        segments: [TranscriptionSegment],
        chunk: MeetingAudioChunk,
        sourceSpans: [MeetingAudioSourceSpan],
        timecodesEnabled: Bool,
        diarizationEnabled: Bool,
        speakerTurns: [SpeakerTurn],
        audioFileIO: MeetingAudioFileIO
    ) -> String {
        guard !text.isEmpty else { return "" }
        guard timecodesEnabled || diarizationEnabled else { return text }

        let cleanedSegments = segments.compactMap { segment -> TranscriptionSegment? in
            let segmentText = TranscriptionPostFilter.sanitize(segment.text).trimmed
            guard !segmentText.isEmpty else { return nil }
            return TranscriptionSegment(
                text: segmentText,
                startTime: segment.startTime,
                endTime: segment.endTime,
                words: segment.words
            )
        }
        guard !cleanedSegments.isEmpty else { return text }
        let sourceEnergyIndex =
            timecodesEnabled || diarizationEnabled
            ? MeetingSourceEnergyIndex(sourceSpans: sourceSpans, audioFileIO: audioFileIO)
            : nil
        let preparedSegments = removeRepeatedTrailingArtifacts(
            cleanedSegments.map { segment in
                MeetingFormattedTranscriptSegment(
                    text: segment.text,
                    interval: refinedInterval(
                        segment: segment,
                        chunk: chunk,
                        sourceEnergyIndex: sourceEnergyIndex
                    ),
                    words: segment.words.map { word in
                        MeetingFormattedTranscriptWord(
                            text: word.text,
                            interval: (
                                start: chunk.startOffset + word.startTime,
                                end: chunk.startOffset + word.endTime
                            )
                        )
                    }
                )
            })
        guard !preparedSegments.isEmpty else { return "" }
        if diarizationEnabled {
            AppLogger.info(
                "Meeting transcript speaker merge input: chunk=\(MeetingDiarizationDebug.interval(chunk.startOffset, chunk.startOffset + chunk.duration)), segments=\(preparedSegments.count), speakerTurns=\(speakerTurns.count), turnCoverage=\(MeetingDiarizationDebug.coverage(speakerTurns))"
            )
        }
        let renderSegments =
            diarizationEnabled && !speakerTurns.isEmpty
            ? MeetingTranscriptSpeakerMerger.merge(segments: preparedSegments, speakerTurns: speakerTurns)
            : preparedSegments.map {
                MeetingSpeakerMergedTranscriptSegment(text: $0.text, interval: $0.interval, speakerLabel: nil)
            }

        return
            renderSegments
            .map { renderSegment in
                formatLine(
                    segment: renderSegment,
                    timecodesEnabled: timecodesEnabled
                )
            }
            .joined(separator: "\n")
    }

    private static func formatLine(
        segment: MeetingSpeakerMergedTranscriptSegment,
        timecodesEnabled: Bool
    ) -> String {
        var prefixes: [String] = []
        if timecodesEnabled {
            prefixes.append("[\(timecode(segment.interval.start)) - \(timecode(segment.interval.end))]")
        }
        if let speakerLabel = segment.speakerLabel {
            prefixes.append("\(speakerLabel):")
        }
        guard !prefixes.isEmpty else { return segment.text }
        return "\(prefixes.joined(separator: " ")) \(segment.text)"
    }

    private static func refinedInterval(
        segment: TranscriptionSegment,
        chunk: MeetingAudioChunk,
        sourceEnergyIndex: MeetingSourceEnergyIndex?
    ) -> (start: TimeInterval, end: TimeInterval) {
        let fallbackStart = chunk.startOffset + segment.startTime
        let fallbackEnd = chunk.startOffset + segment.endTime
        guard let sourceEnergyIndex,
            let activeBounds = sourceEnergyIndex.activeBounds(
                segmentStart: fallbackStart,
                segmentEnd: fallbackEnd
            )
        else {
            return (fallbackStart, fallbackEnd)
        }
        return activeBounds
    }

    private static func timecode(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time.rounded(.down)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds)
    }

    private static func removeRepeatedTrailingArtifacts(
        _ segments: [MeetingFormattedTranscriptSegment],
        maxSegmentDuration: TimeInterval = 2.5,
        maxTailDuration: TimeInterval = 8.0,
        maxWords: Int = 3
    ) -> [MeetingFormattedTranscriptSegment] {
        guard segments.count >= 2, let last = segments.last else { return segments }
        let repeatedText = normalizedArtifactText(last.text)
        guard repeatedTextWordCount(repeatedText) <= maxWords else { return segments }

        var repeatedCount = 0
        var repeatedDuration: TimeInterval = 0
        var firstRepeatedIndex = segments.count
        var index = segments.count - 1
        while index >= 0,
            normalizedArtifactText(segments[index].text) == repeatedText,
            segments[index].duration <= maxSegmentDuration
        {
            repeatedCount += 1
            repeatedDuration += segments[index].duration
            firstRepeatedIndex = index
            index -= 1
        }

        guard repeatedCount >= 2, repeatedDuration <= maxTailDuration else {
            return segments
        }
        return Array(segments.prefix(firstRepeatedIndex))
    }

    private static func normalizedArtifactText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(
                of: #"[^\p{L}\p{N}]+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmed
    }

    private static func repeatedTextWordCount(_ text: String) -> Int {
        text
            .split(separator: " ")
            .count
    }
}

private struct MeetingFormattedTranscriptSegment {
    var text: String
    var interval: (start: TimeInterval, end: TimeInterval)
    var words: [MeetingFormattedTranscriptWord] = []

    var duration: TimeInterval {
        max(0, interval.end - interval.start)
    }
}

private struct MeetingFormattedTranscriptWord {
    var text: String
    var interval: (start: TimeInterval, end: TimeInterval)
}

private struct MeetingSpeakerMergedTranscriptSegment {
    var text: String
    var interval: (start: TimeInterval, end: TimeInterval)
    var speakerLabel: String?
}

private enum MeetingTranscriptSpeakerMerger {
    static func merge(
        segments: [MeetingFormattedTranscriptSegment],
        speakerTurns: [SpeakerTurn]
    ) -> [MeetingSpeakerMergedTranscriptSegment] {
        AppLogger.info(
            "Meeting transcript speaker merge started: segments=\(segments.count), turns=\(speakerTurns.count), speakers=\(MeetingDiarizationDebug.speakerCounts(speakerTurns))"
        )
        let lookup = SpeakerTurnLookup(speakerTurns: speakerTurns)
        return segments.flatMap { segment in
            guard !segment.words.isEmpty else {
                let assignment = lookup.bestTurn(for: segment.interval)
                logSegmentAssignment(
                    segment: segment,
                    speakerTurn: assignment.turn,
                    source: assignment.source
                )
                return [
                    mergedSegment(
                        text: segment.text,
                        interval: segment.interval,
                        speakerTurn: assignment.turn
                    )
                ]
            }

            let wordAssignments = segment.words.map { word in
                let assignment = lookup.bestTurn(for: word.interval)
                return (word: word, speakerTurn: assignment.turn)
            }
            let groups = groupedWords(wordAssignments)
            guard groups.count > 1 else {
                logSegmentAssignment(
                    segment: segment,
                    speakerTurn: groups.first?.speakerTurn,
                    source: "word-overlap-single-group"
                )
                return [
                    mergedSegment(
                        text: segment.text,
                        interval: segment.interval,
                        speakerTurn: groups.first?.speakerTurn
                    )
                ]
            }

            let meaningfulGroups = groups.filter { group in
                group.words.count >= 2 || group.duration >= 1.0
            }
            guard meaningfulGroups.count == groups.count else {
                let majority = majorityTurn(wordAssignments)
                logSegmentAssignment(
                    segment: segment,
                    speakerTurn: majority,
                    source: "word-majority-after-weak-flip"
                )
                return [
                    mergedSegment(
                        text: segment.text,
                        interval: segment.interval,
                        speakerTurn: majority
                    )
                ]
            }

            AppLogger.debug(
                "Meeting transcript speaker merge split segment: interval=\(MeetingDiarizationDebug.interval(segment.interval.start, segment.interval.end)), groups=\(groups.count), speakers=\(groups.map { $0.speakerTurn?.label ?? "none" }.joined(separator: ","))"
            )
            return groups.map { group in
                mergedSegment(
                    text: group.words.map(\.text).joined(separator: " "),
                    interval: group.interval,
                    speakerTurn: group.speakerTurn
                )
            }
        }
    }

    private static func logSegmentAssignment(
        segment: MeetingFormattedTranscriptSegment,
        speakerTurn: SpeakerTurn?,
        source: String
    ) {
        let label = speakerTurn?.label ?? "none"
        let turnInterval =
            speakerTurn.map {
                MeetingDiarizationDebug.interval($0.startOffset, $0.endOffset)
            } ?? "none"
        let level = speakerTurn == nil ? AppLogger.info : AppLogger.debug
        level(
            "Meeting transcript speaker assignment: segment=\(MeetingDiarizationDebug.interval(segment.interval.start, segment.interval.end)), words=\(segment.words.count), speaker=\(label), source=\(source), turn=\(turnInterval)"
        )
    }

    private static func groupedWords(
        _ wordAssignments: [(word: MeetingFormattedTranscriptWord, speakerTurn: SpeakerTurn?)]
    ) -> [WordGroup] {
        var groups: [WordGroup] = []
        for assignment in wordAssignments {
            let speakerId = assignment.speakerTurn?.speakerId
            if var last = groups.last, last.speakerTurn?.speakerId == speakerId {
                last.words.append(assignment.word)
                groups[groups.count - 1] = last
            } else {
                groups.append(WordGroup(words: [assignment.word], speakerTurn: assignment.speakerTurn))
            }
        }
        return groups
    }

    private static func majorityTurn(
        _ wordAssignments: [(word: MeetingFormattedTranscriptWord, speakerTurn: SpeakerTurn?)]
    ) -> SpeakerTurn? {
        let weighted = Dictionary(grouping: wordAssignments, by: { $0.speakerTurn?.speakerId })
            .mapValues { assignments in
                assignments.reduce(0) { total, assignment in
                    total + max(0, assignment.word.interval.end - assignment.word.interval.start)
                }
            }
        guard let speakerId = weighted.max(by: { lhs, rhs in lhs.value < rhs.value })?.key else {
            return nil
        }
        return wordAssignments.first { $0.speakerTurn?.speakerId == speakerId }?.speakerTurn
    }

    private static func mergedSegment(
        text: String,
        interval: (start: TimeInterval, end: TimeInterval),
        speakerTurn: SpeakerTurn?
    ) -> MeetingSpeakerMergedTranscriptSegment {
        MeetingSpeakerMergedTranscriptSegment(
            text: text,
            interval: interval,
            speakerLabel: speakerTurn?.label
        )
    }

    fileprivate static func isMeaningfulOverlap(_ overlap: TimeInterval, intervalDuration: TimeInterval) -> Bool {
        guard overlap > 0 else { return false }
        return overlap >= 0.35 || (intervalDuration > 0 && overlap / intervalDuration >= 0.2)
    }

    private struct WordGroup {
        var words: [MeetingFormattedTranscriptWord]
        var speakerTurn: SpeakerTurn?

        var interval: (start: TimeInterval, end: TimeInterval) {
            (
                start: words.first?.interval.start ?? 0,
                end: words.last?.interval.end ?? 0
            )
        }

        var duration: TimeInterval {
            max(0, interval.end - interval.start)
        }
    }
}

private struct SpeakerTurnLookup {
    private struct IndexedTurn {
        var turn: SpeakerTurn
        var originalIndex: Int
    }

    private let turnsByStart: [IndexedTurn]
    private let prefixMaxEndOffsets: [TimeInterval]

    init(speakerTurns: [SpeakerTurn]) {
        let sortedTurns =
            speakerTurns
            .enumerated()
            .map { index, turn in IndexedTurn(turn: turn, originalIndex: index) }
            .sorted { lhs, rhs in
                if lhs.turn.startOffset == rhs.turn.startOffset {
                    return lhs.originalIndex < rhs.originalIndex
                }
                return lhs.turn.startOffset < rhs.turn.startOffset
            }
        turnsByStart = sortedTurns

        var maxEndOffset = -Double.infinity
        prefixMaxEndOffsets = sortedTurns.map { indexedTurn in
            maxEndOffset = max(maxEndOffset, indexedTurn.turn.endOffset)
            return maxEndOffset
        }
    }

    func bestTurn(for interval: (start: TimeInterval, end: TimeInterval)) -> (turn: SpeakerTurn?, source: String) {
        let intervalDuration = max(0, interval.end - interval.start)
        if let best = bestOverlap(for: interval),
            MeetingTranscriptSpeakerMerger.isMeaningfulOverlap(best.overlap, intervalDuration: intervalDuration)
        {
            return (best.turn.turn, "overlap=\(String(format: "%.2fs", best.overlap))")
        }

        let midpoint = (interval.start + interval.end) / 2
        if let midpointTurn = firstTurn(containing: midpoint) {
            return (midpointTurn, "midpoint")
        }

        return (nil, "no-overlap-or-midpoint")
    }

    private func bestOverlap(
        for interval: (start: TimeInterval, end: TimeInterval)
    ) -> (turn: IndexedTurn, overlap: TimeInterval)? {
        guard !turnsByStart.isEmpty else { return nil }

        let endIndex = upperBoundStart(interval.end)
        guard endIndex > 0 else { return nil }

        var best: (turn: IndexedTurn, overlap: TimeInterval)?
        var index = endIndex - 1

        while true {
            guard prefixMaxEndOffsets[index] > interval.start else { break }

            let indexedTurn = turnsByStart[index]
            let turn = indexedTurn.turn
            let overlap = max(0, min(interval.end, turn.endOffset) - max(interval.start, turn.startOffset))
            if overlap > 0 && (best == nil || isBetterOverlap(overlap, indexedTurn: indexedTurn, than: best!)) {
                best = (indexedTurn, overlap)
            }

            guard index > 0 else { break }
            index -= 1
        }

        return best
    }

    private func firstTurn(containing time: TimeInterval) -> SpeakerTurn? {
        let endIndex = upperBoundStart(time)
        var match: IndexedTurn?

        for indexedTurn in turnsByStart.prefix(endIndex) {
            let turn = indexedTurn.turn
            guard time >= turn.startOffset && time <= turn.endOffset else { continue }

            if match == nil || indexedTurn.originalIndex < match!.originalIndex {
                match = indexedTurn
            }
        }

        return match?.turn
    }

    private func upperBoundStart(_ time: TimeInterval) -> Int {
        var lowerBound = 0
        var upperBound = turnsByStart.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if turnsByStart[midpoint].turn.startOffset <= time {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        return lowerBound
    }

    private func isBetterOverlap(
        _ overlap: TimeInterval,
        indexedTurn: IndexedTurn,
        than current: (turn: IndexedTurn, overlap: TimeInterval)
    ) -> Bool {
        overlap > current.overlap
            || (overlap == current.overlap && indexedTurn.originalIndex < current.turn.originalIndex)
    }
}
