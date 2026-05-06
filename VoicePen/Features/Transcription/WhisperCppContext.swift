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

nonisolated struct WhisperCppTimings: Equatable {
    let elapsedMilliseconds: Double
    let sampleCount: Int
    let threadCount: Int32
    let audioContext: Int32
    let singleSegment: Bool
    let noTimestamps: Bool
    let tokenTimestamps: Bool
    let maxSegmentLength: Int32
}

nonisolated private struct WhisperCppRunResult {
    let text: String
    let segments: [TranscriptionSegment]
    let timings: WhisperCppTimings
}

actor WhisperCppContext {
    private let handle: WhisperCppContextHandle

    init(modelPath: String) throws {
        var contextParameters = whisper_context_default_params()
        #if targetEnvironment(simulator)
            contextParameters.use_gpu = false
        #else
            contextParameters.use_gpu = true
            contextParameters.flash_attn = true
        #endif

        guard let context = whisper_init_from_file_with_params(modelPath, contextParameters) else {
            throw TranscriptionError.modelLoadFailed("whisper.cpp could not load model at \(modelPath)")
        }
        self.handle = WhisperCppContextHandle(context)
    }

    func transcribe(
        audioURL: URL,
        prompt: String,
        language: String,
        includeTimestamps: Bool = false,
    ) throws -> TranscriptionClientResult {
        let context = handle.pointer

        let samples = try Self.readAudioSamples(audioURL)
        let options = WhisperCppDecodingOptions.resolve(
            sampleCount: samples.count,
            includeTimestamps: includeTimestamps
        )
        let result = try runWhisper(
            context: context,
            samples: samples,
            prompt: prompt,
            language: language,
            options: options
        )

        let trimmedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw TranscriptionError.emptyResult
        }
        return TranscriptionClientResult(text: trimmedText, segments: result.segments)
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
            options: options
        )
    }

    func benchmark(audioURL: URL, prompt: String, language: String) throws -> [WhisperCppBenchmarkResult] {
        let context = handle.pointer
        let samples = try Self.readAudioSamples(audioURL)
        let configurations = WhisperCppBenchmarkPlan.configurations(preferredLanguage: language)

        return try configurations.map { configuration in
            let options = WhisperCppDecodingOptions.resolve(
                sampleCount: samples.count,
                processorCount: Int(configuration.threadCount) + 2,
                audioContext: configuration.audioContext
            )
            let configuredOptions = WhisperCppDecodingOptions(
                singleSegment: options.singleSegment,
                noTimestamps: options.noTimestamps,
                tokenTimestamps: options.tokenTimestamps,
                maxSegmentLength: options.maxSegmentLength,
                splitOnWord: options.splitOnWord,
                audioContext: options.audioContext,
                threadCount: configuration.threadCount
            )
            let start = Date()
            let result = try runWhisper(
                context: context,
                samples: samples,
                prompt: prompt,
                language: configuration.language,
                options: configuredOptions
            )
            return WhisperCppBenchmarkResult(
                configuration: configuration,
                elapsedSeconds: Date().timeIntervalSince(start),
                timings: result.timings,
                textLength: result.text.count
            )
        }
    }

    private func runWhisper(
        context: OpaquePointer,
        samples: [Float],
        prompt: String,
        language: String,
        options: WhisperCppDecodingOptions
    ) throws -> WhisperCppRunResult {
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
        parameters.no_timestamps = options.noTimestamps
        parameters.token_timestamps = options.tokenTimestamps
        parameters.max_len = options.maxSegmentLength
        parameters.split_on_word = options.splitOnWord
        parameters.no_context = true
        parameters.single_segment = options.singleSegment
        parameters.suppress_non_speech_tokens = true
        parameters.temperature = 0.0
        parameters.audio_ctx = options.audioContext
        parameters.n_threads = options.threadCount

        whisper_reset_timings(context)
        let start = Date()

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
        var segments: [TranscriptionSegment] = []
        for index in 0..<whisper_full_n_segments(context) {
            if let segment = whisper_full_get_segment_text(context, index) {
                let segmentText = String(cString: segment)
                text += segmentText
                if !parameters.no_timestamps {
                    segments.append(
                        TranscriptionSegment(
                            text: segmentText,
                            startTime: TimeInterval(whisper_full_get_segment_t0(context, index)) / 100,
                            endTime: TimeInterval(whisper_full_get_segment_t1(context, index)) / 100
                        )
                    )
                }
            }
        }

        let timings = WhisperCppTimings(
            elapsedMilliseconds: Date().timeIntervalSince(start) * 1_000,
            sampleCount: samples.count,
            threadCount: options.threadCount,
            audioContext: options.audioContext,
            singleSegment: options.singleSegment,
            noTimestamps: options.noTimestamps,
            tokenTimestamps: options.tokenTimestamps,
            maxSegmentLength: options.maxSegmentLength
        )

        return WhisperCppRunResult(text: text, segments: segments, timings: timings)
    }

    private static func readAudioSamples(_ url: URL) throws -> [Float] {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            )
        else {
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
