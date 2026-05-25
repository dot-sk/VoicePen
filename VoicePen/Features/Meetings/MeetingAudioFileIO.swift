@preconcurrency import AVFoundation
import Foundation

nonisolated protocol MeetingAudioFileIO: Sendable {
    var sampleRate: Double { get }

    func processingFormat() throws -> AVAudioFormat
    func storageFormat() throws -> AVAudioFormat
    func storageBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer
    func writeMonoSamples(_ samples: [Float], to outputURL: URL) throws -> TimeInterval
    func readableDuration(for chunk: MeetingAudioChunk) throws -> TimeInterval?
    func readMonoSampleWindow(
        _ window: MeetingAudioChunk,
        in sourceChunk: MeetingAudioChunk
    ) throws -> MeetingAudioSampleWindow?
    func readMonoSamples(from url: URL, targetSampleRate: Int) throws -> [Float]
    func averageAbsoluteFrameLevels(for span: MeetingAudioSourceSpan) throws -> MeetingAudioFrameLevelWindow?
    func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double?
}

nonisolated struct MeetingAudioSampleWindow: Sendable {
    var samples: [Float]
    var duration: TimeInterval
}

nonisolated struct MeetingAudioFrameLevelWindow: Sendable {
    var levels: [Double]
    var sampleRate: Double
    var duration: TimeInterval
}

nonisolated struct AVFoundationMeetingAudioFileIO: MeetingAudioFileIO {
    let sampleRate = 16_000.0

    func processingFormat() throws -> AVAudioFormat {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio processing format is unavailable.")
        }
        return format
    }

    func storageFormat() throws -> AVAudioFormat {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio output format is unavailable.")
        }
        return format
    }

    func storageBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let outputFormat = try storageFormat()
        guard !buffer.format.matches(outputFormat) else { return buffer }
        return try convertBuffer(buffer, to: outputFormat)
    }

    private func writeStorageBuffer(_ buffer: AVAudioPCMBuffer, to outputURL: URL) throws -> TimeInterval {
        let outputBuffer = try storageBuffer(from: buffer)
        let outputFormat = outputBuffer.format
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
        try outputFile.write(from: outputBuffer)
        return Double(outputBuffer.frameLength) / outputFormat.sampleRate
    }

    func writeMonoSamples(_ samples: [Float], to outputURL: URL) throws -> TimeInterval {
        guard !samples.isEmpty else { return 0 }

        let format = try processingFormat()
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let outputSamples = buffer.floatChannelData?[0]
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices {
            outputSamples[index] = samples[index]
        }
        return try writeStorageBuffer(buffer, to: outputURL)
    }

    func readableDuration(for chunk: MeetingAudioChunk) throws -> TimeInterval? {
        let file = try AVAudioFile(forReading: chunk.url)
        let sampleRate = file.processingFormat.sampleRate
        guard file.length > 0, sampleRate > 0 else {
            return nil
        }
        return Double(file.length) / sampleRate
    }

    func readMonoSampleWindow(
        _ window: MeetingAudioChunk,
        in sourceChunk: MeetingAudioChunk
    ) throws -> MeetingAudioSampleWindow? {
        guard
            let readableBuffer = try readBufferWindow(
                window,
                in: sourceChunk,
                outputFormat: processingFormat()
            )
        else {
            return nil
        }

        guard let samples = MeetingAudioSamples.monoFloatSamples(from: readableBuffer.buffer),
            !samples.isEmpty
        else {
            return nil
        }
        return MeetingAudioSampleWindow(samples: samples, duration: readableBuffer.duration)
    }

    func readMonoSamples(from url: URL, targetSampleRate: Int) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let inputFormat = audioFile.processingFormat
        guard
            let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            )
        else {
            throw TranscriptionError.transcriptionFailed("Could not create diarization audio buffer.")
        }

        try audioFile.read(into: inputBuffer)
        guard inputBuffer.frameLength > 0 else { return [] }

        let outputFormat = try monoFloatFormat(sampleRate: Double(targetSampleRate))
        let sampleBuffer =
            inputFormat.matches(outputFormat)
            ? inputBuffer
            : try convertBuffer(inputBuffer, to: outputFormat)
        guard let samples = MeetingAudioSamples.monoFloatSamples(from: sampleBuffer) else {
            throw TranscriptionError.transcriptionFailed("Could not read diarization audio samples.")
        }
        return samples
    }

    func averageAbsoluteFrameLevels(for span: MeetingAudioSourceSpan) throws -> MeetingAudioFrameLevelWindow? {
        let window = MeetingAudioChunk(
            url: span.sourceURL,
            source: span.source,
            startOffset: span.startOffset,
            duration: span.duration
        )
        let sourceChunk = MeetingAudioChunk(
            url: span.sourceURL,
            source: span.source,
            startOffset: span.sourceStartOffset,
            duration: span.duration
        )
        guard
            let readableBuffer = try readBufferWindow(
                window,
                in: sourceChunk,
                outputFormat: processingFormat()
            ),
            let levels = MeetingAudioSamples.averageAbsoluteFrameLevels(from: readableBuffer.buffer),
            !levels.isEmpty
        else {
            return nil
        }

        return MeetingAudioFrameLevelWindow(
            levels: levels,
            sampleRate: readableBuffer.buffer.format.sampleRate,
            duration: readableBuffer.duration
        )
    }

    func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double? {
        MeetingAudioSamples.normalizedLevel(from: buffer)
    }

    private func readBufferWindow(
        _ window: MeetingAudioChunk,
        in sourceChunk: MeetingAudioChunk,
        outputFormat: AVAudioFormat
    ) throws -> MeetingAudioBufferWindow? {
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

        guard frameCount > 0 else {
            return nil
        }
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount) else {
            throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
        }

        inputFile.framePosition = startFrame
        try inputFile.read(into: inputBuffer, frameCount: frameCount)

        let duration = Double(inputBuffer.frameLength) / sampleRate
        guard inputBuffer.frameLength > 0, duration > 0 else {
            return nil
        }

        let outputBuffer =
            inputFormat.matches(outputFormat)
            ? inputBuffer
            : try convertBuffer(inputBuffer, to: outputFormat)
        guard outputBuffer.frameLength > 0 else {
            return nil
        }
        return MeetingAudioBufferWindow(buffer: outputBuffer, duration: duration)
    }

    private func monoFloatFormat(sampleRate: Double) throws -> AVAudioFormat {
        guard
            let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio processing format is unavailable.")
        }
        return format
    }

    private func convertBuffer(
        _ inputBuffer: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            throw MeetingRecordingError.captureFailed("Meeting audio converter is unavailable.")
        }
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: MeetingAudioFrameCapacity.converted(
                    inputFrames: inputBuffer.frameLength,
                    inputSampleRate: inputBuffer.format.sampleRate,
                    outputSampleRate: outputFormat.sampleRate
                )
            )
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
        }

        let inputProvider = MeetingAudioSingleBufferInputProvider(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.next(inputStatus: inputStatus)
        }

        guard conversionError == nil, status == .haveData || status == .inputRanDry else {
            throw MeetingRecordingError.captureFailed("Meeting audio conversion failed.")
        }

        return outputBuffer
    }
}

nonisolated final class MeetingAudioBufferFileSink: @unchecked Sendable {
    let source: MeetingSourceKind
    let outputURL: URL

    private let lock = NSLock()
    private let audioFileIO: MeetingAudioFileIO
    private let audioFile: AVAudioFile
    private var didWriteSamples = false
    private var didFinish = false
    private var latestLevel: Double?

    init(
        source: MeetingSourceKind,
        outputURL: URL,
        format _: AVAudioFormat,
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO()
    ) throws {
        let outputFormat = try audioFileIO.storageFormat()
        self.source = source
        self.outputURL = outputURL
        self.audioFileIO = audioFileIO
        audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: outputFormat.commonFormat,
            interleaved: outputFormat.isInterleaved
        )
    }

    var level: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestLevel
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        let outputBuffer = try audioFileIO.storageBuffer(from: buffer)
        guard outputBuffer.frameLength > 0 else { return }
        try audioFile.write(from: outputBuffer)
        didWriteSamples = true
        latestLevel = audioFileIO.normalizedLevel(from: outputBuffer)
    }

    func finish(startOffset: TimeInterval, endOffset: TimeInterval) throws -> MeetingAudioChunk? {
        lock.lock()
        didFinish = true
        let didWriteSamples = didWriteSamples
        lock.unlock()

        guard didWriteSamples,
            FileManager.default.fileExists(atPath: outputURL.path)
        else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        return MeetingAudioChunk(
            url: outputURL,
            source: source,
            startOffset: startOffset,
            duration: max(0, endOffset - startOffset)
        )
    }

    func cancel() {
        lock.lock()
        didFinish = true
        lock.unlock()
        try? FileManager.default.removeItem(at: outputURL)
    }
}

nonisolated enum MeetingAudioFrameCapacity {
    static func converted(
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
}

nonisolated final class MeetingAudioSingleBufferInputProvider: @unchecked Sendable {
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

nonisolated private struct MeetingAudioBufferWindow {
    var buffer: AVAudioPCMBuffer
    var duration: TimeInterval
}

private extension AVAudioFormat {
    nonisolated func matches(_ other: AVAudioFormat) -> Bool {
        commonFormat == other.commonFormat
            && sampleRate == other.sampleRate
            && channelCount == other.channelCount
            && isInterleaved == other.isInterleaved
    }
}

nonisolated private enum MeetingAudioSamples {
    static func monoFloatSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return nil }
            var samples: [Float] = []
            samples.reserveCapacity(frameLength)
            for frame in 0..<frameLength {
                var value: Float = 0
                for channel in 0..<channelCount {
                    value += channelData[channel][frame]
                }
                samples.append(value / Float(channelCount))
            }
            return samples
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return nil }
            var samples: [Float] = []
            samples.reserveCapacity(frameLength)
            for frame in 0..<frameLength {
                var value: Float = 0
                for channel in 0..<channelCount {
                    value += Float(channelData[channel][frame]) / 32_768
                }
                samples.append(value / Float(channelCount))
            }
            return samples
        case .pcmFormatInt32:
            guard let channelData = buffer.int32ChannelData else { return nil }
            var samples: [Float] = []
            samples.reserveCapacity(frameLength)
            for frame in 0..<frameLength {
                var value: Float = 0
                for channel in 0..<channelCount {
                    value += Float(channelData[channel][frame]) / 2_147_483_648
                }
                samples.append(value / Float(channelCount))
            }
            return samples
        default:
            return nil
        }
    }

    static func averageAbsoluteFrameLevels(from buffer: AVAudioPCMBuffer) -> [Double]? {
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return [] }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else { return nil }
            return (0..<frameLength).map { frame in
                var total = 0.0
                for channel in 0..<channelCount {
                    total += Double(abs(channelData[channel][frame]))
                }
                return total / Double(channelCount)
            }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else { return nil }
            return (0..<frameLength).map { frame in
                var total = 0.0
                for channel in 0..<channelCount {
                    total += abs(Double(channelData[channel][frame]) / 32_768)
                }
                return total / Double(channelCount)
            }
        case .pcmFormatInt32:
            guard let channelData = buffer.int32ChannelData else { return nil }
            return (0..<frameLength).map { frame in
                var total = 0.0
                for channel in 0..<channelCount {
                    total += abs(Double(channelData[channel][frame]) / 2_147_483_648)
                }
                return total / Double(channelCount)
            }
        default:
            return nil
        }
    }

    static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double? {
        guard let frameLevels = averageAbsoluteFrameLevels(from: buffer),
            !frameLevels.isEmpty
        else {
            return nil
        }

        let average = frameLevels.reduce(0, +) / Double(frameLevels.count)
        return min(1, average * 8)
    }
}
