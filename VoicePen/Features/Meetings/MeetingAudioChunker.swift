import AVFoundation
import Foundation

protocol MeetingAudioChunker: AnyObject {
    func split(
        _ chunks: [MeetingAudioChunk],
        maximumDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) async throws -> MeetingAudioChunkingResult
}

nonisolated struct MeetingAudioChunkingResult: Equatable, Sendable {
    var chunks: [MeetingAudioChunk]
    var temporaryURLs: [URL]
    var sourceSpans: [MeetingAudioSourceSpan] = []
}

nonisolated struct MeetingAudioSourceSpan: Equatable, Sendable {
    var chunkURL: URL
    var source: MeetingSourceKind
    var sourceURL: URL
    var sourceStartOffset: TimeInterval
    var startOffset: TimeInterval
    var duration: TimeInterval
}

nonisolated enum MeetingAudioChunkWindowPlanner {
    static func windows(
        for chunk: MeetingAudioChunk,
        maximumDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) -> [MeetingAudioChunk] {
        guard chunk.duration > 0,
            chunk.startOffset < maximumDuration,
            chunkDuration > 0
        else {
            return []
        }

        var windows: [MeetingAudioChunk] = []
        var elapsed: TimeInterval = 0
        var remaining = min(chunk.duration, maximumDuration - chunk.startOffset)

        while remaining > 0 {
            let duration = min(remaining, chunkDuration)
            windows.append(
                MeetingAudioChunk(
                    url: chunk.url,
                    source: chunk.source,
                    startOffset: chunk.startOffset + elapsed,
                    duration: duration
                )
            )
            elapsed += duration
            remaining -= duration
        }

        return windows
    }

    fileprivate static func timelineWindows(
        for chunks: [MeetingAudioChunk],
        maximumDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) -> [MeetingAudioTimelineWindow] {
        guard maximumDuration > 0, chunkDuration > 0 else { return [] }

        let cappedEndOffset =
            chunks
            .map { min(maximumDuration, $0.startOffset + max(0, $0.duration)) }
            .max() ?? 0
        guard cappedEndOffset > 0 else { return [] }

        var windows: [MeetingAudioTimelineWindow] = []
        var windowStart: TimeInterval = 0
        while windowStart < cappedEndOffset {
            let windowEnd = min(cappedEndOffset, windowStart + chunkDuration)
            let contributors = chunks.compactMap { chunk -> MeetingAudioTimelineContributor? in
                let chunkStart = chunk.startOffset
                let chunkEnd = min(maximumDuration, chunk.startOffset + max(0, chunk.duration))
                let overlapStart = max(windowStart, chunkStart)
                let overlapEnd = min(windowEnd, chunkEnd)
                guard overlapEnd > overlapStart else { return nil }

                return MeetingAudioTimelineContributor(
                    chunk: chunk,
                    overlapStart: overlapStart,
                    duration: overlapEnd - overlapStart
                )
            }

            if !contributors.isEmpty {
                windows.append(
                    MeetingAudioTimelineWindow(
                        startOffset: windowStart,
                        duration: windowEnd - windowStart,
                        contributors: contributors
                    )
                )
            }
            windowStart = windowEnd
        }

        return windows
    }
}

nonisolated private struct MeetingAudioTimelineWindow: Equatable, Sendable {
    var startOffset: TimeInterval
    var duration: TimeInterval
    var contributors: [MeetingAudioTimelineContributor]
}

nonisolated private struct MeetingAudioTimelineContributor: Equatable, Sendable {
    var chunk: MeetingAudioChunk
    var overlapStart: TimeInterval
    var duration: TimeInterval
}

final class AVFoundationMeetingAudioChunker: MeetingAudioChunker {
    private let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func split(
        _ chunks: [MeetingAudioChunk],
        maximumDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) async throws -> MeetingAudioChunkingResult {
        let outputDirectory = outputDirectory
        return try await Task.detached(priority: .userInitiated) {
            try splitChunks(
                chunks,
                maximumDuration: maximumDuration,
                chunkDuration: chunkDuration,
                outputDirectory: outputDirectory,
                fileManager: .default
            )
        }.value
    }
}

final class PassthroughMeetingAudioChunker: MeetingAudioChunker {
    func split(
        _ chunks: [MeetingAudioChunk],
        maximumDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) async throws -> MeetingAudioChunkingResult {
        let windows = chunks.flatMap {
            MeetingAudioChunkWindowPlanner.windows(
                for: $0,
                maximumDuration: maximumDuration,
                chunkDuration: chunkDuration
            )
        }
        return MeetingAudioChunkingResult(
            chunks: windows,
            temporaryURLs: [],
            sourceSpans: windows.map { window in
                MeetingAudioSourceSpan(
                    chunkURL: window.url,
                    source: window.source,
                    sourceURL: window.url,
                    sourceStartOffset: window.startOffset,
                    startOffset: window.startOffset,
                    duration: window.duration
                )
            }
        )
    }
}

nonisolated private func splitChunks(
    _ chunks: [MeetingAudioChunk],
    maximumDuration: TimeInterval,
    chunkDuration: TimeInterval,
    outputDirectory: URL,
    fileManager: FileManager
) throws -> MeetingAudioChunkingResult {
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    var splitChunks: [MeetingAudioChunk] = []
    var temporaryURLs: [URL] = []
    var sourceSpans: [MeetingAudioSourceSpan] = []

    do {
        let timelineWindows = MeetingAudioChunkWindowPlanner.timelineWindows(
            for: chunks,
            maximumDuration: maximumDuration,
            chunkDuration: chunkDuration
        )

        for window in timelineWindows {
            if window.contributors.count > 1 {
                let outputURL = try writeMixedAudioWindow(window, outputDirectory: outputDirectory)
                temporaryURLs.append(outputURL)
                splitChunks.append(
                    MeetingAudioChunk(
                        url: outputURL,
                        source: mergedSource(for: window.contributors),
                        startOffset: window.startOffset,
                        duration: window.duration
                    )
                )
                sourceSpans.append(
                    contentsOf: window.contributors.map { contributor in
                        MeetingAudioSourceSpan(
                            chunkURL: outputURL,
                            source: contributor.chunk.source,
                            sourceURL: contributor.chunk.url,
                            sourceStartOffset: contributor.chunk.startOffset,
                            startOffset: contributor.overlapStart,
                            duration: contributor.duration
                        )
                    }
                )
                continue
            }

            guard let contributor = window.contributors.first else { continue }
            let chunk = contributor.chunk
            let usesOriginalChunk =
                contributor.overlapStart == chunk.startOffset
                && contributor.duration == chunk.duration

            if usesOriginalChunk {
                splitChunks.append(chunk)
                sourceSpans.append(
                    MeetingAudioSourceSpan(
                        chunkURL: chunk.url,
                        source: chunk.source,
                        sourceURL: chunk.url,
                        sourceStartOffset: chunk.startOffset,
                        startOffset: chunk.startOffset,
                        duration: chunk.duration
                    )
                )
                continue
            }

            let outputURL = try writeAudioWindow(
                MeetingAudioChunk(
                    url: chunk.url,
                    source: chunk.source,
                    startOffset: contributor.overlapStart,
                    duration: contributor.duration
                ),
                sourceChunk: chunk,
                outputDirectory: outputDirectory
            )
            temporaryURLs.append(outputURL)
            splitChunks.append(
                MeetingAudioChunk(
                    url: outputURL,
                    source: chunk.source,
                    startOffset: contributor.overlapStart,
                    duration: contributor.duration
                )
            )
            sourceSpans.append(
                MeetingAudioSourceSpan(
                    chunkURL: outputURL,
                    source: chunk.source,
                    sourceURL: chunk.url,
                    sourceStartOffset: chunk.startOffset,
                    startOffset: contributor.overlapStart,
                    duration: contributor.duration
                )
            )
        }
    } catch {
        for url in temporaryURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        throw error
    }

    return MeetingAudioChunkingResult(chunks: splitChunks, temporaryURLs: temporaryURLs, sourceSpans: sourceSpans)
}

nonisolated private func mergedSource(for contributors: [MeetingAudioTimelineContributor]) -> MeetingSourceKind {
    contributors.contains { $0.chunk.source == .microphone } ? .microphone : (contributors.first?.chunk.source ?? .systemAudio)
}

nonisolated private func writeMixedAudioWindow(
    _ window: MeetingAudioTimelineWindow,
    outputDirectory: URL
) throws -> URL {
    guard
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )
    else {
        throw MeetingRecordingError.captureFailed("Meeting audio output format is unavailable.")
    }

    let frameCount = AVAudioFrameCount(max(1, (window.duration * outputFormat.sampleRate).rounded(.up)))
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount),
        let outputSamples = outputBuffer.floatChannelData?[0]
    else {
        throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
    }
    outputBuffer.frameLength = frameCount

    for frame in 0..<Int(frameCount) {
        outputSamples[frame] = 0
    }

    for contributor in window.contributors {
        let samples = try readMonoSamples(for: contributor, outputFormat: outputFormat)
        let destinationOffset = Int(((contributor.overlapStart - window.startOffset) * outputFormat.sampleRate).rounded(.down))
        guard destinationOffset < Int(frameCount) else { continue }

        let writableCount = min(samples.count, Int(frameCount) - destinationOffset)
        for sampleIndex in 0..<writableCount {
            let outputIndex = destinationOffset + sampleIndex
            outputSamples[outputIndex] = clippedSample(outputSamples[outputIndex] + samples[sampleIndex])
        }
    }

    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-meeting-merged-\(Int(window.startOffset * 1000))-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
    try outputFile.write(from: outputBuffer)
    return outputURL
}

nonisolated private func readMonoSamples(
    for contributor: MeetingAudioTimelineContributor,
    outputFormat: AVAudioFormat
) throws -> [Float] {
    let window = MeetingAudioChunk(
        url: contributor.chunk.url,
        source: contributor.chunk.source,
        startOffset: contributor.overlapStart,
        duration: contributor.duration
    )
    let buffer = try readAudioWindowBuffer(window, sourceChunk: contributor.chunk, outputFormat: outputFormat)
    guard let channelData = buffer.floatChannelData else {
        throw MeetingRecordingError.captureFailed("Meeting audio samples are unavailable.")
    }

    let frameLength = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard frameLength > 0, channelCount > 0 else { return [] }

    if channelCount == 1 {
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    var samples: [Float] = []
    samples.reserveCapacity(frameLength)
    for frame in 0..<frameLength {
        var mixedSample: Float = 0
        for channel in 0..<channelCount {
            mixedSample += channelData[channel][frame]
        }
        samples.append(mixedSample / Float(channelCount))
    }
    return samples
}

nonisolated private func readAudioWindowBuffer(
    _ window: MeetingAudioChunk,
    sourceChunk: MeetingAudioChunk,
    outputFormat: AVAudioFormat
) throws -> AVAudioPCMBuffer {
    let inputFile = try AVAudioFile(forReading: sourceChunk.url)
    let inputFormat = inputFile.processingFormat
    let sampleRate = inputFormat.sampleRate
    let sourceOffset = max(0, window.startOffset - sourceChunk.startOffset)
    let startFrame = min(
        inputFile.length,
        AVAudioFramePosition((sourceOffset * sampleRate).rounded(.down))
    )
    let requestedFrames = AVAudioFrameCount(max(1, (window.duration * sampleRate).rounded(.up)))
    let availableFrames = AVAudioFrameCount(max(0, inputFile.length - startFrame))
    let frameCount = min(requestedFrames, availableFrames)

    guard frameCount > 0,
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount)
    else {
        throw MeetingRecordingError.noCapturedAudio
    }

    inputFile.framePosition = startFrame
    try inputFile.read(into: inputBuffer, frameCount: frameCount)

    guard !inputFormat.matches(outputFormat) else {
        return inputBuffer
    }

    return try convertBuffer(inputBuffer, to: outputFormat)
}

nonisolated private func convertBuffer(
    _ inputBuffer: AVAudioPCMBuffer,
    to outputFormat: AVAudioFormat
) throws -> AVAudioPCMBuffer {
    guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
        throw MeetingRecordingError.captureFailed("Meeting audio converter is unavailable.")
    }
    guard
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: convertedFrameCapacity(
                inputFrames: inputBuffer.frameLength,
                inputSampleRate: inputBuffer.format.sampleRate,
                outputSampleRate: outputFormat.sampleRate
            )
        )
    else {
        throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
    }

    let inputProvider = MeetingAudioChunkConverterInputProvider(buffer: inputBuffer)
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
        inputProvider.next(inputStatus: inputStatus)
    }

    guard conversionError == nil, status == .haveData || status == .inputRanDry else {
        throw MeetingRecordingError.captureFailed("Meeting audio conversion failed.")
    }

    return outputBuffer
}

nonisolated private func convertedFrameCapacity(
    inputFrames: AVAudioFrameCount,
    inputSampleRate: Double,
    outputSampleRate: Double
) -> AVAudioFrameCount {
    guard inputSampleRate > 0, outputSampleRate > 0 else {
        return inputFrames
    }

    let ratio = outputSampleRate / inputSampleRate
    return AVAudioFrameCount((Double(inputFrames) * ratio).rounded(.up)) + 32
}

nonisolated private func clippedSample(_ sample: Float) -> Float {
    min(1, max(-1, sample))
}

private extension AVAudioFormat {
    nonisolated func matches(_ other: AVAudioFormat) -> Bool {
        commonFormat == other.commonFormat
            && sampleRate == other.sampleRate
            && channelCount == other.channelCount
            && isInterleaved == other.isInterleaved
    }
}

nonisolated private final class MeetingAudioChunkConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !didProvideInput else {
            inputStatus.pointee = .noDataNow
            return nil
        }

        didProvideInput = true
        inputStatus.pointee = .haveData
        return buffer
    }
}

nonisolated private func writeAudioWindow(
    _ window: MeetingAudioChunk,
    sourceChunk: MeetingAudioChunk,
    outputDirectory: URL
) throws -> URL {
    let inputFile = try AVAudioFile(forReading: sourceChunk.url)
    let format = inputFile.processingFormat
    let sampleRate = format.sampleRate
    let sourceOffset = max(0, window.startOffset - sourceChunk.startOffset)
    let startFrame = min(
        inputFile.length,
        AVAudioFramePosition((sourceOffset * sampleRate).rounded(.down))
    )
    let requestedFrames = AVAudioFrameCount(max(1, (window.duration * sampleRate).rounded(.up)))
    let availableFrames = AVAudioFrameCount(max(0, inputFile.length - startFrame))
    let frameCount = min(requestedFrames, availableFrames)

    guard frameCount > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    else {
        throw MeetingRecordingError.noCapturedAudio
    }

    inputFile.framePosition = startFrame
    try inputFile.read(into: buffer, frameCount: frameCount)

    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-meeting-chunk-\(sourceChunk.source.rawValue)-\(Int(window.startOffset * 1000))-\(UUID().uuidString)")
        .appendingPathExtension("caf")
    let outputFile = try AVAudioFile(forWriting: outputURL, settings: format.settings)
    try outputFile.write(from: buffer)
    return outputURL
}
