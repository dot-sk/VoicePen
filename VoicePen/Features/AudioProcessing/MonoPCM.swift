@preconcurrency import AVFoundation
import Foundation

nonisolated struct MonoPCM: Sendable {
    let samples: [Float]
    let sampleRate: Double

    init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    init(buffer: AVAudioPCMBuffer) throws {
        guard let channelData = buffer.floatChannelData else {
            throw MonoPCMError.couldNotReadSamples
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            self.init(samples: [], sampleRate: buffer.format.sampleRate)
            return
        }

        if channelCount == 1 {
            self.init(
                samples: Array(
                    UnsafeBufferPointer(
                        start: channelData[0],
                        count: frameLength
                    )
                ),
                sampleRate: buffer.format.sampleRate
            )
            return
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
        self.init(samples: samples, sampleRate: buffer.format.sampleRate)
    }

    static func read(from url: URL) throws -> MonoPCM {
        let file = try AVAudioFile(forReading: url)
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        else {
            throw MonoPCMError.couldNotCreateBuffer
        }
        try file.read(into: buffer)
        return try MonoPCM(buffer: buffer)
    }

    func resampled(to outputSampleRate: Double) throws -> MonoPCM {
        guard sampleRate > 0, outputSampleRate > 0 else {
            throw MonoPCMError.invalidSampleRate
        }
        guard sampleRate != outputSampleRate else { return self }

        let inputBuffer = try makeBuffer()
        let outputFormat = try Self.floatFormat(sampleRate: outputSampleRate)
        let converter = try PCMStreamConverter(
            inputFormat: inputBuffer.format,
            outputFormat: outputFormat
        )
        return try MonoPCM(buffer: converter.convert(inputBuffer))
    }

    func write(to url: URL) throws {
        try write(to: url, sampleRange: samples.indices)
    }

    func write(to url: URL, sampleRange: Range<Int>) throws {
        let buffer = try makeBuffer(sampleRange: sampleRange)
        let file = try AVAudioFile(
            forWriting: url,
            settings: buffer.format.settings
        )
        try file.write(from: buffer)
    }

    func makeBuffer() throws -> AVAudioPCMBuffer {
        try makeBuffer(sampleRange: samples.indices)
    }

    private func makeBuffer(sampleRange: Range<Int>) throws -> AVAudioPCMBuffer {
        guard sampleRange.lowerBound >= samples.startIndex,
            sampleRange.upperBound <= samples.endIndex
        else {
            throw MonoPCMError.invalidSampleRange
        }

        let format = try Self.floatFormat(sampleRate: sampleRate)
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(sampleRange.count)
            ),
            let outputSamples = buffer.floatChannelData?[0]
        else {
            throw MonoPCMError.couldNotCreateBuffer
        }

        buffer.frameLength = AVAudioFrameCount(sampleRange.count)
        samples.withUnsafeBufferPointer { source in
            guard let sourceAddress = source.baseAddress else { return }
            memcpy(
                outputSamples,
                sourceAddress.advanced(by: sampleRange.lowerBound),
                sampleRange.count * MemoryLayout<Float>.stride
            )
        }
        return buffer
    }

    private static func floatFormat(sampleRate: Double) throws -> AVAudioFormat {
        guard sampleRate > 0,
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw MonoPCMError.invalidSampleRate
        }
        return format
    }
}

nonisolated private enum MonoPCMError: LocalizedError {
    case invalidSampleRate
    case invalidSampleRange
    case couldNotCreateBuffer
    case couldNotReadSamples

    var errorDescription: String? {
        switch self {
        case .invalidSampleRate:
            return "Mono PCM audio has an invalid sample rate."
        case .invalidSampleRange:
            return "Mono PCM audio has an invalid sample range."
        case .couldNotCreateBuffer:
            return "VoicePen could not create a mono PCM buffer."
        case .couldNotReadSamples:
            return "VoicePen could not read mono PCM samples."
        }
    }
}
