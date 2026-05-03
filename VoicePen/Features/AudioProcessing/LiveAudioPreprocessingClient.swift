import AVFoundation
import Foundation

final class LiveAudioPreprocessingClient: AudioPreprocessingClient {
    private let outputDirectory: URL
    private let fileManager: FileManager

    init(outputDirectory: URL, fileManager: FileManager = .default) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
    }

    func preprocess(audioURL: URL, mode: SpeechPreprocessingMode) async throws -> URL {
        let outputDirectory = outputDirectory
        let rate = mode.speedRate
        return try await Task.detached(priority: .userInitiated) {
            let trimmedURL = try trimSilence(
                inputURL: audioURL,
                outputDirectory: outputDirectory,
                fileManager: .default
            )
            let sourceURL = trimmedURL ?? audioURL
            guard mode != .off else { return sourceURL }

            return try slowDownAudio(
                inputURL: sourceURL,
                outputDirectory: outputDirectory,
                rate: rate,
                fileManager: .default
            )
        }.value
    }
}

nonisolated private func trimSilence(
    inputURL: URL,
    outputDirectory: URL,
    fileManager: FileManager
) throws -> URL? {
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

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

    let samples = try monoSamples(from: buffer, frameLength: frameLength)
    guard
        AudioSilenceTrimmer.containsSpeech(
            samples: samples,
            sampleRate: inputFormat.sampleRate,
            minimumSpeechDuration: VoicePenConfig.minimumSpeechSignalDuration
        )
    else {
        throw AudioPreprocessingError.noSpeechDetected
    }

    guard
        let trimRange = AudioSilenceTrimmer.trimRange(
            samples: samples,
            sampleRate: inputFormat.sampleRate,
            minimumSpeechDuration: VoicePenConfig.minimumSpeechSignalDuration
        )
    else {
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
    let outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
    try outputFile.write(from: outputBuffer)
    return outputURL
}

nonisolated private func slowDownAudio(
    inputURL: URL,
    outputDirectory: URL,
    rate: Double,
    fileManager: FileManager
) throws -> URL {
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let inputFile = try AVAudioFile(forReading: inputURL)
    let inputFormat = inputFile.processingFormat
    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-processed-\(UUID().uuidString)")
        .appendingPathExtension("wav")

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let timePitch = AVAudioUnitTimePitch()
    timePitch.rate = Float(rate)

    engine.attach(player)
    engine.attach(timePitch)
    engine.connect(player, to: timePitch, format: inputFormat)
    engine.connect(timePitch, to: engine.mainMixerNode, format: inputFormat)

    let maximumFrameCount: AVAudioFrameCount = 4096
    try engine.enableManualRenderingMode(
        .offline,
        format: inputFormat,
        maximumFrameCount: maximumFrameCount
    )

    let outputFile = try AVAudioFile(
        forWriting: outputURL,
        settings: inputFormat.settings
    )

    guard
        let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        )
    else {
        throw AudioPreprocessingError.couldNotCreateRenderBuffer
    }

    try engine.start()
    player.scheduleFile(inputFile, at: nil)
    player.play()

    let expectedFrames = AVAudioFramePosition(
        (Double(inputFile.length) / max(rate, 0.01)) + inputFormat.sampleRate
    )

    while engine.manualRenderingSampleTime < expectedFrames {
        let frameCount = min(
            buffer.frameCapacity,
            AVAudioFrameCount(expectedFrames - engine.manualRenderingSampleTime)
        )

        switch try engine.renderOffline(frameCount, to: buffer) {
        case .success:
            guard buffer.frameLength > 0 else { continue }
            try outputFile.write(from: buffer)
        case .insufficientDataFromInputNode:
            continue
        case .cannotDoInCurrentContext:
            continue
        case .error:
            throw AudioPreprocessingError.renderFailed
        @unknown default:
            throw AudioPreprocessingError.renderFailed
        }
    }

    player.stop()
    engine.stop()
    engine.disableManualRenderingMode()

    return outputURL
}

nonisolated private func monoSamples(from buffer: AVAudioPCMBuffer, frameLength: Int) throws -> [Float] {
    guard let channelData = buffer.floatChannelData else {
        throw AudioPreprocessingError.renderFailed
    }

    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return [] }

    if channelCount == 1 {
        return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
    }

    var samples = [Float]()
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
        for frameOffset in 0..<range.count {
            destinationData[channel][frameOffset] = sourceData[channel][range.lowerBound + frameOffset]
        }
    }
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
