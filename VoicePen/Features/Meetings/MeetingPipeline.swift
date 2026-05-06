import AVFoundation
import Foundation

final class MeetingPipeline {
    static let maximumMeetingDuration: TimeInterval = VoicePenConfig.meetingMaximumRecordingDuration
    static let chunkDuration: TimeInterval = 60
    private static let minimumAutoDiarizationDuration: TimeInterval = 15

    private let recorder: MeetingRecordingClient
    private let audioPreprocessor: AudioPreprocessingClient
    private let voiceLevelingProcessor: VoiceLevelingProcessor
    private let chunker: MeetingAudioChunker
    private let transcriber: TranscriptionClient
    private let diarizer: MeetingDiarizationClient?
    private let historyStore: MeetingHistoryStore
    private let recoveryAudioStore: MeetingRecoveryAudioStore?
    private let languageProvider: () -> String
    private let speechPreprocessingModeProvider: () -> SpeechPreprocessingMode
    private let meetingVoiceLevelingEnabledProvider: () -> Bool
    private let meetingTranscriptTimecodesEnabledProvider: () -> Bool
    private let meetingDiarizationEnabledProvider: () -> Bool
    private let meetingDiarizationExpectedSpeakerCountProvider: @MainActor () -> Int?
    private let appVersionProvider: () -> String
    private var processingProgressHandler: @MainActor (MeetingProcessingProgress?) -> Void = { _ in }
    private let fileManager: FileManager
    private let chunkProcessingTimeout: Duration

    init(
        recorder: MeetingRecordingClient,
        audioPreprocessor: AudioPreprocessingClient = PassthroughAudioPreprocessingClient(),
        voiceLevelingProcessor: VoiceLevelingProcessor = PassthroughVoiceLevelingProcessor(),
        chunker: MeetingAudioChunker = PassthroughMeetingAudioChunker(),
        transcriber: TranscriptionClient,
        diarizer: MeetingDiarizationClient? = nil,
        historyStore: MeetingHistoryStore,
        recoveryAudioStore: MeetingRecoveryAudioStore? = nil,
        languageProvider: @escaping () -> String = { VoicePenConfig.defaultLanguage },
        speechPreprocessingModeProvider: @escaping () -> SpeechPreprocessingMode = { .off },
        meetingVoiceLevelingEnabledProvider: @escaping () -> Bool = { false },
        meetingTranscriptTimecodesEnabledProvider: @escaping () -> Bool = { true },
        meetingDiarizationEnabledProvider: @escaping () -> Bool = { false },
        meetingDiarizationExpectedSpeakerCountProvider: @escaping @MainActor () -> Int? = { nil },
        appVersionProvider: @escaping () -> String = { VoicePenConfig.appVersion },
        chunkProcessingTimeout: Duration = VoicePenConfig.meetingChunkProcessingTimeout,
        fileManager: FileManager = .default
    ) {
        self.recorder = recorder
        self.audioPreprocessor = audioPreprocessor
        self.voiceLevelingProcessor = voiceLevelingProcessor
        self.chunker = chunker
        self.transcriber = transcriber
        self.diarizer = diarizer
        self.historyStore = historyStore
        self.recoveryAudioStore = recoveryAudioStore
        self.languageProvider = languageProvider
        self.speechPreprocessingModeProvider = speechPreprocessingModeProvider
        self.meetingVoiceLevelingEnabledProvider = meetingVoiceLevelingEnabledProvider
        self.meetingTranscriptTimecodesEnabledProvider = meetingTranscriptTimecodesEnabledProvider
        self.meetingDiarizationEnabledProvider = meetingDiarizationEnabledProvider
        self.meetingDiarizationExpectedSpeakerCountProvider = meetingDiarizationExpectedSpeakerCountProvider
        self.appVersionProvider = appVersionProvider
        self.fileManager = fileManager
        self.chunkProcessingTimeout = chunkProcessingTimeout
    }

    func setProcessingProgressHandler(_ handler: @escaping @MainActor (MeetingProcessingProgress?) -> Void) {
        processingProgressHandler = handler
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
        let expectedSpeakerCount = await expectedDiarizationSpeakerCountIfNeeded()
        return try await process(recording, expectedDiarizationSpeakerCount: expectedSpeakerCount)
    }

    private func expectedDiarizationSpeakerCountIfNeeded() async -> Int? {
        guard meetingDiarizationEnabledProvider() else { return nil }
        return await MainActor.run { meetingDiarizationExpectedSpeakerCountProvider() }
    }

    func process(
        _ recording: MeetingRecordingResult,
        expectedDiarizationSpeakerCount: Int? = nil
    ) async throws -> MeetingHistoryEntry {
        var cleanupURLs = recording.temporaryAudioURLs
        do {
            let chunkingResult = try await chunker.split(
                recording.chunks,
                maximumDuration: Self.maximumMeetingDuration,
                chunkDuration: Self.chunkDuration
            )
            cleanupURLs.append(contentsOf: chunkingResult.temporaryURLs)
            let meetingDiarizationEnabled = meetingDiarizationEnabledProvider()
            let entry = try await processRecording(
                recording,
                chunks: chunkingResult.chunks,
                sourceSpans: chunkingResult.sourceSpans,
                meetingDiarizationEnabled: meetingDiarizationEnabled,
                expectedDiarizationSpeakerCount: expectedDiarizationSpeakerCount
            )
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
            let meetingDiarizationEnabled = meetingDiarizationEnabledProvider()
            let retryEntry = try await processRecording(
                recording,
                chunks: chunkingResult.chunks,
                sourceSpans: chunkingResult.sourceSpans,
                meetingDiarizationEnabled: meetingDiarizationEnabled,
                expectedDiarizationSpeakerCount: nil,
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
        sourceSpans: [MeetingAudioSourceSpan],
        meetingDiarizationEnabled: Bool,
        expectedDiarizationSpeakerCount: Int?,
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
        let meetingTranscriptTimecodesEnabled = meetingTranscriptTimecodesEnabledProvider()
        let orderedChunks = chunks.sorted(by: chunkOrder)
        let sourceSpansByChunkURL = Dictionary(grouping: sourceSpans, by: \.chunkURL)
        let diarization = await measure {
            await meetingSpeakerTurns(
                chunks: orderedChunks,
                enabled: meetingDiarizationEnabled,
                expectedSpeakerCount: expectedDiarizationSpeakerCount
            )
        }
        let speakerTurns = diarization.value
        if meetingDiarizationEnabled {
            AppLogger.info(
                "Meeting diarization timing: elapsed=\(Self.elapsedTime(diarization.elapsed)), turns=\(speakerTurns.count)"
            )
        }
        var transcriptParts: [String] = []
        var modelMetadata: VoiceTranscriptionModelMetadata?
        var skippedChunkCount = 0
        await reportProcessingProgress(completedChunks: 0, totalChunks: orderedChunks.count)

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
                            speakerTurns: speakerTurns,
                            sourceSpans: sourceSpansByChunkURL[chunk.url] ?? [
                                MeetingAudioSourceSpan(
                                    chunkURL: chunk.url,
                                    source: chunk.source,
                                    sourceURL: chunk.url,
                                    sourceStartOffset: chunk.startOffset,
                                    startOffset: chunk.startOffset,
                                    duration: chunk.duration
                                )
                            ]
                        )
                    }
                )

                timings.preprocessing = (timings.preprocessing ?? 0) + processedChunk.preprocessing
                timings.transcription = (timings.transcription ?? 0) + processedChunk.transcription
                modelMetadata = modelMetadata ?? processedChunk.modelMetadata
                AppLogger.info(
                    "Meeting chunk processed: chunk=\(MeetingDiarizationDebug.interval(chunk.startOffset, chunk.startOffset + chunk.duration)), preprocessing=\(Self.elapsedTime(processedChunk.preprocessing)), transcription=\(Self.elapsedTime(processedChunk.transcription)), textChars=\(processedChunk.text.count)"
                )

                if processedChunk.text.isEmpty {
                    skippedChunkCount += 1
                } else {
                    transcriptParts.append(processedChunk.text)
                }
                await reportProcessingProgress(completedChunks: index + 1, totalChunks: orderedChunks.count)
            } catch AudioPreprocessingError.noSpeechDetected {
                skippedChunkCount += 1
                await reportProcessingProgress(completedChunks: index + 1, totalChunks: orderedChunks.count)
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
            modelMetadata: metadataWithAppVersion(modelMetadata),
            recoveryAudio: recoveryAudio
        )
        try historyStore.append(entry)
        return entry
    }

    private func reportProcessingProgress(completedChunks: Int, totalChunks: Int) async {
        let progress = MeetingProcessingProgress(completedChunks: completedChunks, totalChunks: totalChunks)
        await MainActor.run { [processingProgressHandler] in
            processingProgressHandler(progress)
        }
    }

    private func meetingSpeakerTurns(
        chunks: [MeetingAudioChunk],
        enabled: Bool,
        expectedSpeakerCount: Int?
    ) async -> [SpeakerTurn] {
        guard enabled else {
            AppLogger.debug("Meeting diarization disabled for this meeting")
            return []
        }
        guard let diarizer else {
            AppLogger.info("Meeting diarization unavailable: no diarizer configured")
            return []
        }
        let recordingDuration = Self.recordingDuration(for: chunks)
        if expectedSpeakerCount == nil, recordingDuration < Self.minimumAutoDiarizationDuration {
            AppLogger.info(
                "Meeting diarization skipped: recording=\(MeetingDiarizationDebug.interval(0, recordingDuration)) is shorter than auto diarization minimum \(Self.elapsedTime(Self.minimumAutoDiarizationDuration)); choose an exact speaker count to force diarization for very short recordings"
            )
            return []
        }
        AppLogger.info(
            "Meeting diarization requested: chunks=\(chunks.count), expectedSpeakers=\(expectedSpeakerCount.map(String.init) ?? "auto")"
        )
        do {
            let result = try await diarizer.diarize(
                recording: MeetingDiarizationRecording(
                    chunks: chunks,
                    maximumDuration: Self.maximumMeetingDuration,
                    expectedSpeakerCount: expectedSpeakerCount
                ))
            let turns = result.turns
            AppLogger.info(
                "Meeting diarization returned: backend=\(result.backend), turns=\(turns.count), coverage=\(MeetingDiarizationDebug.coverage(turns)), speakers=\(MeetingDiarizationDebug.speakerCounts(turns))"
            )
            return turns
        } catch {
            AppLogger.info("Meeting diarization skipped: \(error.localizedDescription)")
            return []
        }
    }

    private func processChunk(
        _ chunk: MeetingAudioChunk,
        mode: SpeechPreprocessingMode,
        language: String,
        voiceLevelingEnabled: Bool,
        timecodesEnabled: Bool,
        diarizationEnabled: Bool,
        speakerTurns: [SpeakerTurn],
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
        let transcriptText = MeetingTranscriptFormatter.format(
            text: sanitizedText,
            segments: transcription.value.segments,
            chunk: chunk,
            sourceSpans: sourceSpans,
            timecodesEnabled: timecodesEnabled,
            diarizationEnabled: diarizationEnabled,
            speakerTurns: speakerTurns
        )
        return MeetingProcessedChunk(
            text: transcriptText,
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
            modelMetadata: metadataWithAppVersion(modelMetadata),
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

    private func metadataWithAppVersion(_ metadata: VoiceTranscriptionModelMetadata?) -> VoiceTranscriptionModelMetadata? {
        metadata?.withAppVersion(appVersionProvider())
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

    private static func recordingDuration(for chunks: [MeetingAudioChunk]) -> TimeInterval {
        min(maximumMeetingDuration, chunks.map { $0.startOffset + $0.duration }.max() ?? 0)
    }

    private static func elapsedTime(_ elapsed: TimeInterval) -> String {
        String(format: "%.2fs", elapsed)
    }
}

private struct MeetingProcessedChunk: Sendable {
    var text: String
    var preprocessing: TimeInterval
    var transcription: TimeInterval
    var modelMetadata: VoiceTranscriptionModelMetadata?
}

private enum MeetingTranscriptFormatter {
    static func format(
        text: String,
        segments: [TranscriptionSegment],
        chunk: MeetingAudioChunk,
        sourceSpans: [MeetingAudioSourceSpan],
        timecodesEnabled: Bool,
        diarizationEnabled: Bool,
        speakerTurns: [SpeakerTurn]
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
            ? MeetingSourceEnergyIndex(sourceSpans: sourceSpans)
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
        return segments.flatMap { segment in
            guard !segment.words.isEmpty else {
                let assignment = bestTurn(for: segment.interval, in: speakerTurns)
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
                let assignment = bestTurn(for: word.interval, in: speakerTurns)
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

    private static func bestTurn(
        for interval: (start: TimeInterval, end: TimeInterval),
        in speakerTurns: [SpeakerTurn]
    ) -> (turn: SpeakerTurn?, source: String) {
        let intervalDuration = max(0, interval.end - interval.start)
        let scoredTurns = speakerTurns.map { turn in
            (
                turn: turn,
                overlap: max(0, min(interval.end, turn.endOffset) - max(interval.start, turn.startOffset))
            )
        }
        if let best = scoredTurns.max(by: { $0.overlap < $1.overlap }),
            isMeaningfulOverlap(best.overlap, intervalDuration: intervalDuration)
        {
            return (best.turn, "overlap=\(String(format: "%.2fs", best.overlap))")
        }

        let midpoint = (interval.start + interval.end) / 2
        let midpointTurn = speakerTurns.first { turn in
            midpoint >= turn.startOffset && midpoint <= turn.endOffset
        }
        if let midpointTurn {
            return (midpointTurn, "midpoint")
        }

        return (nil, "no-overlap-or-midpoint")
    }

    private static func isMeaningfulOverlap(_ overlap: TimeInterval, intervalDuration: TimeInterval) -> Bool {
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

private struct MeetingSourceEnergyIndex {
    private let profilesBySource: [MeetingSourceKind: [MeetingSourceEnergyProfile]]

    init(sourceSpans: [MeetingAudioSourceSpan], binDuration: TimeInterval = 0.1) {
        var profilesBySource: [MeetingSourceKind: [MeetingSourceEnergyProfile]] = [:]
        for span in sourceSpans {
            guard let profile = MeetingSourceEnergyProfile(span: span, binDuration: binDuration) else {
                continue
            }
            profilesBySource[span.source, default: []].append(profile)
        }
        self.profilesBySource = profilesBySource
    }

    func dominantEnergy(
        for source: MeetingSourceKind,
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval
    ) -> Double {
        profilesBySource[source]?
            .compactMap { $0.averageEnergy(segmentStart: segmentStart, segmentEnd: segmentEnd) }
            .max() ?? 0
    }

    func activeBounds(
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        threshold: Double = 0.0001
    ) -> (start: TimeInterval, end: TimeInterval)? {
        profilesBySource.values
            .flatMap { $0 }
            .compactMap { $0.activeBounds(segmentStart: segmentStart, segmentEnd: segmentEnd, threshold: threshold) }
            .reduce(nil) { partial, bounds in
                guard let partial else { return bounds }
                return (
                    start: min(partial.start, bounds.start),
                    end: max(partial.end, bounds.end)
                )
            }
    }
}

private struct MeetingSourceEnergyProfile {
    var startOffset: TimeInterval
    var duration: TimeInterval
    var binDuration: TimeInterval
    var bins: [Double]

    init?(span: MeetingAudioSourceSpan, binDuration: TimeInterval) {
        guard span.duration > 0, binDuration > 0 else { return nil }
        guard let audioFile = try? AVAudioFile(forReading: span.sourceURL) else { return nil }
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let sourceOffset = max(0, span.startOffset - span.sourceStartOffset)
        let startFrame = min(
            audioFile.length,
            AVAudioFramePosition((sourceOffset * sampleRate).rounded(.down))
        )
        let requestedFrames = AVAudioFrameCount(max(1, (span.duration * sampleRate).rounded(.up)))
        let availableFrames = AVAudioFrameCount(max(0, audioFile.length - startFrame))
        let frameCount = min(requestedFrames, availableFrames)
        guard frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else {
            return nil
        }

        audioFile.framePosition = startFrame
        do {
            try audioFile.read(into: buffer, frameCount: frameCount)
        } catch {
            return nil
        }
        guard let channelData = buffer.floatChannelData else { return nil }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return nil }

        let binCount = max(1, Int((span.duration / binDuration).rounded(.up)))
        var totals = Array(repeating: 0.0, count: binCount)
        var counts = Array(repeating: 0, count: binCount)
        let framesPerBin = max(1, Int((binDuration * sampleRate).rounded(.up)))

        for frame in 0..<frameLength {
            let binIndex = min(binCount - 1, frame / framesPerBin)
            var frameTotal = 0.0
            for channel in 0..<channelCount {
                frameTotal += Double(abs(channelData[channel][frame]))
            }
            totals[binIndex] += frameTotal / Double(channelCount)
            counts[binIndex] += 1
        }

        self.startOffset = span.startOffset
        self.duration = span.duration
        self.binDuration = binDuration
        self.bins = totals.enumerated().map { index, total in
            let count = counts[index]
            return count > 0 ? total / Double(count) : 0
        }
    }

    func averageEnergy(segmentStart: TimeInterval, segmentEnd: TimeInterval) -> Double? {
        let profileEnd = startOffset + duration
        let overlapStart = max(segmentStart, startOffset)
        let overlapEnd = min(segmentEnd, profileEnd)
        guard overlapEnd > overlapStart, !bins.isEmpty else { return nil }

        var weightedTotal = 0.0
        var totalDuration = 0.0
        for (index, energy) in bins.enumerated() {
            let binStart = startOffset + (Double(index) * binDuration)
            let binEnd = min(profileEnd, binStart + binDuration)
            let binOverlapStart = max(overlapStart, binStart)
            let binOverlapEnd = min(overlapEnd, binEnd)
            guard binOverlapEnd > binOverlapStart else { continue }
            let binOverlapDuration = binOverlapEnd - binOverlapStart
            weightedTotal += energy * binOverlapDuration
            totalDuration += binOverlapDuration
        }

        guard totalDuration > 0 else { return nil }
        return weightedTotal / totalDuration
    }

    func activeBounds(
        segmentStart: TimeInterval,
        segmentEnd: TimeInterval,
        threshold: Double
    ) -> (start: TimeInterval, end: TimeInterval)? {
        let profileEnd = startOffset + duration
        let overlapStart = max(segmentStart, startOffset)
        let overlapEnd = min(segmentEnd, profileEnd)
        guard overlapEnd > overlapStart, !bins.isEmpty else { return nil }

        var firstActiveStart: TimeInterval?
        var lastActiveEnd: TimeInterval?
        for (index, energy) in bins.enumerated() where energy > threshold {
            let binStart = startOffset + (Double(index) * binDuration)
            let binEnd = min(profileEnd, binStart + binDuration)
            let binOverlapStart = max(overlapStart, binStart)
            let binOverlapEnd = min(overlapEnd, binEnd)
            guard binOverlapEnd > binOverlapStart else { continue }
            firstActiveStart = firstActiveStart.map { min($0, binOverlapStart) } ?? binOverlapStart
            lastActiveEnd = lastActiveEnd.map { max($0, binOverlapEnd) } ?? binOverlapEnd
        }

        guard let firstActiveStart, let lastActiveEnd else { return nil }
        return (firstActiveStart, lastActiveEnd)
    }
}
