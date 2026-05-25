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
    private let audioFileIO: MeetingAudioFileIO

    init(
        outputDirectory: URL,
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO()
    ) {
        self.outputDirectory = outputDirectory
        self.audioFileIO = audioFileIO
    }

    func split(
        _ chunks: [MeetingAudioChunk],
        maximumDuration: TimeInterval,
        chunkDuration: TimeInterval
    ) async throws -> MeetingAudioChunkingResult {
        let outputDirectory = outputDirectory
        let audioFileIO = audioFileIO
        return try await Task.detached(priority: .userInitiated) {
            try splitChunks(
                chunks,
                maximumDuration: maximumDuration,
                chunkDuration: chunkDuration,
                outputDirectory: outputDirectory,
                fileManager: .default,
                audioFileIO: audioFileIO
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
    fileManager: FileManager,
    audioFileIO: MeetingAudioFileIO
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
                guard
                    let writtenWindow = try writeMixedAudioWindow(
                        window,
                        outputDirectory: outputDirectory,
                        audioFileIO: audioFileIO
                    )
                else {
                    continue
                }
                temporaryURLs.append(writtenWindow.url)
                splitChunks.append(
                    MeetingAudioChunk(
                        url: writtenWindow.url,
                        source: mergedSource(for: writtenWindow.contributors),
                        startOffset: window.startOffset,
                        duration: writtenWindow.duration
                    )
                )
                sourceSpans.append(
                    contentsOf: writtenWindow.contributors.map { contributor in
                        MeetingAudioSourceSpan(
                            chunkURL: writtenWindow.url,
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
                guard let readableDuration = try audioFileIO.readableDuration(for: chunk) else {
                    continue
                }
                let readableChunk = MeetingAudioChunk(
                    url: chunk.url,
                    source: chunk.source,
                    startOffset: chunk.startOffset,
                    duration: min(chunk.duration, readableDuration)
                )
                splitChunks.append(readableChunk)
                sourceSpans.append(
                    MeetingAudioSourceSpan(
                        chunkURL: chunk.url,
                        source: chunk.source,
                        sourceURL: chunk.url,
                        sourceStartOffset: chunk.startOffset,
                        startOffset: chunk.startOffset,
                        duration: readableChunk.duration
                    )
                )
                continue
            }

            let windowChunk = MeetingAudioChunk(
                url: chunk.url,
                source: chunk.source,
                startOffset: contributor.overlapStart,
                duration: contributor.duration
            )
            guard
                let writtenWindow = try writeAudioWindow(
                    windowChunk,
                    sourceChunk: chunk,
                    outputDirectory: outputDirectory,
                    audioFileIO: audioFileIO
                )
            else {
                continue
            }
            temporaryURLs.append(writtenWindow.url)
            splitChunks.append(
                MeetingAudioChunk(
                    url: writtenWindow.url,
                    source: chunk.source,
                    startOffset: contributor.overlapStart,
                    duration: writtenWindow.duration
                )
            )
            sourceSpans.append(
                MeetingAudioSourceSpan(
                    chunkURL: writtenWindow.url,
                    source: chunk.source,
                    sourceURL: chunk.url,
                    sourceStartOffset: chunk.startOffset,
                    startOffset: contributor.overlapStart,
                    duration: writtenWindow.duration
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

nonisolated private struct MeetingAudioWrittenWindow: Sendable {
    var url: URL
    var duration: TimeInterval
    var contributors: [MeetingAudioTimelineContributor]
}

nonisolated private struct MeetingAudioReadableContributor: Sendable {
    var contributor: MeetingAudioTimelineContributor
    var samples: [Float]
    var duration: TimeInterval
}

nonisolated private func mergedSource(for contributors: [MeetingAudioTimelineContributor]) -> MeetingSourceKind {
    contributors.contains { $0.chunk.source == .microphone } ? .microphone : (contributors.first?.chunk.source ?? .systemAudio)
}

nonisolated private func writeMixedAudioWindow(
    _ window: MeetingAudioTimelineWindow,
    outputDirectory: URL,
    audioFileIO: MeetingAudioFileIO
) throws -> MeetingAudioWrittenWindow? {
    let readableContributors = try window.contributors.compactMap { contributor in
        try readMonoSamples(for: contributor, audioFileIO: audioFileIO)
    }
    guard !readableContributors.isEmpty else { return nil }

    let sampleRate = audioFileIO.sampleRate
    let frameCount = max(
        1,
        readableContributors.map { readableContributor in
            let destinationOffset = Int(
                ((readableContributor.contributor.overlapStart - window.startOffset) * sampleRate).rounded(.down)
            )
            return destinationOffset + readableContributor.samples.count
        }.max() ?? 0
    )
    var outputSamples = Array(repeating: Float(0), count: frameCount)

    for readableContributor in readableContributors {
        let contributor = readableContributor.contributor
        let samples = readableContributor.samples
        let destinationOffset = Int(
            ((contributor.overlapStart - window.startOffset) * sampleRate).rounded(.down)
        )
        guard destinationOffset < frameCount else { continue }

        let writableCount = min(samples.count, frameCount - destinationOffset)
        for sampleIndex in 0..<writableCount {
            let outputIndex = destinationOffset + sampleIndex
            outputSamples[outputIndex] = clippedSample(outputSamples[outputIndex] + samples[sampleIndex])
        }
    }

    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-meeting-merged-\(Int(window.startOffset * 1000))-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    let duration = try audioFileIO.writeMonoSamples(outputSamples, to: outputURL)
    return MeetingAudioWrittenWindow(
        url: outputURL,
        duration: min(window.duration, duration),
        contributors: readableContributors.map { readableContributor in
            var contributor = readableContributor.contributor
            contributor.duration = min(contributor.duration, readableContributor.duration)
            return contributor
        }
    )
}

nonisolated private func readMonoSamples(
    for contributor: MeetingAudioTimelineContributor,
    audioFileIO: MeetingAudioFileIO
) throws -> MeetingAudioReadableContributor? {
    let window = MeetingAudioChunk(
        url: contributor.chunk.url,
        source: contributor.chunk.source,
        startOffset: contributor.overlapStart,
        duration: contributor.duration
    )
    guard let sampleWindow = try audioFileIO.readMonoSampleWindow(window, in: contributor.chunk) else { return nil }
    return MeetingAudioReadableContributor(
        contributor: contributor,
        samples: sampleWindow.samples,
        duration: sampleWindow.duration
    )
}

nonisolated private func clippedSample(_ sample: Float) -> Float {
    min(1, max(-1, sample))
}

nonisolated private func writeAudioWindow(
    _ window: MeetingAudioChunk,
    sourceChunk: MeetingAudioChunk,
    outputDirectory: URL,
    audioFileIO: MeetingAudioFileIO
) throws -> MeetingAudioWrittenWindow? {
    guard let sampleWindow = try audioFileIO.readMonoSampleWindow(window, in: sourceChunk) else { return nil }

    let outputURL =
        outputDirectory
        .appendingPathComponent(
            "voicepen-meeting-chunk-\(sourceChunk.source.rawValue)-\(Int(window.startOffset * 1000))-\(UUID().uuidString)"
        )
        .appendingPathExtension("caf")
    let outputDuration = try audioFileIO.writeMonoSamples(sampleWindow.samples, to: outputURL)
    return MeetingAudioWrittenWindow(
        url: outputURL,
        duration: min(window.duration, outputDuration, sampleWindow.duration),
        contributors: []
    )
}
