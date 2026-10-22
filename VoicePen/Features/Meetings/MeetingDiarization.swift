import Foundation
import VoicePenDiarization

protocol MeetingDiarizationClient: AnyObject {
    func diarize(recording: MeetingDiarizationRecording) async throws -> MeetingDiarizationResult

    func warmUp() async throws
    func resetCache() async
}

protocol MeetingDiarizationModelManaging: AnyObject {
    var isModelInstalled: Bool { get }
    var modelDirectory: URL { get }

    func download(events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws
    func warmUp() async throws
    func deleteDownloadedModelFiles() async throws
}

nonisolated struct MeetingDiarizationRecording: Equatable, Sendable {
    var chunks: [MeetingAudioChunk]
    var maximumDuration: TimeInterval
    var backend: MeetingDiarizationBackend
    var strategy: MeetingDiarizationStrategy

    init(
        chunks: [MeetingAudioChunk],
        maximumDuration: TimeInterval,
        backend: MeetingDiarizationBackend = .nemotron,
        strategy: MeetingDiarizationStrategy = .fullTimeline
    ) {
        self.chunks = chunks
        self.maximumDuration = maximumDuration
        self.backend = backend
        self.strategy = strategy
    }

    var orderedChunks: [MeetingAudioChunk] {
        chunks
            .filter { $0.duration > 0 && $0.startOffset < maximumDuration }
            .sorted {
                if $0.startOffset != $1.startOffset {
                    return $0.startOffset < $1.startOffset
                }
                return Self.sourceOrder($0.source) < Self.sourceOrder($1.source)
            }
    }

    var duration: TimeInterval {
        min(maximumDuration, orderedChunks.map { $0.startOffset + $0.duration }.max() ?? 0)
    }

    private static func sourceOrder(_ source: MeetingSourceKind) -> Int {
        source == .microphone ? 0 : 1
    }
}

nonisolated enum MeetingDiarizationStrategy: String, Equatable, Sendable {
    case fullTimeline
}

nonisolated enum MeetingDiarizationBackend: String, CaseIterable, Identifiable, Sendable {
    case nemotron

    var id: String { rawValue }

    var displayName: String {
        "Nemotron offline"
    }

    var backendName: String {
        "nemotron"
    }
}

nonisolated struct MeetingDiarizationSpeaker: Equatable, Sendable {
    var id: Int
    var label: String
}

nonisolated struct MeetingDiarizationConfig: Equatable, Sendable {
    var backend: String
    var usesSileroPreFilter: Bool
}

nonisolated struct SpeakerTurn: Equatable, Sendable {
    var startOffset: TimeInterval
    var endOffset: TimeInterval
    var speakerId: Int
    var confidence: Double?

    var duration: TimeInterval {
        max(0, endOffset - startOffset)
    }

    var label: String {
        "Speaker \(speakerId + 1)"
    }
}

nonisolated enum MeetingDiarizationDebug {
    static func interval(_ start: TimeInterval, _ end: TimeInterval) -> String {
        "\(time(start))-\(time(end))"
    }

    static func intervals(_ intervals: [(start: TimeInterval, end: TimeInterval)], limit: Int = 8) -> String {
        guard !intervals.isEmpty else { return "[]" }
        let prefix = intervals.prefix(limit).map { interval($0.start, $0.end) }
        let suffix = intervals.count > limit ? ", +\(intervals.count - limit) more" : ""
        return "[\(prefix.joined(separator: ", "))\(suffix)]"
    }

    static func turns(_ turns: [SpeakerTurn], limit: Int = 8) -> String {
        guard !turns.isEmpty else { return "[]" }
        let prefix = turns.prefix(limit).map { turn in
            "\(turn.label)@\(interval(turn.startOffset, turn.endOffset))"
        }
        let suffix = turns.count > limit ? ", +\(turns.count - limit) more" : ""
        return "[\(prefix.joined(separator: ", "))\(suffix)]"
    }

    static func speakerCounts(_ turns: [SpeakerTurn]) -> String {
        let counts = Dictionary(grouping: turns, by: \.speakerId)
            .mapValues { $0.count }
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { "Speaker \($0.key + 1): \($0.value)" }
        return counts.isEmpty ? "none" : counts.joined(separator: ", ")
    }

    static func coverage(_ turns: [SpeakerTurn]) -> String {
        guard let start = turns.map(\.startOffset).min(),
            let end = turns.map(\.endOffset).max()
        else {
            return "none"
        }
        return interval(start, end)
    }

    private static func time(_ time: TimeInterval) -> String {
        String(format: "%.2fs", max(0, time))
    }
}

nonisolated struct MeetingDiarizationResult: Equatable, Sendable {
    var speakers: [MeetingDiarizationSpeaker]
    var turns: [SpeakerTurn]
    var backend: String
    var config: MeetingDiarizationConfig
}

nonisolated enum MeetingSpeakerTurnPostprocessor {
    static func postprocess(
        _ turns: [SpeakerTurn],
        minimumTurnDuration: TimeInterval = 0.4,
        mergeGap: TimeInterval = 0.75,
        shortFlipDuration: TimeInterval = 0.75
    ) -> [SpeakerTurn] {
        var turns =
            turns
            .filter { $0.duration >= minimumTurnDuration }
            .sorted { $0.startOffset < $1.startOffset }
        guard !turns.isEmpty else { return [] }

        turns = mergeAdjacent(turns, maximumGap: mergeGap)
        turns = smoothShortFlips(turns, maximumDuration: shortFlipDuration)
        turns = resolveOverlaps(
            turns,
            minimumTurnDuration: minimumTurnDuration,
            shortFlipDuration: shortFlipDuration
        )
        return mergeAdjacent(turns, maximumGap: mergeGap)
    }

    private static func mergeAdjacent(_ turns: [SpeakerTurn], maximumGap: TimeInterval) -> [SpeakerTurn] {
        var merged: [SpeakerTurn] = []
        for turn in turns {
            guard var last = merged.last,
                last.speakerId == turn.speakerId,
                turn.startOffset - last.endOffset <= maximumGap
            else {
                merged.append(turn)
                continue
            }
            last.endOffset = max(last.endOffset, turn.endOffset)
            last.confidence = max(last.confidence ?? 0, turn.confidence ?? 0)
            merged[merged.count - 1] = last
        }
        return merged
    }

    private static func smoothShortFlips(_ turns: [SpeakerTurn], maximumDuration: TimeInterval) -> [SpeakerTurn] {
        guard turns.count >= 3 else { return turns }
        var smoothed = turns
        for index in 1..<(smoothed.count - 1) {
            let previous = smoothed[index - 1]
            let current = smoothed[index]
            let next = smoothed[index + 1]
            guard current.duration <= maximumDuration,
                previous.speakerId == next.speakerId,
                current.speakerId != previous.speakerId
            else {
                continue
            }
            smoothed[index].speakerId = previous.speakerId
        }
        return smoothed
    }

    private static func resolveOverlaps(
        _ turns: [SpeakerTurn],
        minimumTurnDuration: TimeInterval,
        shortFlipDuration: TimeInterval
    ) -> [SpeakerTurn] {
        let nestedFlipDuration = max(shortFlipDuration, 1.0)
        var resolved: [SpeakerTurn] = []
        for var turn in turns.sorted(by: { $0.startOffset < $1.startOffset }) {
            guard var last = resolved.last, turn.startOffset < last.endOffset else {
                resolved.append(turn)
                continue
            }

            if last.speakerId == turn.speakerId {
                last.endOffset = max(last.endOffset, turn.endOffset)
                resolved[resolved.count - 1] = last
                continue
            }

            let turnIsNestedShortFlip =
                turn.endOffset <= last.endOffset
                && turn.duration <= nestedFlipDuration
            if turnIsNestedShortFlip {
                continue
            }

            let lastIsNestedShortFlip =
                last.duration <= nestedFlipDuration
                && last.startOffset >= turn.startOffset
                && last.endOffset <= turn.endOffset
            if lastIsNestedShortFlip {
                resolved.removeLast()
                resolved.append(turn)
                continue
            }

            let boundary = (turn.startOffset + last.endOffset) / 2
            last.endOffset = boundary
            turn.startOffset = boundary

            if last.duration >= minimumTurnDuration {
                resolved[resolved.count - 1] = last
            } else {
                resolved.removeLast()
            }
            if turn.duration >= minimumTurnDuration {
                resolved.append(turn)
            }
        }
        return resolved
    }
}

nonisolated protocol NemotronDiarizationRuntime: Sendable {
    func warmUp() async throws
    func diarize(audioSamples: [Float], sampleRate: Int) async throws -> [SpeakerTurn]
    func unload() async
}

protocol NemotronDiarizationRuntimeFactory: Sendable {
    func makeRuntime(modelDirectory: URL) async throws -> NemotronDiarizationRuntime
}

final class DefaultNemotronDiarizationRuntimeFactory: NemotronDiarizationRuntimeFactory {
    func makeRuntime(modelDirectory: URL) async throws -> NemotronDiarizationRuntime {
        await NemotronRuntime(modelDirectory: modelDirectory)
    }
}

private actor NemotronRuntime: NemotronDiarizationRuntime {
    private let context: NemotronOfflineContext

    init(modelDirectory: URL) async {
        context = NemotronOfflineContext(modelDirectory: modelDirectory)
    }

    func warmUp() async throws { try await context.warmUp() }
    func unload() async { await context.unload() }

    func diarize(audioSamples: [Float], sampleRate: Int) async throws -> [SpeakerTurn] {
        guard sampleRate == 16_000 else {
            throw TranscriptionError.transcriptionFailed("Nemotron diarization expects 16000 Hz samples.")
        }
        return try await context.diarize(samples: audioSamples).map {
            SpeakerTurn(
                startOffset: $0.startSeconds, endOffset: $0.endSeconds,
                speakerId: $0.speakerIndex, confidence: nil)
        }
    }
}

final class NemotronDiarizationModelCache: Sendable {
    private let downloader: NemotronDiarizationModelDownloader

    init(
        runtimeFactory: NemotronDiarizationRuntimeFactory = DefaultNemotronDiarizationRuntimeFactory(),
        downloader: NemotronDiarizationModelDownloader = NemotronDiarizationModelDownloader()
    ) {
        self.downloader = downloader
        self.wrapped = Wrapped(runtimeFactory: runtimeFactory)
    }

    actor Wrapped {
        private let runtimeFactory: NemotronDiarizationRuntimeFactory
        private var runtime: NemotronDiarizationRuntime?
        private var creating: Task<NemotronDiarizationRuntime, Error>?
        private var generation = 0
        private var activeOperations = 0

        init(runtimeFactory: NemotronDiarizationRuntimeFactory) {
            self.runtimeFactory = runtimeFactory
        }

        func runtime(for modelDirectory: URL) async throws -> NemotronDiarizationRuntime {
            if let runtime {
                return runtime
            }
            let requestGeneration = generation
            let task: Task<NemotronDiarizationRuntime, Error>
            if let creating {
                task = creating
            } else {
                let factory = runtimeFactory
                task = Task { try await factory.makeRuntime(modelDirectory: modelDirectory) }
                creating = task
            }
            do {
                let newRuntime = try await task.value
                guard generation == requestGeneration else {
                    await newRuntime.unload()
                    throw CancellationError()
                }
                runtime = newRuntime
                creating = nil
                try Task.checkCancellation()
                return newRuntime
            } catch {
                if generation == requestGeneration { creating = nil }
                throw error
            }
        }

        func warmUp(modelDirectory: URL) async throws {
            activeOperations += 1
            do {
                let runtime = try await runtime(for: modelDirectory)
                try await runtime.warmUp()
                await finishOperation()
            } catch {
                await finishOperation()
                throw error
            }
        }

        func diarize(audioSamples: [Float], sampleRate: Int, modelDirectory: URL) async throws -> [SpeakerTurn] {
            activeOperations += 1
            do {
                let runtime = try await runtime(for: modelDirectory)
                let turns = try await runtime.diarize(audioSamples: audioSamples, sampleRate: sampleRate)
                await finishOperation()
                return turns
            } catch {
                await finishOperation()
                throw error
            }
        }

        private func finishOperation() async {
            activeOperations -= 1
            if activeOperations == 0 {
                await reset()
            }
        }

        func reset() async {
            generation += 1
            creating?.cancel()
            creating = nil
            let previous = runtime
            runtime = nil
            await previous?.unload()
        }
    }

    private let wrapped: Wrapped

    func warmUp(cacheDirectory: URL) async throws {
        try await wrapped.warmUp(modelDirectory: cacheDirectory)
    }

    func diarize(audioSamples: [Float], sampleRate: Int, cacheDirectory: URL) async throws -> [SpeakerTurn] {
        try await wrapped.diarize(audioSamples: audioSamples, sampleRate: sampleRate, modelDirectory: cacheDirectory)
    }

    func reset() async {
        await wrapped.reset()
    }

    func download(cacheDirectory: URL, events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws {
        await wrapped.reset()
        try await downloader.download(cacheDirectory: cacheDirectory, events: { events($0) })
    }
}

final class NemotronMeetingDiarizationClient: MeetingDiarizationClient {
    private let cacheDirectory: URL
    private let selectedBackendProvider: () -> MeetingDiarizationBackend
    private let audioFileIO: MeetingAudioFileIO
    private let sampleRate = 16_000
    private let cache: NemotronDiarizationModelCache

    init(
        cacheDirectory: URL,
        cache: NemotronDiarizationModelCache = NemotronDiarizationModelCache(),
        selectedBackendProvider: @escaping () -> MeetingDiarizationBackend = { .nemotron },
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO()
    ) {
        self.cacheDirectory = cacheDirectory
        self.cache = cache
        self.selectedBackendProvider = selectedBackendProvider
        self.audioFileIO = audioFileIO
    }

    var isModelInstalled: Bool {
        NemotronDiarizationModelFiles.isInstalled(in: cacheDirectory)
    }

    var modelDirectory: URL {
        cacheDirectory
    }

    func download(events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws {
        AppLogger.info("Downloading Nemotron diarization model to \(cacheDirectory.path)")
        try await cache.download(cacheDirectory: cacheDirectory, events: events)
    }

    func deleteDownloadedModelFiles() async throws {
        await resetCache()
        for directory in [cacheDirectory, NemotronDiarizationModelFiles.stagingDirectory(for: cacheDirectory)] {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    func warmUp() async throws {
        try await cache.warmUp(cacheDirectory: cacheDirectory)
    }

    func resetCache() async {
        await cache.reset()
    }

    func diarize(recording: MeetingDiarizationRecording) async throws -> MeetingDiarizationResult {
        let chunks = recording.orderedChunks
        guard !chunks.isEmpty else {
            return Self.makeResult(turns: [], backendName: MeetingDiarizationBackend.nemotron.backendName)
        }

        let requestedBackend = selectedBackendProvider()
        let effectiveBackend = recording.backend
        guard chunks.count == 1 else {
            throw TranscriptionError.transcriptionFailed(
                "Meeting diarization expects one full-timeline recording chunk, got \(chunks.count)."
            )
        }
        let recordingDuration = recording.duration
        AppLogger.info(
            "Meeting diarization requested. selectedBackend=\(requestedBackend.rawValue), effectiveBackend=\(effectiveBackend.rawValue), strategy=\(recording.strategy.rawValue), inputPath=\(chunks[0].url.lastPathComponent), inputDuration=\(String(format: "%.2fs", recordingDuration))"
        )
        let samples = try audioFileIO.readMonoSamples(from: chunks[0].url, targetSampleRate: sampleRate)
        AppLogger.info(
            "Meeting diarization timeline samples: sampleCount=\(samples.count), sampleRate=\(sampleRate), requestedDuration=\(String(format: "%.2fs", recordingDuration))"
        )

        let rawTurns = try await cache.diarize(
            audioSamples: samples,
            sampleRate: sampleRate,
            cacheDirectory: cacheDirectory
        )
        AppLogger.info(
            "Meeting diarization Nemotron result: rawSegments=\(rawTurns.count), rawSpeakers=\(MeetingDiarizationDebug.speakerCounts(rawTurns))"
        )
        let postprocessedTurns = MeetingSpeakerTurnPostprocessor.postprocess(rawTurns)
        AppLogger.info(
            "Meeting diarization postprocessed turns: count=\(postprocessedTurns.count), coverage=\(MeetingDiarizationDebug.coverage(postprocessedTurns)), speakers=\(MeetingDiarizationDebug.speakerCounts(postprocessedTurns)), turns=\(MeetingDiarizationDebug.turns(postprocessedTurns))"
        )

        return Self.makeResult(turns: postprocessedTurns, backendName: effectiveBackend.backendName)
    }

    private static func makeResult(turns: [SpeakerTurn], backendName: String) -> MeetingDiarizationResult {
        let speakers = Set(turns.map(\.speakerId))
            .sorted()
            .map { MeetingDiarizationSpeaker(id: $0, label: "Speaker \($0 + 1)") }
        return MeetingDiarizationResult(
            speakers: speakers,
            turns: turns,
            backend: backendName,
            config: MeetingDiarizationConfig(
                backend: backendName,
                usesSileroPreFilter: false
            )
        )
    }

}

extension NemotronMeetingDiarizationClient: MeetingDiarizationModelManaging {}
