import AVFoundation
import Foundation

final class LiveAudioPreprocessingClient: AudioPreprocessingClient {
    private let outputDirectory: URL
    private let audioDenoiser: AudioDenoising?

    init(
        outputDirectory: URL,
        audioDenoiser: AudioDenoising? = nil
    ) {
        self.outputDirectory = outputDirectory
        self.audioDenoiser = audioDenoiser
    }

    func preprocess(audioURL: URL) async throws -> URL {
        let outputDirectory = outputDirectory
        let audioDenoiser = audioDenoiser
        return try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            if let audioDenoiser {
                return try preprocessWithDenoising(
                    inputURL: audioURL,
                    outputDirectory: outputDirectory,
                    audioDenoiser: audioDenoiser
                )
            }

            let trimmedURL = try trimSilence(
                inputURL: audioURL,
                outputDirectory: outputDirectory
            )
            return trimmedURL ?? audioURL
        }.value
    }
}

nonisolated private func preprocessWithDenoising(
    inputURL: URL,
    outputDirectory: URL,
    audioDenoiser: AudioDenoising
) throws -> URL {
    let totalStart = DispatchTime.now().uptimeNanoseconds

    let readStart = DispatchTime.now().uptimeNanoseconds
    let input = try MonoPCM.read(from: inputURL)
    let readDuration = elapsedTime(since: readStart)

    let denoiseStart = DispatchTime.now().uptimeNanoseconds
    let denoised: [Float]
    do {
        denoised = try audioDenoiser.process(
            samples: input.samples,
            sampleRate: Int(input.sampleRate.rounded())
        )
    } catch {
        AppLogger.info(
            "Microphone noise suppression skipped: \(error.localizedDescription)"
        )
        return try trimSilence(
            inputURL: inputURL,
            outputDirectory: outputDirectory
        ) ?? inputURL
    }
    let denoiseDuration = elapsedTime(since: denoiseStart)

    let silenceStart = DispatchTime.now().uptimeNanoseconds
    guard
        let analysis = AudioSilenceTrimmer.analyze(
            samples: denoised,
            sampleRate: input.sampleRate,
            minimumSpeechDuration: VoicePenConfig.minimumSpeechSignalDuration
        )
    else {
        throw AudioPreprocessingError.noSpeechDetected
    }
    let trimRange = analysis.trimRange(
        sampleCount: denoised.count,
        sampleRate: input.sampleRate
    )
    let silenceDuration = elapsedTime(since: silenceStart)

    let outputName = trimRange == nil ? "voicepen-denoised" : "voicepen-trimmed"
    let outputURL =
        outputDirectory
        .appendingPathComponent("\(outputName)-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    let writeStart = DispatchTime.now().uptimeNanoseconds
    let resultURL = try createTemporaryAudioFile(at: outputURL) {
        let output = MonoPCM(samples: denoised, sampleRate: input.sampleRate)
        if let trimRange {
            try output.write(to: outputURL, sampleRange: trimRange)
        } else {
            try output.write(to: outputURL)
        }
    }
    let writeDuration = elapsedTime(since: writeStart)

    AppLogger.info(
        String(
            format:
                "Audio preprocessing timings: read=%.3fs, denoise=%.3fs, silence=%.3fs, write=%.3fs, total=%.3fs",
            readDuration,
            denoiseDuration,
            silenceDuration,
            writeDuration,
            elapsedTime(since: totalStart)
        )
    )
    return resultURL
}

nonisolated private func trimSilence(
    inputURL: URL,
    outputDirectory: URL
) throws -> URL? {
    let inputFile = try AVAudioFile(forReading: inputURL)
    let inputFormat = inputFile.processingFormat
    guard
        let buffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(inputFile.length)
        )
    else {
        throw AudioPreprocessingError.couldNotCreateRenderBuffer
    }

    try inputFile.read(into: buffer)
    let frameLength = Int(buffer.frameLength)
    guard frameLength > 0 else { return nil }

    let samples: [Float]
    do {
        samples = try MonoPCM(buffer: buffer).samples
    } catch {
        throw AudioPreprocessingError.renderFailed
    }
    guard
        let analysis = AudioSilenceTrimmer.analyze(
            samples: samples,
            sampleRate: inputFormat.sampleRate,
            minimumSpeechDuration: VoicePenConfig.minimumSpeechSignalDuration
        )
    else {
        throw AudioPreprocessingError.noSpeechDetected
    }

    guard let trimRange = analysis.trimRange(sampleCount: samples.count, sampleRate: inputFormat.sampleRate) else {
        return nil
    }

    guard
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(trimRange.count)
        )
    else {
        throw AudioPreprocessingError.couldNotCreateRenderBuffer
    }
    outputBuffer.frameLength = AVAudioFrameCount(trimRange.count)

    try copyFrames(
        from: buffer,
        to: outputBuffer,
        range: trimRange,
        channelCount: Int(inputFormat.channelCount)
    )

    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-trimmed-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    return try createTemporaryAudioFile(at: outputURL) {
        let outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
        try outputFile.write(from: outputBuffer)
    }
}

nonisolated private func copyFrames(
    from source: AVAudioPCMBuffer,
    to destination: AVAudioPCMBuffer,
    range: Range<Int>,
    channelCount: Int
) throws {
    guard let sourceData = source.floatChannelData,
        let destinationData = destination.floatChannelData
    else {
        throw AudioPreprocessingError.renderFailed
    }

    for channel in 0..<channelCount {
        memcpy(
            destinationData[channel],
            sourceData[channel].advanced(by: range.lowerBound),
            range.count * MemoryLayout<Float>.stride
        )
    }
}

nonisolated private func createTemporaryAudioFile(
    at url: URL,
    operation: () throws -> Void
) throws -> URL {
    do {
        try operation()
        return url
    } catch {
        try? FileManager.default.removeItem(at: url)
        throw error
    }
}

nonisolated private func elapsedTime(since start: UInt64) -> TimeInterval {
    TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
}

enum AudioPreprocessingError: LocalizedError, Equatable {
    case couldNotCreateRenderBuffer
    case renderFailed
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .couldNotCreateRenderBuffer:
            return "VoicePen could not create an audio preprocessing buffer."
        case .renderFailed:
            return "VoicePen could not preprocess the recording."
        case .noSpeechDetected:
            return "VoicePen did not detect speech in the recording."
        }
    }
}
