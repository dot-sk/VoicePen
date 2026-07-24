import Accelerate
import CRNNoise
import Foundation

nonisolated protocol AudioDenoising: Sendable {
    func process(samples: [Float], sampleRate: Int) throws -> [Float]
}

nonisolated final class RNNoiseAudioDenoiser: AudioDenoising, @unchecked Sendable {
    private static let processingSampleRate = 48_000
    private static let modelResourceName = "rnnoise-model-v0.2"

    private let lock = NSLock()
    private let model: OpaquePointer

    init?(modelURL: URL?) {
        guard let modelURL,
            FileManager.default.fileExists(atPath: modelURL.path),
            let model = modelURL.path.withCString({ rnnoise_model_from_filename($0) })
        else {
            return nil
        }
        self.model = model
    }

    deinit {
        rnnoise_model_free(model)
    }

    func process(samples: [Float], sampleRate: Int) throws -> [Float] {
        guard !samples.isEmpty else { return samples }
        guard sampleRate > 0 else {
            throw RNNoiseAudioDenoiserError.invalidSampleRate
        }

        lock.lock()
        defer { lock.unlock() }

        let resampleInStart = DispatchTime.now().uptimeNanoseconds
        let input = try MonoPCM(
            samples: samples,
            sampleRate: Double(sampleRate)
        ).resampled(to: Double(Self.processingSampleRate)).samples
        let resampleInDuration = elapsedTime(since: resampleInStart)
        guard let state = rnnoise_create(model) else {
            throw RNNoiseAudioDenoiserError.couldNotCreateState
        }
        defer { rnnoise_destroy(state) }

        let frameSize = Int(rnnoise_get_frame_size())
        guard frameSize > 0 else {
            throw RNNoiseAudioDenoiserError.invalidFrameSize
        }

        let frameCount = (input.count + frameSize - 1) / frameSize
        var denoised = Array(repeating: Float(0), count: frameCount * frameSize)
        var inputFrame = Array(repeating: Float(0), count: frameSize)
        var inputScale: Float = 32_768
        var outputScale: Float = 1 / 32_768

        let rnnoiseStart = DispatchTime.now().uptimeNanoseconds
        input.withUnsafeBufferPointer { inputBuffer in
            inputFrame.withUnsafeMutableBufferPointer { frameBuffer in
                denoised.withUnsafeMutableBufferPointer { outputBuffer in
                    guard
                        let inputBaseAddress = inputBuffer.baseAddress,
                        let frameBaseAddress = frameBuffer.baseAddress,
                        let outputBaseAddress = outputBuffer.baseAddress
                    else {
                        return
                    }

                    for frameIndex in 0..<frameCount {
                        let start = frameIndex * frameSize
                        let count = min(frameSize, input.count - start)
                        if count < frameSize {
                            frameBuffer.update(repeating: 0)
                        }
                        vDSP_vsmul(
                            inputBaseAddress.advanced(by: start),
                            1,
                            &inputScale,
                            frameBaseAddress,
                            1,
                            vDSP_Length(count)
                        )

                        let frameOutput = outputBaseAddress.advanced(by: start)
                        _ = rnnoise_process_frame(
                            state,
                            frameOutput,
                            frameBaseAddress
                        )
                        vDSP_vsmul(
                            frameOutput,
                            1,
                            &outputScale,
                            frameOutput,
                            1,
                            vDSP_Length(frameSize)
                        )
                    }
                }
            }
        }
        let rnnoiseDuration = elapsedTime(since: rnnoiseStart)

        let resampleOutStart = DispatchTime.now().uptimeNanoseconds
        var output = try MonoPCM(
            samples: denoised,
            sampleRate: Double(Self.processingSampleRate)
        ).resampled(to: Double(sampleRate)).samples
        if output.count > samples.count {
            output.removeLast(output.count - samples.count)
        } else if output.count < samples.count {
            output.append(
                contentsOf: repeatElement(Float.zero, count: samples.count - output.count)
            )
        }
        let resampleOutDuration = elapsedTime(since: resampleOutStart)

        AppLogger.info(
            String(
                format:
                    "RNNoise timings: resample-in=%.3fs, rnnoise=%.3fs, resample-out=%.3fs",
                resampleInDuration,
                rnnoiseDuration,
                resampleOutDuration
            )
        )
        return output
    }

    static func bundledModelURL() -> URL? {
        #if SWIFT_PACKAGE
            modelURL(in: .module)
        #else
            modelURL(in: .main)
        #endif
    }

    static func modelURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: modelResourceName, withExtension: "bin")
            ?? bundle.url(
                forResource: modelResourceName,
                withExtension: "bin",
                subdirectory: "Resources"
            )
    }
}

nonisolated private func elapsedTime(since start: UInt64) -> TimeInterval {
    TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
}

nonisolated private enum RNNoiseAudioDenoiserError: LocalizedError {
    case invalidSampleRate
    case couldNotCreateState
    case invalidFrameSize

    var errorDescription: String? {
        switch self {
        case .invalidSampleRate:
            return "RNNoise received an invalid sample rate."
        case .couldNotCreateState:
            return "RNNoise could not create a processing state."
        case .invalidFrameSize:
            return "RNNoise returned an invalid frame size."
        }
    }
}
