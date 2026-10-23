@preconcurrency import AVFoundation
import CoreML
import FluidAudio
import Foundation

public struct NemotronFileResult: Sendable, Equatable {
    public let text: String
    public let inputSampleCount: Int
}

public enum NemotronFileError: Error {
    case invalidAudio
    case incompleteAudio
}

public actor NemotronFileContext {
    private let directory: URL
    private var manager: StreamingNemotronAsrManager?

    public init(directory: URL) {
        self.directory = directory
    }

    public func warmUp() async throws {
        guard manager == nil else { return }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let manager = StreamingNemotronAsrManager(configuration: configuration)
        try await manager.loadModels(from: directory)
        self.manager = manager
    }

    public func transcribe(audioURL: URL) async throws -> NemotronFileResult {
        try Task.checkCancellation()
        try await warmUp()
        guard let manager else { throw NemotronFileError.invalidAudio }
        await manager.reset()
        do {
            let file = try AVAudioFile(forReading: audioURL)
            let format = file.processingFormat
            guard format.sampleRate == 16_000, format.channelCount == 1, file.length > 0 else {
                throw NemotronFileError.invalidAudio
            }
            var submitted = 0
            while file.framePosition < file.length {
                try Task.checkCancellation()
                let requested = AVAudioFrameCount(min(35_840, file.length - file.framePosition))
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: requested) else {
                    throw NemotronFileError.invalidAudio
                }
                try file.read(into: buffer, frameCount: requested)
                guard buffer.frameLength > 0 else { throw NemotronFileError.incompleteAudio }
                guard let samples = buffer.floatChannelData?[0],
                    UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)).allSatisfy(\.isFinite)
                else { throw NemotronFileError.invalidAudio }
                submitted += Int(buffer.frameLength)
                _ = try await manager.process(audioBuffer: buffer)
            }
            try Task.checkCancellation()
            let text = try await manager.finish()
            await manager.reset()
            try Task.checkCancellation()
            return NemotronFileResult(text: text, inputSampleCount: submitted)
        } catch {
            await manager.reset()
            throw error
        }
    }
}
