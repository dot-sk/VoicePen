import AVFoundation
import AudioToolbox
import Foundation

protocol VoiceLevelingProcessor: AnyObject {
    func process(audioURL: URL) async throws -> URL
}

final class PassthroughVoiceLevelingProcessor: VoiceLevelingProcessor {
    func process(audioURL: URL) async throws -> URL {
        audioURL
    }
}

final class SystemVoiceLevelingProcessor: VoiceLevelingProcessor {
    private let outputDirectory: URL

    init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    func process(audioURL: URL) async throws -> URL {
        let outputDirectory = outputDirectory
        return try await Task.detached(priority: .userInitiated) {
            try renderLeveledAudio(
                inputURL: audioURL,
                outputDirectory: outputDirectory,
                fileManager: .default
            )
        }.value
    }
}

nonisolated private func renderLeveledAudio(
    inputURL: URL,
    outputDirectory: URL,
    fileManager: FileManager
) throws -> URL {
    try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    let inputFile = try AVAudioFile(forReading: inputURL)
    let inputFormat = inputFile.processingFormat
    let outputURL =
        outputDirectory
        .appendingPathComponent("voicepen-leveled-\(UUID().uuidString)")
        .appendingPathExtension("wav")

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let dynamicsProcessor = makeSystemEffect(subtype: kAudioUnitSubType_DynamicsProcessor)
    let peakLimiter = makeSystemEffect(subtype: kAudioUnitSubType_PeakLimiter)

    configureDynamicsProcessor(dynamicsProcessor)
    configurePeakLimiter(peakLimiter)

    engine.attach(player)
    engine.attach(dynamicsProcessor)
    engine.attach(peakLimiter)
    engine.connect(player, to: dynamicsProcessor, format: inputFormat)
    engine.connect(dynamicsProcessor, to: peakLimiter, format: inputFormat)
    engine.connect(peakLimiter, to: engine.mainMixerNode, format: inputFormat)

    let maximumFrameCount: AVAudioFrameCount = 4096
    try engine.enableManualRenderingMode(
        .offline,
        format: inputFormat,
        maximumFrameCount: maximumFrameCount
    )

    let outputFile = try AVAudioFile(forWriting: outputURL, settings: inputFormat.settings)
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

    let expectedFrames = inputFile.length
    while engine.manualRenderingSampleTime < expectedFrames {
        let remainingFrames = expectedFrames - engine.manualRenderingSampleTime
        let frameCount = min(buffer.frameCapacity, AVAudioFrameCount(remainingFrames))

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

nonisolated private func makeSystemEffect(subtype: OSType) -> AVAudioUnitEffect {
    let description = AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: subtype,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )

    return AVAudioUnitEffect(audioComponentDescription: description)
}

nonisolated private func configureDynamicsProcessor(_ effect: AVAudioUnitEffect) {
    setParameter(kDynamicsProcessorParam_Threshold, to: -24, on: effect)
    setParameter(kDynamicsProcessorParam_HeadRoom, to: 6, on: effect)
    setParameter(kDynamicsProcessorParam_ExpansionRatio, to: 2, on: effect)
    setParameter(kDynamicsProcessorParam_ExpansionThreshold, to: -50, on: effect)
    setParameter(kDynamicsProcessorParam_AttackTime, to: 0.005, on: effect)
    setParameter(kDynamicsProcessorParam_ReleaseTime, to: 0.25, on: effect)
    setParameter(kDynamicsProcessorParam_OverallGain, to: 6, on: effect)
}

nonisolated private func configurePeakLimiter(_ effect: AVAudioUnitEffect) {
    setParameter(kLimiterParam_AttackTime, to: 0.001, on: effect)
    setParameter(kLimiterParam_DecayTime, to: 0.08, on: effect)
    setParameter(kLimiterParam_PreGain, to: 0, on: effect)
}

nonisolated private func setParameter(_ address: AudioUnitParameterID, to value: AUValue, on effect: AVAudioUnitEffect) {
    effect.auAudioUnit.parameterTree?
        .parameter(withAddress: AUParameterAddress(address))?
        .value = value
}
