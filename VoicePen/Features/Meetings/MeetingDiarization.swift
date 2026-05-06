import AVFoundation
import AudioCommon
import Foundation
import SpeechVAD

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

nonisolated struct DiarizationChunk: Equatable, Sendable {
    var startOffset: TimeInterval
    var duration: TimeInterval

    var endOffset: TimeInterval {
        startOffset + duration
    }
}

nonisolated enum MeetingDiarizationChunkPlanner {
    static func chunks(
        recordingDuration: TimeInterval,
        chunkDuration requestedChunkDuration: TimeInterval = 120,
        overlap requestedOverlap: TimeInterval = 3
    ) -> [DiarizationChunk] {
        guard recordingDuration > 0 else { return [] }
        guard recordingDuration > 10 * 60 else {
            return [DiarizationChunk(startOffset: 0, duration: recordingDuration)]
        }

        let chunkDuration = min(120, max(60, requestedChunkDuration))
        let overlap = min(5, max(2, requestedOverlap))
        let step = max(1, chunkDuration - overlap)
        var chunks: [DiarizationChunk] = []
        var start: TimeInterval = 0

        while start < recordingDuration {
            let end = min(recordingDuration, start + chunkDuration)
            chunks.append(DiarizationChunk(startOffset: start, duration: end - start))
            guard end < recordingDuration else { break }
            start += step
        }

        return chunks
    }
}

nonisolated struct MeetingDiarizationRecording: Equatable, Sendable {
    var chunks: [MeetingAudioChunk]
    var maximumDuration: TimeInterval
    var expectedSpeakerCount: Int?

    var orderedChunks: [MeetingAudioChunk] {
        chunks
            .filter { $0.duration > 0 && $0.startOffset < maximumDuration }
            .sorted { $0.startOffset < $1.startOffset }
    }

    var duration: TimeInterval {
        min(maximumDuration, orderedChunks.map { $0.startOffset + $0.duration }.max() ?? 0)
    }
}

nonisolated struct MeetingDiarizationSpeaker: Equatable, Sendable {
    var id: Int
    var label: String
}

nonisolated struct MeetingDiarizationConfig: Equatable, Sendable {
    var expectedSpeakerCount: Int?
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

    static func chunks(_ chunks: [DiarizationChunk], limit: Int = 8) -> String {
        intervals(chunks.map { ($0.startOffset, $0.endOffset) }, limit: limit)
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
        for index in 1..<(turns.count - 1) {
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

actor SpeechSwiftDiarizationModelCache {
    private let downloader: SpeechSwiftDiarizationModelDownloader
    private var pipeline: PyannoteDiarizationPipeline?

    init(downloader: SpeechSwiftDiarizationModelDownloader = SpeechSwiftDiarizationModelDownloader()) {
        self.downloader = downloader
    }

    private func diarizationPipeline(cacheDirectory: URL) async throws -> PyannoteDiarizationPipeline {
        if let pipeline {
            return pipeline
        }

        try SpeechSwiftDiarizationModelFiles.ensureOfflineSentinels(in: cacheDirectory)
        let loadedPipeline = try await DiarizationPipeline.fromPretrained(
            embeddingEngine: .coreml,
            useVADFilter: false,
            cacheBaseDir: cacheDirectory,
            offlineMode: true
        ) { progress, stage in
            AppLogger.debug(
                "Meeting diarization model load: progress=\(String(format: "%.0f%%", progress * 100)), stage=\(stage)"
            )
        }
        pipeline = loadedPipeline
        return loadedPipeline
    }

    func diarize(
        samples: [Float],
        sampleRate: Int,
        cacheDirectory: URL,
        expectedSpeakerCount: Int?
    ) async throws -> SpeechVAD.DiarizationResult {
        let pipeline = try await diarizationPipeline(cacheDirectory: cacheDirectory)
        if let expectedSpeakerCount {
            AppLogger.info(
                "Meeting diarization expectedSpeakers=\(expectedSpeakerCount) captured in VoicePen request; speech-swift Pyannote backend currently uses its default global clustering threshold."
            )
        }
        return pipeline.diarize(audio: samples, sampleRate: sampleRate, config: .default) { progress, stage in
            AppLogger.debug(
                "Meeting diarization speech-swift pipeline: progress=\(String(format: "%.0f%%", progress * 100)), stage=\(stage)"
            )
            return !Task.isCancelled
        }
    }

    func warmUp(cacheDirectory: URL) async throws {
        let pipeline = try await diarizationPipeline(cacheDirectory: cacheDirectory)
        _ = pipeline.diarize(
            audio: Self.warmupSamples(sampleRate: 16_000),
            sampleRate: 16_000,
            config: .default
        ) { _, _ in
            !Task.isCancelled
        }
    }

    private static func warmupSamples(sampleRate: Int) -> [Float] {
        let duration = 10
        let totalSamples = sampleRate * duration
        return (0..<totalSamples).map { index in
            let phase = 2 * Double.pi * 220 * Double(index) / Double(sampleRate)
            return Float(sin(phase) * 0.03)
        }
    }

    func download(
        cacheDirectory: URL,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        pipeline = nil

        let segmentationArtifact = SpeechSwiftDiarizationModelFiles.segmentationArtifact(in: cacheDirectory)
        AppLogger.info("Downloading meeting diarization segmentation model \(segmentationArtifact.modelId) from \(segmentationArtifact.metadataURL.absoluteString)")
        try await downloadWithRetry(label: "meeting diarization segmentation model \(segmentationArtifact.modelId)") {
            try await downloader.download(artifact: segmentationArtifact) { progress in
                progressHandler(progress * 0.45, "Pyannote segmentation")
            }
        }
        AppLogger.info("Downloaded meeting diarization segmentation model \(segmentationArtifact.modelId)")

        let embeddingArtifact = SpeechSwiftDiarizationModelFiles.embeddingArtifact(in: cacheDirectory)
        AppLogger.info("Downloading meeting diarization speaker embedding model \(embeddingArtifact.modelId) from \(embeddingArtifact.metadataURL.absoluteString)")
        try await downloadWithRetry(label: "meeting diarization speaker embedding model \(embeddingArtifact.modelId)") {
            try await downloader.download(artifact: embeddingArtifact) { progress in
                progressHandler(0.45 + progress * 0.55, "WeSpeaker")
            }
        }
        AppLogger.info("Downloaded meeting diarization speaker embedding model \(embeddingArtifact.modelId)")

        pipeline = try await diarizationPipeline(cacheDirectory: cacheDirectory)
    }

    func reset() {
        pipeline = nil
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
                    AppLogger.info("Retrying \(label), attempt \(attempt)")
                }
                try await operation()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                AppLogger.error("\(label) download attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(Double(attempt)))
                }
            }
        }
        throw lastError ?? TranscriptionError.transcriptionFailed("Could not download \(label).")
    }
}

nonisolated enum SpeechSwiftDiarizationModelArtifactKind: Equatable, Sendable {
    case safetensors
    case coreML(compiledModelDirectoryName: String)
}

nonisolated struct SpeechSwiftDiarizationModelArtifact: Equatable, Sendable {
    let displayName: String
    let modelId: String
    let kind: SpeechSwiftDiarizationModelArtifactKind
    let destinationDirectory: URL

    init(
        displayName: String,
        modelId: String,
        kind: SpeechSwiftDiarizationModelArtifactKind,
        destinationDirectory: URL
    ) {
        self.displayName = displayName
        self.modelId = modelId
        self.kind = kind
        self.destinationDirectory = destinationDirectory
    }

    init(
        displayName: String,
        modelId: String,
        compiledModelDirectoryName: String,
        destinationDirectory: URL
    ) {
        self.init(
            displayName: displayName,
            modelId: modelId,
            kind: .coreML(compiledModelDirectoryName: compiledModelDirectoryName),
            destinationDirectory: destinationDirectory
        )
    }

    var metadataURL: URL {
        URL(string: "https://huggingface.co/api/models/\(modelId)/revision/main")!
    }

    func resolveURL(for remotePath: String) -> URL {
        let encodedPath =
            remotePath
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { component in
                String(component).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String(component)
            }
            .joined(separator: "/")
        return URL(string: "https://huggingface.co/\(modelId)/resolve/main/\(encodedPath)")!
    }
}

nonisolated enum SpeechSwiftDiarizationModelFiles {
    static let segmentationModelId = PyannoteVADModel.defaultModelId
    static let embeddingModelId = WeSpeakerModel.defaultCoreMLModelId
    static let embeddingCompiledModelDirectoryName = "wespeaker.mlmodelc"
    private static let offlineSentinelFileName = ".voicepen-coreml-offline.safetensors"

    static func segmentationDirectory(in cacheDirectory: URL) -> URL {
        hubStyleDirectory(for: segmentationModelId, in: cacheDirectory)
    }

    static func embeddingDirectory(in cacheDirectory: URL) -> URL {
        hubStyleDirectory(for: embeddingModelId, in: cacheDirectory)
    }

    static func segmentationArtifact(in cacheDirectory: URL) -> SpeechSwiftDiarizationModelArtifact {
        SpeechSwiftDiarizationModelArtifact(
            displayName: "Pyannote segmentation",
            modelId: segmentationModelId,
            kind: .safetensors,
            destinationDirectory: segmentationDirectory(in: cacheDirectory)
        )
    }

    static func embeddingArtifact(in cacheDirectory: URL) -> SpeechSwiftDiarizationModelArtifact {
        SpeechSwiftDiarizationModelArtifact(
            displayName: "WeSpeaker",
            modelId: embeddingModelId,
            compiledModelDirectoryName: embeddingCompiledModelDirectoryName,
            destinationDirectory: embeddingDirectory(in: cacheDirectory)
        )
    }

    static func isInstalled(in cacheDirectory: URL) -> Bool {
        let segmentationDir = segmentationDirectory(in: cacheDirectory)
        let embeddingDir = embeddingDirectory(in: cacheDirectory)
        let embeddingModelDir = embeddingDir.appendingPathComponent(
            embeddingCompiledModelDirectoryName,
            isDirectory: true
        )
        let fileManager = FileManager.default

        return containsSafetensors(in: segmentationDir)
            && fileManager.fileExists(atPath: segmentationDir.appendingPathComponent("config.json").path)
            && fileManager.fileExists(atPath: embeddingModelDir.path)
            && fileManager.fileExists(atPath: embeddingDir.appendingPathComponent("config.json").path)
    }

    static func offlineSentinelURL(in directory: URL) -> URL {
        directory.appendingPathComponent(offlineSentinelFileName)
    }

    static func ensureOfflineSentinels(in cacheDirectory: URL) throws {
        try ensureOfflineSentinel(
            directory: embeddingDirectory(in: cacheDirectory),
            compiledModelDirectoryName: embeddingCompiledModelDirectoryName
        )
    }

    private static func ensureOfflineSentinel(
        directory: URL,
        compiledModelDirectoryName: String
    ) throws {
        let compiledModelURL = directory.appendingPathComponent(compiledModelDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: compiledModelURL.path) else { return }
        let sentinelURL = offlineSentinelURL(in: directory)
        guard !FileManager.default.fileExists(atPath: sentinelURL.path) else { return }

        // speech-swift's CoreML offline check currently looks for a safetensors file
        // even though the CoreML backend loads .mlmodelc bundles.
        try Data("coreml".utf8).write(to: sentinelURL, options: .atomic)
    }

    private static func hubStyleDirectory(for modelId: String, in cacheDirectory: URL) -> URL {
        modelId
            .split(separator: "/")
            .reduce(cacheDirectory.appendingPathComponent("models", isDirectory: true)) { url, component in
                url.appendingPathComponent(String(component), isDirectory: true)
            }
    }

    private static func containsSafetensors(in directory: URL) -> Bool {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else {
            return false
        }
        return contents.contains { $0.pathExtension == "safetensors" }
    }
}

nonisolated enum SpeechSwiftDiarizationModelDownloadPlan {
    static func files(
        from remotePaths: [String],
        kind: SpeechSwiftDiarizationModelArtifactKind
    ) -> [String] {
        switch kind {
        case .safetensors:
            return safetensorsFiles(from: remotePaths)
        case let .coreML(compiledModelDirectoryName):
            return files(from: remotePaths, compiledModelDirectoryName: compiledModelDirectoryName)
        }
    }

    static func files(from remotePaths: [String], compiledModelDirectoryName: String) -> [String] {
        remotePaths
            .filter { remotePath in
                remotePath == "config.json" || remotePath.hasPrefix("\(compiledModelDirectoryName)/")
            }
            .sorted()
    }

    static func safetensorsFiles(from remotePaths: [String]) -> [String] {
        remotePaths
            .filter { remotePath in
                remotePath == "config.json"
                    || remotePath == "model.safetensors.index.json"
                    || URL(fileURLWithPath: remotePath).pathExtension == "safetensors"
            }
            .sorted()
    }

    static func containsRequiredFiles(
        _ files: [String],
        for kind: SpeechSwiftDiarizationModelArtifactKind
    ) -> Bool {
        guard files.contains("config.json") else { return false }
        switch kind {
        case .safetensors:
            return files.contains { URL(fileURLWithPath: $0).pathExtension == "safetensors" }
        case let .coreML(compiledModelDirectoryName):
            return files.contains { $0.hasPrefix("\(compiledModelDirectoryName)/") }
        }
    }
}

nonisolated enum SpeechSwiftDiarizationModelDownloadSessionConfiguration {
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

nonisolated private struct HuggingFaceModelRevisionResponse: Decodable {
    struct Sibling: Decodable {
        let rfilename: String
    }

    let siblings: [Sibling]
}

nonisolated final class SpeechSwiftDiarizationModelDownloader: @unchecked Sendable {
    private let proxyProvider: @Sendable () -> ModelDownloadProxyConfiguration?
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = {
            ModelDownloadProxyConfiguration.fromEnvironment()
        }
    ) {
        self.fileManager = fileManager
        self.proxyProvider = proxyProvider
    }

    func download(
        artifact: SpeechSwiftDiarizationModelArtifact,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try fileManager.createDirectory(at: artifact.destinationDirectory, withIntermediateDirectories: true)
        let session = URLSession(
            configuration: SpeechSwiftDiarizationModelDownloadSessionConfiguration.make(proxy: proxyProvider())
        )
        defer { session.invalidateAndCancel() }

        AppLogger.info("Fetching meeting diarization metadata from \(artifact.metadataURL.absoluteString)")
        let remotePaths = try await remotePaths(for: artifact, session: session)
        let files = SpeechSwiftDiarizationModelDownloadPlan.files(
            from: remotePaths,
            kind: artifact.kind
        )
        guard SpeechSwiftDiarizationModelDownloadPlan.containsRequiredFiles(files, for: artifact.kind) else {
            throw ModelDownloadError.downloadFailed(
                modelId: artifact.modelId,
                message: "Hugging Face metadata did not include required diarization model files."
            )
        }

        for (index, remotePath) in files.enumerated() {
            try Task.checkCancellation()
            try await downloadFile(
                remotePath,
                artifact: artifact,
                session: session
            )
            progress(Double(index + 1) / Double(files.count))
        }

        if case .coreML = artifact.kind {
            try Data("coreml".utf8).write(
                to: SpeechSwiftDiarizationModelFiles.offlineSentinelURL(in: artifact.destinationDirectory),
                options: .atomic
            )
        }
    }

    private func remotePaths(
        for artifact: SpeechSwiftDiarizationModelArtifact,
        session: URLSession
    ) async throws -> [String] {
        let (data, response) = try await session.data(from: artifact.metadataURL)
        try validate(response: response, modelId: artifact.modelId, source: artifact.metadataURL)
        let revision = try JSONDecoder().decode(HuggingFaceModelRevisionResponse.self, from: data)
        return revision.siblings.map(\.rfilename)
    }

    private func downloadFile(
        _ remotePath: String,
        artifact: SpeechSwiftDiarizationModelArtifact,
        session: URLSession
    ) async throws {
        let destinationURL = artifact.destinationDirectory.appendingPathComponent(remotePath)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sourceURL = artifact.resolveURL(for: remotePath)
        let (temporaryURL, response) = try await session.download(from: sourceURL)
        try validate(response: response, modelId: artifact.modelId, source: sourceURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func validate(response: URLResponse, modelId: String, source: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelDownloadError.downloadFailed(modelId: modelId, message: "Unexpected response from \(source.absoluteString).")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ModelDownloadError.downloadFailed(
                modelId: modelId,
                message: "HTTP \(httpResponse.statusCode) from \(source.absoluteString)."
            )
        }
    }
}

final class SpeechSwiftMeetingDiarizationClient: MeetingDiarizationClient {
    private static let backendName = "speech-swift-pyannote"

    private let cacheDirectory: URL
    private let cache: SpeechSwiftDiarizationModelCache
    private let sampleRate = 16_000

    init(
        cacheDirectory: URL,
        cache: SpeechSwiftDiarizationModelCache = SpeechSwiftDiarizationModelCache()
    ) {
        self.cacheDirectory = cacheDirectory
        self.cache = cache
    }

    var isModelInstalled: Bool {
        SpeechSwiftDiarizationModelFiles.isInstalled(in: cacheDirectory)
    }

    var modelDirectory: URL {
        cacheDirectory
    }

    func download(events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        AppLogger.info("Preparing meeting diarization model download in \(cacheDirectory.path)")
        events(.downloadingArtifact(name: "Meeting diarization", progress: nil))
        try await cache.download(cacheDirectory: cacheDirectory) { progress, message in
            events(.downloadingArtifact(name: message, progress: progress))
        }
        try Data("complete".utf8).write(to: completionMarkerURL, options: .atomic)
        AppLogger.info("Meeting diarization model download marker written to \(completionMarkerURL.path)")
        events(.completed)
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
            return Self.makeResult(turns: [], expectedSpeakerCount: recording.expectedSpeakerCount)
        }

        let recordingDuration = recording.duration
        let diarizationChunks = MeetingDiarizationChunkPlanner.chunks(recordingDuration: recordingDuration)
        AppLogger.info(
            "Meeting diarization started: backend=pyannote-pipeline, chunks=\(chunks.count), recording=\(MeetingDiarizationDebug.interval(0, recordingDuration)), expectedSpeakers=\(recording.expectedSpeakerCount.map(String.init) ?? "auto"), sileroPreFilter=false"
        )
        AppLogger.debug(
            "Meeting diarization input chunks: \(MeetingDiarizationDebug.intervals(chunks.map { ($0.startOffset, $0.startOffset + $0.duration) }))"
        )
        AppLogger.info(
            "Meeting diarization physical chunk strategy: count=\(diarizationChunks.count), chunks=\(MeetingDiarizationDebug.chunks(diarizationChunks)); speech-swift pipeline receives full recording audio"
        )

        let samples = try samplesForFullRecording(duration: recordingDuration, from: chunks)
        AppLogger.info(
            "Meeting diarization full-recording audio prepared: samples=\(samples.count), sampleRate=\(sampleRate)"
        )
        let speechSwiftResult = try await cache.diarize(
            samples: samples,
            sampleRate: sampleRate,
            cacheDirectory: cacheDirectory,
            expectedSpeakerCount: recording.expectedSpeakerCount
        )

        let rawTurns = speechSwiftResult.segments.map { segment in
            SpeakerTurn(
                startOffset: TimeInterval(segment.startTime),
                endOffset: TimeInterval(segment.endTime),
                speakerId: segment.speakerId,
                confidence: nil
            )
        }
        AppLogger.info(
            "Meeting diarization speech-swift result: rawSegments=\(rawTurns.count), reportedSpeakers=\(speechSwiftResult.numSpeakers), speakers=\(MeetingDiarizationDebug.speakerCounts(rawTurns)), turns=\(MeetingDiarizationDebug.turns(rawTurns))"
        )
        let postprocessedTurns = MeetingSpeakerTurnPostprocessor.postprocess(rawTurns)
        AppLogger.info(
            "Meeting diarization postprocessed turns: count=\(postprocessedTurns.count), coverage=\(MeetingDiarizationDebug.coverage(postprocessedTurns)), speakers=\(MeetingDiarizationDebug.speakerCounts(postprocessedTurns)), turns=\(MeetingDiarizationDebug.turns(postprocessedTurns))"
        )

        return Self.makeResult(turns: postprocessedTurns, expectedSpeakerCount: recording.expectedSpeakerCount)
    }

    private static func makeResult(
        turns: [SpeakerTurn],
        expectedSpeakerCount: Int?
    ) -> MeetingDiarizationResult {
        let speakers = Set(turns.map(\.speakerId))
            .sorted()
            .map { MeetingDiarizationSpeaker(id: $0, label: "Speaker \($0 + 1)") }
        return MeetingDiarizationResult(
            speakers: speakers,
            turns: turns,
            backend: backendName,
            config: MeetingDiarizationConfig(
                expectedSpeakerCount: expectedSpeakerCount,
                backend: backendName,
                usesSileroPreFilter: false
            )
        )
    }

    private func samplesForFullRecording(
        duration: TimeInterval,
        from chunks: [MeetingAudioChunk]
    ) throws -> [Float] {
        guard duration > 0 else { return [] }
        var samples: [Float] = []
        var cursor: TimeInterval = 0
        for chunk in chunks {
            let overlapStart = max(cursor, chunk.startOffset)
            let overlapEnd = min(duration, chunk.startOffset + chunk.duration)
            guard overlapEnd > overlapStart else { continue }

            if overlapStart > cursor {
                samples.append(contentsOf: silence(duration: overlapStart - cursor))
            }
            let chunkSamples = try Self.readMonoSamples(from: chunk.url, targetSampleRate: sampleRate)
            samples.append(
                contentsOf: slice(
                    chunkSamples,
                    start: overlapStart - chunk.startOffset,
                    end: overlapEnd - chunk.startOffset
                ))
            cursor = overlapEnd
        }

        if cursor < duration {
            samples.append(contentsOf: silence(duration: duration - cursor))
        }
        return samples
    }

    private func silence(duration: TimeInterval) -> [Float] {
        Array(repeating: 0, count: max(0, Int((duration * Double(sampleRate)).rounded())))
    }

    private func slice(_ samples: [Float], start: TimeInterval, end: TimeInterval) -> [Float] {
        let startFrame = max(0, min(samples.count, Int((start * Double(sampleRate)).rounded(.down))))
        let endFrame = max(startFrame, min(samples.count, Int((end * Double(sampleRate)).rounded(.up))))
        return Array(samples[startFrame..<endFrame])
    }

    private static func readMonoSamples(from url: URL, targetSampleRate: Int) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            )
        else {
            throw TranscriptionError.transcriptionFailed("Could not create diarization audio buffer.")
        }

        try audioFile.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw TranscriptionError.transcriptionFailed("Could not read diarization audio samples.")
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }

        var samples = [Float]()
        samples.reserveCapacity(frameLength)
        for frame in 0..<frameLength {
            var value: Float = 0
            for channel in 0..<channelCount {
                value += channelData[channel][frame]
            }
            samples.append(value / Float(channelCount))
        }

        let inputSampleRate = Int(format.sampleRate)
        guard inputSampleRate != targetSampleRate else { return samples }
        return AudioFileLoader.resample(samples, from: inputSampleRate, to: targetSampleRate)
    }

    private var completionMarkerURL: URL {
        cacheDirectory.appendingPathComponent(".voicepen-diarization-download-complete")
    }
}

extension SpeechSwiftMeetingDiarizationClient: MeetingDiarizationModelManaging {}
