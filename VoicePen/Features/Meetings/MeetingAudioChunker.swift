@preconcurrency import AVFoundation
import Foundation

protocol MeetingAudioChunker: AnyObject {
    func master(
        _ chunks: [MeetingAudioChunk],
        duration: TimeInterval
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

final class AVFoundationMeetingAudioChunker: MeetingAudioChunker {
    private let outputDirectory: URL
    private let audioFileIO: MeetingAudioFileIO
    private let microphoneDenoiser: AudioDenoising?

    init(
        outputDirectory: URL,
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO(),
        microphoneDenoiser: AudioDenoising? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.audioFileIO = audioFileIO
        self.microphoneDenoiser = microphoneDenoiser
    }

    func master(
        _ chunks: [MeetingAudioChunk],
        duration: TimeInterval
    ) async throws -> MeetingAudioChunkingResult {
        let outputDirectory = outputDirectory
        let audioFileIO = audioFileIO
        let microphoneDenoiser = microphoneDenoiser
        return try await Task.detached(priority: .userInitiated) {
            try masterChunks(
                chunks,
                duration: duration,
                outputDirectory: outputDirectory,
                fileManager: .default,
                audioFileIO: audioFileIO,
                microphoneDenoiser: microphoneDenoiser
            )
        }.value
    }
}

final class PassthroughMeetingAudioChunker: MeetingAudioChunker {
    func master(
        _ chunks: [MeetingAudioChunk],
        duration: TimeInterval
    ) async throws -> MeetingAudioChunkingResult {
        guard
            let first = chunks.sorted(by: { lhs, rhs in
                if lhs.startOffset != rhs.startOffset {
                    return lhs.startOffset < rhs.startOffset
                }
                return lhs.source == .microphone && rhs.source == .systemAudio
            }).first
        else {
            return MeetingAudioChunkingResult(chunks: [], temporaryURLs: [], sourceSpans: [])
        }
        let master = MeetingAudioChunk(
            url: first.url,
            source: first.source,
            startOffset: 0,
            duration: duration
        )
        return MeetingAudioChunkingResult(
            chunks: [master],
            temporaryURLs: [],
            sourceSpans: chunks.map { chunk in
                MeetingAudioSourceSpan(
                    chunkURL: master.url,
                    source: chunk.source,
                    sourceURL: chunk.url,
                    sourceStartOffset: chunk.startOffset,
                    startOffset: chunk.startOffset,
                    duration: chunk.duration
                )
            }
        )
    }
}

nonisolated private func masterChunks(
    _ chunks: [MeetingAudioChunk],
    duration: TimeInterval,
    outputDirectory: URL,
    fileManager: FileManager,
    audioFileIO: MeetingAudioFileIO,
    microphoneDenoiser: AudioDenoising?
) throws -> MeetingAudioChunkingResult {
    guard duration > 0 else {
        return MeetingAudioChunkingResult(chunks: [], temporaryURLs: [], sourceSpans: [])
    }
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let originalReadableChunks = try chunks.compactMap { chunk -> MeetingAudioChunk? in
        guard let readableDuration = try audioFileIO.readableDuration(for: chunk), readableDuration > 0 else {
            return nil
        }
        return MeetingAudioChunk(
            url: chunk.url,
            source: chunk.source,
            startOffset: chunk.startOffset,
            duration: min(chunk.duration, readableDuration)
        )
    }
    guard !originalReadableChunks.isEmpty else {
        return MeetingAudioChunkingResult(chunks: [], temporaryURLs: [], sourceSpans: [])
    }

    let denoisedSources = prepareMicrophoneSources(
        originalReadableChunks,
        outputDirectory: outputDirectory,
        fileManager: fileManager,
        audioFileIO: audioFileIO,
        microphoneDenoiser: microphoneDenoiser
    )
    let readableChunks = denoisedSources.chunks
    var keepDenoisedSources = false
    defer {
        if !keepDenoisedSources {
            for url in denoisedSources.temporaryURLs {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    let sourceGains = try MeetingSourceLevelNormalizer.gains(
        for: readableChunks,
        audioFileIO: audioFileIO
    )
    let masterScale = try consistentMasterScale(
        chunks: readableChunks,
        duration: duration,
        gains: sourceGains,
        audioFileIO: audioFileIO
    )
    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-meeting-master-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    let processingFormat = try audioFileIO.processingFormat()
    let writer = try ExtendedAudioFileWriter(
        outputURL: outputURL,
        clientFormat: processingFormat,
        fileFormat: audioFileIO.storageFormat(),
        writeMode: .synchronous
    )

    do {
        var blockStart: TimeInterval = 0
        while blockStart < duration {
            let blockDuration = min(MeetingSourceLevelNormalizer.blockDuration, duration - blockStart)
            var samples = try masteredSamples(
                chunks: readableChunks,
                startOffset: blockStart,
                duration: blockDuration,
                gains: sourceGains,
                audioFileIO: audioFileIO
            )
            if !samples.isEmpty {
                applyScale(masterScale, to: &samples)
                try writer.write(try pcmBuffer(samples: samples, format: processingFormat))
            }
            blockStart += blockDuration
        }
        try writer.close()
    } catch {
        try? writer.close()
        try? fileManager.removeItem(at: outputURL)
        throw error
    }

    let probe = MeetingAudioChunk(url: outputURL, source: .microphone, startOffset: 0, duration: duration)
    guard let masteredDuration = try audioFileIO.readableDuration(for: probe), masteredDuration > 0 else {
        try? fileManager.removeItem(at: outputURL)
        return MeetingAudioChunkingResult(chunks: [], temporaryURLs: [], sourceSpans: [])
    }
    let master = MeetingAudioChunk(
        url: outputURL,
        source: readableChunks.contains { $0.source == .microphone } ? .microphone : .systemAudio,
        startOffset: 0,
        duration: min(duration, masteredDuration)
    )
    let sourceSpans = originalReadableChunks.map { chunk in
        MeetingAudioSourceSpan(
            chunkURL: outputURL,
            source: chunk.source,
            sourceURL: chunk.url,
            sourceStartOffset: chunk.startOffset,
            startOffset: chunk.startOffset,
            duration: chunk.duration
        )
    }
    keepDenoisedSources = true
    return MeetingAudioChunkingResult(
        chunks: [master],
        temporaryURLs: denoisedSources.temporaryURLs + [outputURL],
        sourceSpans: sourceSpans
    )
}

nonisolated private struct MeetingPreparedAudioSources {
    var chunks: [MeetingAudioChunk]
    var temporaryURLs: [URL]
}

nonisolated private func prepareMicrophoneSources(
    _ chunks: [MeetingAudioChunk],
    outputDirectory: URL,
    fileManager: FileManager,
    audioFileIO: MeetingAudioFileIO,
    microphoneDenoiser: AudioDenoising?
) -> MeetingPreparedAudioSources {
    guard let microphoneDenoiser else {
        return MeetingPreparedAudioSources(chunks: chunks, temporaryURLs: [])
    }

    var preparedChunks: [MeetingAudioChunk] = []
    var temporaryURLs: [URL] = []
    for chunk in chunks {
        let prepared = prepareMicrophoneSource(
            chunk,
            outputDirectory: outputDirectory,
            fileManager: fileManager,
            audioFileIO: audioFileIO,
            microphoneDenoiser: microphoneDenoiser
        )
        preparedChunks.append(prepared.chunk)
        if let temporaryURL = prepared.temporaryURL {
            temporaryURLs.append(temporaryURL)
        }
    }
    return MeetingPreparedAudioSources(chunks: preparedChunks, temporaryURLs: temporaryURLs)
}

nonisolated private func prepareMicrophoneSource(
    _ chunk: MeetingAudioChunk,
    outputDirectory: URL,
    fileManager: FileManager,
    audioFileIO: MeetingAudioFileIO,
    microphoneDenoiser: AudioDenoising
) -> (chunk: MeetingAudioChunk, temporaryURL: URL?) {
    guard chunk.source == .microphone else { return (chunk, nil) }

    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-meeting-denoised-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    var writer: ExtendedAudioFileWriter?
    do {
        let processingFormat = try audioFileIO.processingFormat()
        writer = try ExtendedAudioFileWriter(
            outputURL: outputURL,
            clientFormat: processingFormat,
            fileFormat: audioFileIO.storageFormat(),
            writeMode: .synchronous
        )

        let blockDuration: TimeInterval = 60
        let endOffset = chunk.startOffset + chunk.duration
        var blockStart = chunk.startOffset
        var writtenSampleCount = 0
        while blockStart < endOffset {
            let requestedDuration = min(blockDuration, endOffset - blockStart)
            let window = MeetingAudioChunk(
                url: chunk.url,
                source: chunk.source,
                startOffset: blockStart,
                duration: requestedDuration
            )
            guard let sampleWindow = try audioFileIO.readMonoSampleWindow(window, in: chunk),
                !sampleWindow.samples.isEmpty
            else {
                break
            }
            let denoised = try microphoneDenoiser.process(
                samples: sampleWindow.samples,
                sampleRate: Int(audioFileIO.sampleRate.rounded())
            )
            guard denoised.count == sampleWindow.samples.count else {
                throw MeetingRecordingError.captureFailed(
                    "Meeting microphone noise suppression changed the audio duration."
                )
            }
            try writer?.write(try pcmBuffer(samples: denoised, format: processingFormat))
            writtenSampleCount += denoised.count
            blockStart += sampleWindow.duration
        }

        guard writtenSampleCount > 0 else {
            throw MeetingRecordingError.noCapturedAudio
        }
        try writer?.close()
        writer = nil
        let writtenDuration = Double(writtenSampleCount) / audioFileIO.sampleRate
        return (
            MeetingAudioChunk(
                url: outputURL,
                source: chunk.source,
                startOffset: chunk.startOffset,
                duration: min(chunk.duration, writtenDuration)
            ),
            outputURL
        )
    } catch {
        try? writer?.close()
        try? fileManager.removeItem(at: outputURL)
        AppLogger.info("Meeting microphone noise suppression skipped: \(error.localizedDescription)")
        return (chunk, nil)
    }
}

nonisolated private enum MeetingSourceLevelNormalizer {
    static let blockDuration: TimeInterval = 30
    private static let analysisFrameDuration: TimeInterval = 0.1
    private static let targetRMS = pow(10, -20.0 / 20.0)
    private static let minimumGain = pow(10, -12.0 / 20.0)
    private static let maximumGain = pow(10, 18.0 / 20.0)

    static func gains(
        for chunks: [MeetingAudioChunk],
        audioFileIO: MeetingAudioFileIO
    ) throws -> [MeetingSourceKind: Float] {
        var levelsBySource: [MeetingSourceKind: [Double]] = [:]
        let frameCount = max(1, Int((analysisFrameDuration * audioFileIO.sampleRate).rounded()))

        for chunk in chunks {
            var offset = chunk.startOffset
            let endOffset = chunk.startOffset + chunk.duration
            while offset < endOffset {
                let duration = min(blockDuration, endOffset - offset)
                let window = MeetingAudioChunk(
                    url: chunk.url,
                    source: chunk.source,
                    startOffset: offset,
                    duration: duration
                )
                if let sampleWindow = try audioFileIO.readMonoSampleWindow(window, in: chunk) {
                    var frameStart = 0
                    while frameStart < sampleWindow.samples.count {
                        let frameEnd = min(sampleWindow.samples.count, frameStart + frameCount)
                        let frame = sampleWindow.samples[frameStart..<frameEnd]
                        let meanSquare =
                            frame.reduce(0.0) { partial, sample in
                                partial + Double(sample * sample)
                            } / Double(frame.count)
                        levelsBySource[chunk.source, default: []].append(sqrt(meanSquare))
                        frameStart = frameEnd
                    }
                }
                offset += duration
            }
        }

        return Dictionary(
            uniqueKeysWithValues: Set(chunks.map(\.source)).map { source in
                let usefulLevels = (levelsBySource[source] ?? [])
                    .filter { $0 > 0.000_1 }
                    .sorted()
                guard !usefulLevels.isEmpty else { return (source, Float(1)) }
                let index = min(usefulLevels.count - 1, Int(Double(usefulLevels.count - 1) * 0.9))
                let referenceRMS = usefulLevels[index]
                let gain = min(maximumGain, max(minimumGain, targetRMS / referenceRMS))
                return (source, Float(gain))
            })
    }
}

nonisolated private func masteredSamples(
    chunks: [MeetingAudioChunk],
    startOffset: TimeInterval,
    duration: TimeInterval,
    gains: [MeetingSourceKind: Float],
    audioFileIO: MeetingAudioFileIO
) throws -> [Float] {
    let frameCount = max(1, Int((duration * audioFileIO.sampleRate).rounded()))
    var output = [Float](repeating: 0, count: frameCount)
    let blockEnd = startOffset + duration

    for chunk in chunks {
        let overlapStart = max(startOffset, chunk.startOffset)
        let overlapEnd = min(blockEnd, chunk.startOffset + chunk.duration)
        guard overlapEnd > overlapStart else { continue }
        let window = MeetingAudioChunk(
            url: chunk.url,
            source: chunk.source,
            startOffset: overlapStart,
            duration: overlapEnd - overlapStart
        )
        guard let sampleWindow = try audioFileIO.readMonoSampleWindow(window, in: chunk) else { continue }
        let destinationOffset = max(0, Int(((overlapStart - startOffset) * audioFileIO.sampleRate).rounded()))
        let count = min(sampleWindow.samples.count, output.count - destinationOffset)
        guard count > 0 else { continue }
        let gain = gains[chunk.source] ?? 1
        for index in 0..<count {
            output[destinationOffset + index] += sampleWindow.samples[index] * gain
        }
    }

    return output
}

nonisolated private func consistentMasterScale(
    chunks: [MeetingAudioChunk],
    duration: TimeInterval,
    gains: [MeetingSourceKind: Float],
    audioFileIO: MeetingAudioFileIO
) throws -> Float {
    let headroom: Float = 0.8
    var peak: Float = 0
    var blockStart: TimeInterval = 0
    while blockStart < duration {
        let blockDuration = min(MeetingSourceLevelNormalizer.blockDuration, duration - blockStart)
        let samples = try masteredSamples(
            chunks: chunks,
            startOffset: blockStart,
            duration: blockDuration,
            gains: gains,
            audioFileIO: audioFileIO
        )
        peak = samples.reduce(peak) { max($0, abs($1)) }
        blockStart += blockDuration
    }

    let scaledPeak = peak * headroom
    return scaledPeak > 0.95 ? headroom * 0.95 / scaledPeak : headroom
}

nonisolated private func applyScale(_ scale: Float, to samples: inout [Float]) {
    for index in samples.indices {
        samples[index] *= scale
    }
}

nonisolated private func pcmBuffer(samples: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    guard
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData?[0]
    else {
        throw MeetingRecordingError.captureFailed("Meeting master buffer is unavailable.")
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { source in
        guard let baseAddress = source.baseAddress else { return }
        channel.update(from: baseAddress, count: samples.count)
    }
    return buffer
}
