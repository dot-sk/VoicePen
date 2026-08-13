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
        inputFile.framePosition = startFrame
        guard
            let inputBuffer = try readFrames(
                from: inputFile,
                format: inputFormat,
                frameCount: frameCount
            )
        else {
            return nil
        }

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

    private func readFrames(
        from inputFile: AVAudioFile,
        format: AVAudioFormat,
        frameCount: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer? {
        guard let destination = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
        }
        let readCapacity = min(frameCount, 65_536)
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: readCapacity) else {
            throw MeetingRecordingError.captureFailed("Meeting audio input buffer is unavailable.")
        }

        destination.frameLength = frameCount
        var copiedFrames: AVAudioFrameCount = 0
        while copiedFrames < frameCount {
            let requestedFrames = min(readCapacity, frameCount - copiedFrames)
            try inputFile.read(into: readBuffer, frameCount: requestedFrames)
            let readFrames = readBuffer.frameLength
            guard readFrames > 0 else { break }
            guard
                copyFrames(
                    from: readBuffer,
                    to: destination,
                    destinationFrameOffset: copiedFrames,
                    frameCount: readFrames,
                    format: format
                )
            else {
                throw MeetingRecordingError.captureFailed("Meeting audio input buffer could not be copied.")
            }
            copiedFrames += readFrames
        }

        destination.frameLength = copiedFrames
        return copiedFrames > 0 ? destination : nil
    }

    private func copyFrames(
        from source: AVAudioPCMBuffer,
        to destination: AVAudioPCMBuffer,
        destinationFrameOffset: AVAudioFrameCount,
        frameCount: AVAudioFrameCount,
        format: AVAudioFormat
    ) -> Bool {
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let destinationByteOffset = Int(destinationFrameOffset) * bytesPerFrame
        let byteCount = Int(frameCount) * bytesPerFrame
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard bytesPerFrame > 0, sourceBuffers.count == destinationBuffers.count else { return false }

        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                let destinationData = destinationBuffers[index].mData,
                byteCount <= Int(sourceBuffers[index].mDataByteSize),
                destinationByteOffset + byteCount <= Int(destinationBuffers[index].mDataByteSize)
            else {
                return false
            }
            memcpy(destinationData.advanced(by: destinationByteOffset), sourceData, byteCount)
        }
        return true
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
    private let inputFormat: AVAudioFormat
    private let writer: MeetingAudioBufferWriting
    private var didWriteSamples = false
    private var didFinish = false
    private var latestLevel: Double?
    private var acceptedDuration: TimeInterval = 0
    private var firstFailure: MeetingRecordingError?

    init(
        source: MeetingSourceKind,
        outputURL: URL,
        format inputFormat: AVAudioFormat,
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO()
    ) throws {
        let outputFormat = try audioFileIO.storageFormat()
        let writer: ExtendedAudioFileWriter
        do {
            writer = try ExtendedAudioFileWriter(
                outputURL: outputURL,
                clientFormat: inputFormat,
                fileFormat: outputFormat
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw MeetingRecordingError.captureFailed(
                "Meeting \(source.rawValue) audio writer could not be created."
            )
        }
        self.source = source
        self.outputURL = outputURL
        self.audioFileIO = audioFileIO
        self.inputFormat = inputFormat
        self.writer = writer
    }

    init(
        source: MeetingSourceKind,
        outputURL: URL,
        format inputFormat: AVAudioFormat,
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO(),
        writer: MeetingAudioBufferWriting
    ) {
        self.source = source
        self.outputURL = outputURL
        self.audioFileIO = audioFileIO
        self.inputFormat = inputFormat
        self.writer = writer
    }

    var level: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestLevel
    }

    var hasFailed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return firstFailure != nil
    }

    func fail(_ error: MeetingRecordingError) {
        lock.lock()
        _ = recordFailure(error)
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        if let firstFailure {
            throw firstFailure
        }
        guard buffer.format.matches(inputFormat) else {
            throw recordFailure(
                MeetingRecordingError.captureFailed(
                    "Meeting \(source.rawValue) audio input format changed during capture."
                )
            )
        }
        guard buffer.frameLength > 0 else { return }

        do {
            try writer.write(buffer)
            didWriteSamples = true
            acceptedDuration += Double(buffer.frameLength) / buffer.format.sampleRate
            latestLevel = audioFileIO.normalizedLevel(from: buffer)
        } catch {
            throw recordFailure(
                MeetingRecordingError.captureFailed(
                    "Meeting \(source.rawValue) audio could not be written."
                )
            )
        }
    }

    func finish(startOffset: TimeInterval, endOffset: TimeInterval) throws -> MeetingAudioChunk? {
        lock.lock()
        do {
            try closeWriter()
        } catch {
            _ = recordFailure(
                MeetingRecordingError.captureFailed(
                    "Meeting \(source.rawValue) audio writer could not be closed."
                )
            )
        }
        let didWriteSamples = didWriteSamples
        let acceptedDuration = acceptedDuration
        let firstFailure = firstFailure
        lock.unlock()

        if let firstFailure {
            try? FileManager.default.removeItem(at: outputURL)
            throw firstFailure
        }
        guard didWriteSamples,
            FileManager.default.fileExists(atPath: outputURL.path)
        else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        let probe = MeetingAudioChunk(
            url: outputURL,
            source: source,
            startOffset: startOffset,
            duration: acceptedDuration
        )
        let expectedDuration = max(0, endOffset - startOffset)
        guard let readableDuration = try audioFileIO.readableDuration(for: probe),
            abs(readableDuration - acceptedDuration) <= Self.maximumWriterDurationMismatch,
            readableDuration + Self.maximumTimelineShortfall >= expectedDuration
        else {
            try? FileManager.default.removeItem(at: outputURL)
            throw MeetingRecordingError.captureFailed(
                "Meeting \(source.rawValue) audio lost captured frames before finalization."
            )
        }

        return MeetingAudioChunk(
            url: outputURL,
            source: source,
            startOffset: startOffset,
            duration: min(expectedDuration, readableDuration)
        )
    }

    func cancel() {
        lock.lock()
        do {
            try closeWriter()
        } catch {
            AppLogger.error(
                "Meeting \(source.rawValue) audio writer close failed during cancellation: "
                    + error.localizedDescription
            )
        }
        lock.unlock()
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func closeWriter() throws {
        guard !didFinish else { return }
        didFinish = true
        try writer.close()
    }

    private func recordFailure(_ error: MeetingRecordingError) -> MeetingRecordingError {
        if let firstFailure {
            return firstFailure
        }
        firstFailure = error
        AppLogger.error(error.localizedDescription)
        return error
    }

    private static let maximumWriterDurationMismatch: TimeInterval = 0.25
    private static let maximumTimelineShortfall: TimeInterval = 2
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

extension AVAudioFormat {
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
