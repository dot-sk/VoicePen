@preconcurrency import AVFoundation
import Foundation

nonisolated enum PCMStreamConverterError: LocalizedError {
    case conversionFailed

    var errorDescription: String? {
        "PCM conversion failed."
    }
}

nonisolated final class PCMStreamConverter: @unchecked Sendable {
    let inputFormat: AVAudioFormat
    let outputFormat: AVAudioFormat

    private let converter: AVAudioConverter
    private var inputBuffer: AVAudioPCMBuffer?
    private var inputFrameOffset: AVAudioFrameCount = 0
    private var scratchBuffer: AVAudioPCMBuffer?
    private var inputCopyFailed = false

    init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw PCMStreamConverterError.conversionFailed
        }
        converter.primeMethod = .none
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format.matches(inputFormat),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: outputFrameCapacity(for: buffer.frameLength)
            )
        else {
            throw PCMStreamConverterError.conversionFailed
        }

        inputBuffer = buffer
        inputFrameOffset = 0
        inputCopyFailed = false
        defer { inputBuffer = nil }

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { [self] packetCount, inputStatus in
            nextInputBuffer(packetCount: packetCount, inputStatus: inputStatus)
        }

        guard !inputCopyFailed, conversionError == nil,
            status == .haveData || status == .inputRanDry
        else {
            throw PCMStreamConverterError.conversionFailed
        }
        return outputBuffer
    }

    private func outputFrameCapacity(for inputFrameCount: AVAudioFrameCount) -> AVAudioFrameCount {
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        return max(1, AVAudioFrameCount((Double(inputFrameCount) * ratio).rounded(.up)) + 32)
    }

    private func nextInputBuffer(
        packetCount: AVAudioPacketCount,
        inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        guard let inputBuffer, inputFrameOffset < inputBuffer.frameLength else {
            inputStatus.pointee = .noDataNow
            return nil
        }

        let framesPerPacket = max(1, inputFormat.streamDescription.pointee.mFramesPerPacket)
        let requestedFrames = max(1, AVAudioFrameCount(packetCount) * framesPerPacket)
        let frameCount = min(requestedFrames, inputBuffer.frameLength - inputFrameOffset)
        if (scratchBuffer?.frameCapacity ?? 0) < frameCount {
            scratchBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frameCount)
        }
        guard let scratchBuffer, copyFrames(from: inputBuffer, count: frameCount, into: scratchBuffer) else {
            inputCopyFailed = true
            inputStatus.pointee = .noDataNow
            return nil
        }

        inputFrameOffset += frameCount
        inputStatus.pointee = .haveData
        return scratchBuffer
    }

    private func copyFrames(
        from source: AVAudioPCMBuffer,
        count: AVAudioFrameCount,
        into destination: AVAudioPCMBuffer
    ) -> Bool {
        destination.frameLength = count
        let bytesPerFrame = Int(inputFormat.streamDescription.pointee.mBytesPerFrame)
        let byteOffset = Int(inputFrameOffset) * bytesPerFrame
        let byteCount = Int(count) * bytesPerFrame
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
        guard bytesPerFrame > 0, sourceBuffers.count == destinationBuffers.count else { return false }

        for index in sourceBuffers.indices {
            guard let sourceData = sourceBuffers[index].mData,
                let destinationData = destinationBuffers[index].mData,
                byteOffset + byteCount <= Int(sourceBuffers[index].mDataByteSize),
                byteCount <= Int(destinationBuffers[index].mDataByteSize)
            else {
                return false
            }
            memcpy(destinationData, sourceData.advanced(by: byteOffset), byteCount)
        }
        return true
    }
}
