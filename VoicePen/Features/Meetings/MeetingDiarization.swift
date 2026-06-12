import ArgmaxCore
import Foundation
@preconcurrency import SpeakerKit

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
        backend: MeetingDiarizationBackend = .speakerKit,
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
    case speakerKit

    var id: String { rawValue }

    var displayName: String {
        "SpeakerKit"
    }

    var backendName: String {
        "speakerKit"
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

nonisolated enum SpeakerKitDiarizationModelFiles {
    static let repositoryId = "argmaxinc/speakerkit-coreml"
    static let completionMarkerFileName = ".voicepen-diarization-download-complete"

    nonisolated enum SpeakerKitModelVariant: CaseIterable, Sendable {
        case segmenter
        case embedder
        case clusterer

        var info: ModelInfo {
            switch self {
            case .segmenter:
                .segmenter()
            case .embedder:
                .embedder()
            case .clusterer:
                .plda()
            }
        }

        var readinessFiles: [String] {
            switch self {
            case .segmenter:
                ["SpeakerSegmenter.mlmodelc"]
            case .embedder:
                ["SpeakerEmbedder.mlmodelc", "SpeakerEmbedderPreprocessor.mlmodelc"]
            case .clusterer:
                ["PldaProjector.mlmodelc"]
            }
        }
    }

    static func modelDirectory(for variant: SpeakerKitModelVariant, in cacheDirectory: URL) -> URL {
        cacheDirectory.appendingPathComponent(variant.info.name, isDirectory: true)
    }

    static func modelRootDirectory(for variant: SpeakerKitModelVariant) -> String? {
        guard let version = variant.info.version,
            let modelVariant = variant.info.variant
        else {
            return nil
        }
        return "\(variant.info.name)/\(version)/\(modelVariant)"
    }

    static func requiredModelDirectories(for variant: SpeakerKitModelVariant) -> [String] {
        guard let modelRoot = modelRootDirectory(for: variant) else {
            return []
        }
        return variant.readinessFiles.map {
            "\(modelRoot)/\($0)"
        }
    }

    static func allRequiredModelDirectories() -> [String] {
        SpeakerKitModelVariant.allCases.flatMap(requiredModelDirectories(for:))
    }

    static func isInstalled(in cacheDirectory: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: completionMarkerURL(in: cacheDirectory).path) else {
            return false
        }
        for variant in SpeakerKitModelVariant.allCases {
            for directory in requiredModelDirectories(for: variant) {
                var isDirectory: ObjCBool = false
                let artifactURL = cacheDirectory.appendingPathComponent(directory, isDirectory: true)
                guard fileManager.fileExists(atPath: artifactURL.path, isDirectory: &isDirectory),
                    isDirectory.boolValue
                else {
                    return false
                }
            }
        }
        return true
    }

    static func completionMarkerURL(in cacheDirectory: URL) -> URL {
        cacheDirectory.appendingPathComponent(completionMarkerFileName)
    }
}

typealias SpeakerKitModelVariant = SpeakerKitDiarizationModelFiles.SpeakerKitModelVariant

nonisolated enum SpeakerKitDiarizationModelDownloadPlan {
    static func selectedFiles(
        from remotePaths: [String],
        for variant: SpeakerKitModelVariant
    ) -> [String] {
        guard let modelRoot = SpeakerKitDiarizationModelFiles.modelRootDirectory(for: variant) else {
            return []
        }
        let modelRootPrefix = "\(modelRoot.lowercased())/"
        return
            remotePaths
            .filter { remotePath in
                remotePath.lowercased().hasPrefix(modelRootPrefix)
            }
            .sorted()
    }

    static func containsRequiredFiles(_ files: [String], for variant: SpeakerKitModelVariant) -> Bool {
        guard let modelRoot = SpeakerKitDiarizationModelFiles.modelRootDirectory(for: variant) else {
            return false
        }
        let modelRootPrefix = "\(modelRoot.lowercased())/"
        return files.contains { $0.lowercased().hasPrefix(modelRootPrefix) }
    }
}

nonisolated struct HuggingFaceModelRevisionResponse: Decodable {
    struct Sibling: Decodable {
        let rfilename: String
    }

    let siblings: [Sibling]
}

nonisolated enum SpeakerKitDiarizationModelDownloadSessionConfiguration {
    static func make(proxy: ModelDownloadProxyConfiguration?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = true
        if let proxy {
            configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        }
        return configuration
    }
}

protocol SpeakerKitDiarizationRuntime: Sendable {
    func warmUp() async throws
    func diarize(audioSamples: [Float], sampleRate: Int) async throws -> [SpeakerTurn]
    func unload() async
}

protocol SpeakerKitDiarizationRuntimeFactory: Sendable {
    func makeRuntime(modelDirectory: URL) async throws -> SpeakerKitDiarizationRuntime
}

final class DefaultSpeakerKitDiarizationRuntimeFactory: SpeakerKitDiarizationRuntimeFactory {
    func makeRuntime(modelDirectory: URL) async throws -> SpeakerKitDiarizationRuntime {
        await SpeakerKitRuntime(modelDirectory: modelDirectory)
    }
}

private actor SpeakerKitRuntime: SpeakerKitDiarizationRuntime {
    private let sampleRate = 16_000
    private let modelDirectory: URL
    private var speakerKit: SpeakerKit?

    init(modelDirectory: URL) async {
        self.modelDirectory = modelDirectory
    }

    func warmUp() async throws {
        let model = try await loadOrCreate()
        try await model.ensureModelsLoaded()
    }

    func diarize(audioSamples: [Float], sampleRate: Int) async throws -> [SpeakerTurn] {
        guard sampleRate == self.sampleRate else {
            throw TranscriptionError.transcriptionFailed("SpeakerKit diarization expects \(self.sampleRate) Hz samples.")
        }
        let model = try await loadOrCreate()
        let options = PyannoteDiarizationOptions(numberOfSpeakers: nil)
        let result = try await model.diarize(audioArray: audioSamples, options: options)
        return extractTurns(from: result)
    }

    func unload() async {
        await speakerKit?.unloadModels()
        self.speakerKit = nil
    }

    private func loadOrCreate() async throws -> SpeakerKit {
        if let speakerKit {
            return speakerKit
        }

        let config = PyannoteConfig(modelFolder: modelDirectory.path, download: false, load: false)
        let speakerKit = try await SpeakerKit(config)
        self.speakerKit = speakerKit
        return speakerKit
    }

    private func extractTurns(from result: DiarizationResult) -> [SpeakerTurn] {
        var rawTurns: [SpeakerTurn] = []
        let segments = result.segments
        guard !segments.isEmpty else {
            AppLogger.debug("SpeakerKit diarization returned no speech segments.")
            return []
        }

        var droppedNoSpeaker = 0
        var droppedMultiSpeaker = 0
        for segment in segments {
            let speakerCount = segment.speaker.speakerIds.count
            guard speakerCount == 1, let speakerId = segment.speaker.speakerId else {
                if speakerCount == 0 {
                    droppedNoSpeaker += 1
                } else {
                    droppedMultiSpeaker += 1
                }
                continue
            }

            guard segment.endTime > segment.startTime else {
                continue
            }

            rawTurns.append(
                SpeakerTurn(
                    startOffset: TimeInterval(segment.startTime),
                    endOffset: TimeInterval(segment.endTime),
                    speakerId: speakerId,
                    confidence: nil
                )
            )
        }

        if droppedNoSpeaker > 0 {
            AppLogger.debug("SpeakerKit diarization dropped \(droppedNoSpeaker) no-speaker segments.")
        }
        if droppedMultiSpeaker > 0 {
            AppLogger.debug("SpeakerKit diarization dropped \(droppedMultiSpeaker) multi-speaker segments.")
        }

        return rawTurns
    }
}

final class SpeakerKitDiarizationModelDownloader: @unchecked Sendable {
    private let fileManager: FileManager
    private let proxyProvider: @Sendable () -> ModelDownloadProxyConfiguration?
    private let metadataFetcher: @Sendable (URL, URLSession) async throws -> [String]
    private let fileDownloader: @Sendable (URL, URL, URLSession, @escaping @Sendable (Double?) -> Void) async throws -> Void

    init(
        fileManager: FileManager = .default,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = {
            ModelDownloadProxyConfiguration.fromEnvironment()
        },
        metadataFetcher: (@Sendable (URL, URLSession) async throws -> [String])? = nil,
        fileDownloader: (@Sendable (URL, URL, URLSession, @escaping @Sendable (Double?) -> Void) async throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.proxyProvider = proxyProvider
        self.metadataFetcher = metadataFetcher ?? Self.defaultMetadataFetcher
        self.fileDownloader = fileDownloader ?? Self.defaultFileDownloader
    }

    func download(cacheDirectory: URL, events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws {
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let metadataURL = SpeakerKitDiarizationModelFiles.repositoryMetadataURL()

        let configuration = SpeakerKitDiarizationModelDownloadSessionConfiguration.make(proxy: proxyProvider())
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        AppLogger.info("Fetching SpeakerKit model metadata from \(metadataURL.absoluteString)")
        let remotePaths = try await metadataFetcher(metadataURL, session)

        let variants: [SpeakerKitModelVariant] = [.segmenter, .embedder, .clusterer]
        let totalFileCount = variants.reduce(0) { $0 + SpeakerKitDiarizationModelDownloadPlan.selectedFiles(from: remotePaths, for: $1).count }
        var completed = 0

        for variant in variants {
            AppLogger.info("Downloading SpeakerKit model variant \(variant.info.name)")
            let artifactDirectory = SpeakerKitDiarizationModelFiles.modelDirectory(for: variant, in: cacheDirectory)
            try fileManager.createDirectory(at: artifactDirectory, withIntermediateDirectories: true)
            let selectedFiles = SpeakerKitDiarizationModelDownloadPlan.selectedFiles(from: remotePaths, for: variant)
            guard SpeakerKitDiarizationModelDownloadPlan.containsRequiredFiles(selectedFiles, for: variant) else {
                throw ModelDownloadError.downloadFailed(
                    modelId: SpeakerKitDiarizationModelFiles.repositoryId,
                    message: "\(variant.info.name) metadata did not include files under \(variant.info.downloadPattern)."
                )
            }

            for remotePath in selectedFiles {
                let sourceURL = SpeakerKitDiarizationModelFiles.resolveURL(
                    for: remotePath,
                    repositoryId: SpeakerKitDiarizationModelFiles.repositoryId
                )
                let destinationURL = cacheDirectory.appendingPathComponent(remotePath)

                try await downloadWithRetry(label: "\(variant.info.name)/\(remotePath)") {
                    let currentCompleted = completed
                    try await self.fileDownloader(sourceURL, destinationURL, session) { progress in
                        let completedProgress = Double(currentCompleted) / Double(max(1, totalFileCount))
                        let stageProgress = min(
                            1,
                            completedProgress + (progress ?? 0) / Double(max(1, totalFileCount))
                        )
                        events(.downloadingArtifact(name: destinationURL.lastPathComponent, progress: stageProgress))
                    }
                }
                completed += 1
                events(.downloadingArtifact(name: destinationURL.lastPathComponent, progress: nil))
            }
        }

        try Data("complete".utf8).write(
            to: SpeakerKitDiarizationModelFiles.completionMarkerURL(in: cacheDirectory),
            options: .atomic
        )
        events(.completed)
    }

    private func downloadWithRetry(
        label: String,
        maxAttempts: Int = 3,
        operation: () async throws -> Void
    ) async throws {
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                if attempt > 1 {
                    AppLogger.info("Retrying SpeakerKit download \(label), attempt \(attempt)")
                }
                try await operation()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < maxAttempts && error.isRetryableModelDownloadError {
                    AppLogger.debug("SpeakerKit download attempt for \(label) failed: \(error.localizedDescription)")
                    try await Task.sleep(for: .seconds(Double(attempt)))
                    continue
                }
                throw lastError ?? TranscriptionError.transcriptionFailed("Could not download \(label).")
            }
        }
    }

    private static func defaultMetadataFetcher(_ metadataURL: URL, _ session: URLSession) async throws -> [String] {
        let (data, response) = try await session.data(from: metadataURL)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw ModelDownloadError.downloadFailed(modelId: metadataURL.absoluteString, message: "Unexpected Hugging Face metadata response.")
        }
        let revision = try JSONDecoder().decode(HuggingFaceModelRevisionResponse.self, from: data)
        return revision.siblings.map(\.rfilename)
    }

    private static func defaultFileDownloader(
        _ sourceURL: URL,
        _ destinationURL: URL,
        _ session: URLSession,
        _ progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let (temporaryURL, response) = try await session.download(from: sourceURL)
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            throw ModelDownloadError.downloadFailed(modelId: sourceURL.lastPathComponent, message: "Could not download \(sourceURL.lastPathComponent).")
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        progress(1)
    }
}

final class SpeakerKitDiarizationModelCache: Sendable {
    private let runtimeFactory: SpeakerKitDiarizationRuntimeFactory
    private let downloader: SpeakerKitDiarizationModelDownloader

    init(
        runtimeFactory: SpeakerKitDiarizationRuntimeFactory = DefaultSpeakerKitDiarizationRuntimeFactory(),
        downloader: SpeakerKitDiarizationModelDownloader = SpeakerKitDiarizationModelDownloader()
    ) {
        self.runtimeFactory = runtimeFactory
        self.downloader = downloader
        self.wrapped = Wrapped(runtimeFactory: runtimeFactory)
    }

    actor Wrapped {
        private let runtimeFactory: SpeakerKitDiarizationRuntimeFactory
        private var runtime: SpeakerKitDiarizationRuntime?

        init(runtimeFactory: SpeakerKitDiarizationRuntimeFactory) {
            self.runtimeFactory = runtimeFactory
        }

        func runtime(for modelDirectory: URL) async throws -> SpeakerKitDiarizationRuntime {
            if let runtime {
                return runtime
            }
            let newRuntime = try await runtimeFactory.makeRuntime(modelDirectory: modelDirectory)
            runtime = newRuntime
            return newRuntime
        }

        func warmUp(modelDirectory: URL) async throws {
            let runtime = try await runtime(for: modelDirectory)
            try await runtime.warmUp()
        }

        func diarize(audioSamples: [Float], sampleRate: Int, modelDirectory: URL) async throws -> [SpeakerTurn] {
            let runtime = try await runtime(for: modelDirectory)
            return try await runtime.diarize(audioSamples: audioSamples, sampleRate: sampleRate)
        }

        func reset() async {
            if let runtime {
                await runtime.unload()
            }
            runtime = nil
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

final class SpeakerKitMeetingDiarizationClient: MeetingDiarizationClient {
    private let cacheDirectory: URL
    private let selectedBackendProvider: () -> MeetingDiarizationBackend
    private let audioFileIO: MeetingAudioFileIO
    private let sampleRate = 16_000
    private let cache: SpeakerKitDiarizationModelCache

    init(
        cacheDirectory: URL,
        cache: SpeakerKitDiarizationModelCache = SpeakerKitDiarizationModelCache(),
        selectedBackendProvider: @escaping () -> MeetingDiarizationBackend = { .speakerKit },
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO()
    ) {
        self.cacheDirectory = cacheDirectory
        self.cache = cache
        self.selectedBackendProvider = selectedBackendProvider
        self.audioFileIO = audioFileIO
    }

    var isModelInstalled: Bool {
        SpeakerKitDiarizationModelFiles.isInstalled(in: cacheDirectory)
    }

    var modelDirectory: URL {
        cacheDirectory
    }

    func download(events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws {
        AppLogger.info("Downloading SpeakerKit diarization model to \(cacheDirectory.path)")
        try await cache.download(cacheDirectory: cacheDirectory, events: events)
    }

    func deleteDownloadedModelFiles() async throws {
        await resetCache()
        if FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try FileManager.default.removeItem(at: cacheDirectory)
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
            return Self.makeResult(turns: [], backendName: MeetingDiarizationBackend.speakerKit.backendName)
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
            "Meeting diarization SpeakerKit result: rawSegments=\(rawTurns.count), rawSpeakers=\(MeetingDiarizationDebug.speakerCounts(rawTurns))"
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

private extension SpeakerKitDiarizationModelFiles {
    static func repositoryMetadataURL() -> URL {
        URL(string: "https://huggingface.co/api/models/\(repositoryId)/revision/main")!
    }

    static func resolveURL(for remotePath: String, repositoryId: String) -> URL {
        let encodedPath =
            remotePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(repositoryId)/resolve/main/\(encodedPath)")!
    }
}

extension SpeakerKitMeetingDiarizationClient: MeetingDiarizationModelManaging {}
