import AVFoundation
import Foundation
import whisper

nonisolated struct WhisperCppLanguageConfiguration: Equatable {
    let languageCode: String?
    let detectLanguageOnly: Bool

    static func resolve(language: String) -> WhisperCppLanguageConfiguration {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedLanguage.isEmpty, normalizedLanguage != "auto" else {
            return WhisperCppLanguageConfiguration(languageCode: nil, detectLanguageOnly: false)
        }

        return WhisperCppLanguageConfiguration(languageCode: normalizedLanguage, detectLanguageOnly: false)
    }
}

actor WhisperCppContext {
    private let handle: WhisperCppContextHandle

    init(modelPath: String) throws {
        var contextParameters = whisper_context_default_params()
        #if targetEnvironment(simulator)
        contextParameters.use_gpu = false
        #else
        contextParameters.flash_attn = true
        #endif

        guard let context = whisper_init_from_file_with_params(modelPath, contextParameters) else {
            throw TranscriptionError.modelLoadFailed("whisper.cpp could not load model at \(modelPath)")
        }
        self.handle = WhisperCppContextHandle(context)
    }

    func transcribe(audioURL: URL, prompt: String, language: String) throws -> String {
        let context = handle.pointer

        let samples = try Self.readAudioSamples(audioURL)
        let options = WhisperCppDecodingOptions.resolve(sampleCount: samples.count)
        let text = try runWhisper(
            context: context,
            samples: samples,
            prompt: prompt,
            language: language,
            singleSegment: options.singleSegment
        )

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranscriptionError.emptyResult
        }
        return trimmedText
    }

    func warmUp(language: String) throws {
        let context = handle.pointer

        let samples = [Float](repeating: 0, count: 16_000)
        let options = WhisperCppDecodingOptions.resolve(sampleCount: samples.count, isWarmup: true)
        _ = try runWhisper(
            context: context,
            samples: samples,
            prompt: "",
            language: language,
            singleSegment: options.singleSegment
        )
    }

    private func runWhisper(
        context: OpaquePointer,
        samples: [Float],
        prompt: String,
        language: String,
        singleSegment: Bool
    ) throws -> String {
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)

        let languageConfiguration = WhisperCppLanguageConfiguration.resolve(language: language)
        let languageCString = languageConfiguration.languageCode.map { Array($0.utf8CString) }

        let promptCString: [CChar]?
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            promptCString = Array(trimmedPrompt.utf8CString)
        } else {
            promptCString = nil
        }

        parameters.print_realtime = false
        parameters.print_progress = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = false
        parameters.detect_language = languageConfiguration.detectLanguageOnly
        parameters.no_context = true
        parameters.single_segment = singleSegment
        parameters.temperature = 0.0
        parameters.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))

        whisper_reset_timings(context)

        let status: Int32
        if let languageCString, let promptCString {
            status = languageCString.withUnsafeBufferPointer { languageBuffer in
                promptCString.withUnsafeBufferPointer { promptBuffer in
                    parameters.language = languageBuffer.baseAddress
                    parameters.initial_prompt = promptBuffer.baseAddress
                    return samples.withUnsafeBufferPointer { sampleBuffer in
                        whisper_full(context, parameters, sampleBuffer.baseAddress, Int32(sampleBuffer.count))
                    }
                }
            }
        } else if let languageCString {
            status = languageCString.withUnsafeBufferPointer { languageBuffer in
                parameters.language = languageBuffer.baseAddress
                return samples.withUnsafeBufferPointer { sampleBuffer in
                    whisper_full(context, parameters, sampleBuffer.baseAddress, Int32(sampleBuffer.count))
                }
            }
        } else if let promptCString {
            status = promptCString.withUnsafeBufferPointer { promptBuffer in
                parameters.initial_prompt = promptBuffer.baseAddress
                return samples.withUnsafeBufferPointer { sampleBuffer in
                    whisper_full(context, parameters, sampleBuffer.baseAddress, Int32(sampleBuffer.count))
                }
            }
        } else {
            status = samples.withUnsafeBufferPointer { sampleBuffer in
                whisper_full(context, parameters, sampleBuffer.baseAddress, Int32(sampleBuffer.count))
            }
        }

        guard status == 0 else {
            throw TranscriptionError.transcriptionFailed("whisper.cpp transcription failed with status \(status).")
        }

        var text = ""
        for index in 0..<whisper_full_n_segments(context) {
            if let segment = whisper_full_get_segment_text(context, index) {
                text += String(cString: segment)
            }
        }

        return text
    }

    private static func readAudioSamples(_ url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw TranscriptionError.transcriptionFailed("Could not create audio buffer.")
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw TranscriptionError.transcriptionFailed("Could not read audio samples.")
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
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
}

nonisolated private final class WhisperCppContextHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(_ pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        whisper_free(pointer)
    }
}
