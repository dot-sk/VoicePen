@preconcurrency import AVFoundation
import Foundation

nonisolated enum ActiveChannelMonoMixer {
    private static let minimumActiveChannelRMS: Float = 0.0005
    private static let relativeActiveChannelRMS: Float = 0.15

    static func makeFloatFormat(
        sampleRate: Double,
        channelCount: AVAudioChannelCount
    ) -> AVAudioFormat? {
        guard sampleRate > 0, channelCount > 0 else { return nil }

        if let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) {
            return format
        }

        let discreteLayoutTag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder | channelCount)
        if let channelLayout = AVAudioChannelLayout(layoutTag: discreteLayoutTag) {
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                interleaved: false,
                channelLayout: channelLayout
            )
        }

        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat
                | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size),
            mChannelsPerFrame: channelCount,
            mBitsPerChannel: UInt32(MemoryLayout<Float32>.size * 8),
            mReserved: 0
        )
        return AVAudioFormat(streamDescription: &description)
    }

    static func makeMonoBuffer(
        from buffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard outputFormat.commonFormat == .pcmFormatFloat32,
            outputFormat.channelCount == 1,
            !outputFormat.isInterleaved
        else {
            return nil
        }

        let samples = monoSamples(from: buffer)
        guard !samples.isEmpty,
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let outputData = outputBuffer.floatChannelData?[0]
        else {
            return nil
        }

        outputBuffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            outputData[index] = samples[index]
        }
        return outputBuffer
    }

    static func monoSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard let channelData = buffer.floatChannelData else { return [] }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }

        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        }

        let rmsValues = (0..<channelCount).map { channel in
            channelRMS(channelData[channel], frameLength: frameLength)
        }
        guard let maximumRMS = rmsValues.max(), maximumRMS > 0 else {
            return [Float](repeating: 0, count: frameLength)
        }

        let threshold = max(minimumActiveChannelRMS, maximumRMS * relativeActiveChannelRMS)
        let activeChannels = rmsValues.indices.filter { rmsValues[$0] >= threshold }
        let channelsToMix =
            activeChannels.isEmpty
            ? [loudestChannelIndex(rmsValues)]
            : Array(activeChannels)

        var samples: [Float] = []
        samples.reserveCapacity(frameLength)
        for frame in 0..<frameLength {
            var mixedSample: Float = 0
            for channel in channelsToMix {
                mixedSample += channelData[channel][frame]
            }
            samples.append(clipped(mixedSample / Float(channelsToMix.count)))
        }
        return samples
    }

    private static func channelRMS(_ samples: UnsafePointer<Float>, frameLength: Int) -> Float {
        var meanSquare: Float = 0
        for frame in 0..<frameLength {
            let sample = samples[frame]
            meanSquare += sample * sample
        }
        meanSquare /= Float(frameLength)
        return sqrt(meanSquare)
    }

    private static func loudestChannelIndex(_ rmsValues: [Float]) -> Int {
        rmsValues.enumerated().max { lhs, rhs in
            lhs.element < rhs.element
        }?.offset ?? 0
    }

    private static func clipped(_ sample: Float) -> Float {
        min(1, max(-1, sample))
    }
}
