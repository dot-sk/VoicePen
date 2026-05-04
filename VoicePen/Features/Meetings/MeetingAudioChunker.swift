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
        return MeetingAudioChunkingResult(chunks: windows, temporaryURLs: [])
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

    do {
        for chunk in chunks {
            let windows = MeetingAudioChunkWindowPlanner.windows(
                for: chunk,
                maximumDuration: maximumDuration,
                chunkDuration: chunkDuration
            )

            if windows.count == 1, windows[0] == chunk {
                splitChunks.append(chunk)
                continue
            }

            for window in windows {
                let outputURL = try writeAudioWindow(
                    window,
                    sourceChunk: chunk,
                    outputDirectory: outputDirectory
                )
                temporaryURLs.append(outputURL)
                splitChunks.append(
                    MeetingAudioChunk(
                        url: outputURL,
                        source: window.source,
                        startOffset: window.startOffset,
                        duration: window.duration
                    )
                )
            }
        }
    } catch {
        for url in temporaryURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        throw error
    }

    return MeetingAudioChunkingResult(chunks: splitChunks, temporaryURLs: temporaryURLs)
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
