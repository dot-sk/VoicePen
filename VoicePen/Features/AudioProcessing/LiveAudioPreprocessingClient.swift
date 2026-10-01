import AVFoundation
import Foundation

final class LiveAudioPreprocessingClient: AudioPreprocessingClient {
    private let outputDirectory: URL
    private let audioDenoiserProvider: (() -> AudioDenoising?)?
    private let clarityProcessor: WhisperOptimalAudioProcessor?

    init(
        outputDirectory: URL,
        audioDenoiser: AudioDenoising? = nil,
        audioDenoiserProvider: (() -> AudioDenoising?)? = nil,
        clarityProcessor: WhisperOptimalAudioProcessor? = nil
    ) {
        self.outputDirectory = outputDirectory
        if let audioDenoiserProvider {
            self.audioDenoiserProvider = audioDenoiserProvider
        } else if let audioDenoiser {
            self.audioDenoiserProvider = { audioDenoiser }
        } else {
            self.audioDenoiserProvider = nil
        }
        self.clarityProcessor = clarityProcessor
    }

    func preprocess(audioURL: URL) async throws -> URL {
        let outputDirectory = outputDirectory
        let audioDenoiser = audioDenoiserProvider?()
        let clarityProcessor = clarityProcessor
        return try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            return try preprocessAudio(
                inputURL: audioURL,
                outputDirectory: outputDirectory,
                audioDenoiser: audioDenoiser,
                clarityProcessor: clarityProcessor
            )
        }.value
    }
}

nonisolated private func preprocessAudio(
    inputURL: URL,
    outputDirectory: URL,
    audioDenoiser: AudioDenoising?,
    clarityProcessor: WhisperOptimalAudioProcessor?
) throws -> URL {
    let totalStart = DispatchTime.now().uptimeNanoseconds

    let readStart = DispatchTime.now().uptimeNanoseconds
    let input = try MonoPCM.read(from: inputURL)
    let readDuration = elapsedTime(since: readStart)

    let denoiseStart = DispatchTime.now().uptimeNanoseconds
    var samples = input.samples
    var didDenoise = false

    if let audioDenoiser {
        do {
            samples = try audioDenoiser.process(
                samples: samples,
                sampleRate: Int(input.sampleRate.rounded())
            )
            didDenoise = true
        } catch {
            AppLogger.info(
                "Microphone noise suppression skipped: \(error.localizedDescription)"
            )
            samples = input.samples
        }
    }
    let denoiseDuration = elapsedTime(since: denoiseStart)

    let clarityStart = DispatchTime.now().uptimeNanoseconds
    var didClarity = false
    if let clarityProcessor {
        samples = clarityProcessor.process(
            samples: samples,
            sampleRate: input.sampleRate
        )
        didClarity = true
    }
    let clarityDuration = elapsedTime(since: clarityStart)

    let silenceStart = DispatchTime.now().uptimeNanoseconds
    guard
        let analysis = AudioSilenceTrimmer.analyze(
            samples: samples,
            sampleRate: input.sampleRate,
            minimumSpeechDuration: VoicePenConfig.minimumSpeechSignalDuration
        )
    else {
        throw AudioPreprocessingError.noSpeechDetected
    }
    let trimRange = analysis.trimRange(
        sampleCount: samples.count,
        sampleRate: input.sampleRate
    )
    let silenceDuration = elapsedTime(since: silenceStart)

    if !didDenoise && !didClarity && trimRange == nil {
        return inputURL
    }

    let outputName: String
    if trimRange != nil {
        outputName = "voicepen-trimmed"
    } else if didDenoise {
        outputName = "voicepen-denoised"
    } else {
        outputName = "voicepen-processed"
    }

    let outputURL =
        outputDirectory
        .appendingPathComponent("\(outputName)-\(UUID().uuidString)")
        .appendingPathExtension("wav")
    let writeStart = DispatchTime.now().uptimeNanoseconds
    let resultURL = try createTemporaryAudioFile(at: outputURL) {
        let output = MonoPCM(samples: samples, sampleRate: input.sampleRate)
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
                "Audio preprocessing timings: read=%.3fs, denoise=%.3fs, clarity=%.3fs, silence=%.3fs, write=%.3fs, total=%.3fs",
            readDuration,
            denoiseDuration,
            clarityDuration,
            silenceDuration,
            writeDuration,
            elapsedTime(since: totalStart)
        )
    )
    return resultURL
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
