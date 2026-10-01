import Foundation

nonisolated enum WhisperCppSamplingStrategy: Equatable, Sendable {
    case greedy
    case beamSearch
}

nonisolated enum WhisperCppDecodeDiagnostics {
    static func profileLabel(for profile: LocalDecodingProfile) -> String {
        switch profile {
        case .standard:
            return "standard-greedy"
        case .maximumQuality:
            return "maximum-quality-beam-search"
        }
    }
}

nonisolated struct WhisperCppDecodingOptions: Equatable {
    static let defaultSampleRate: Double = 16_000
    static let shortUtteranceMaximumDuration: TimeInterval = 10

    let singleSegment: Bool
    let noTimestamps: Bool
    let tokenTimestamps: Bool
    let maxSegmentLength: Int32
    let splitOnWord: Bool
    let audioContext: Int32
    let threadCount: Int32
    let suppressNonSpeechTokens: Bool
    let temperature: Float
    let decodingProfile: LocalDecodingProfile

    var samplingStrategy: WhisperCppSamplingStrategy {
        switch decodingProfile {
        case .standard:
            return .greedy
        case .maximumQuality:
            return .beamSearch
        }
    }

    static func resolve(
        sampleCount: Int,
        sampleRate: Double = defaultSampleRate,
        isWarmup: Bool = false,
        includeTimestamps: Bool = false,
        decodingProfile: LocalDecodingProfile = .standard,
        processorCount: Int = ProcessInfo.processInfo.processorCount,
        audioContext: Int32 = 0
    ) -> WhisperCppDecodingOptions {
        let threadCount = defaultThreadCount(processorCount: processorCount)
        let effectiveDecodingProfile: LocalDecodingProfile = isWarmup ? .standard : decodingProfile

        guard !isWarmup else {
            return WhisperCppDecodingOptions(
                singleSegment: true,
                noTimestamps: true,
                tokenTimestamps: false,
                maxSegmentLength: 0,
                splitOnWord: false,
                audioContext: audioContext,
                threadCount: threadCount,
                suppressNonSpeechTokens: true,
                temperature: 0,
                decodingProfile: effectiveDecodingProfile
            )
        }

        guard sampleCount > 0, sampleRate > 0 else {
            return WhisperCppDecodingOptions(
                singleSegment: false,
                noTimestamps: true,
                tokenTimestamps: false,
                maxSegmentLength: 0,
                splitOnWord: false,
                audioContext: audioContext,
                threadCount: threadCount,
                suppressNonSpeechTokens: true,
                temperature: 0,
                decodingProfile: effectiveDecodingProfile
            )
        }

        let duration = Double(sampleCount) / sampleRate
        return WhisperCppDecodingOptions(
            singleSegment: !includeTimestamps && duration <= shortUtteranceMaximumDuration,
            noTimestamps: !includeTimestamps,
            tokenTimestamps: includeTimestamps,
            maxSegmentLength: includeTimestamps ? 80 : 0,
            splitOnWord: includeTimestamps,
            audioContext: audioContext,
            threadCount: threadCount,
            suppressNonSpeechTokens: true,
            temperature: 0,
            decodingProfile: effectiveDecodingProfile
        )
    }

    func timings(
        elapsedMilliseconds: Double,
        sampleCount: Int
    ) -> WhisperCppTimings {
        WhisperCppTimings(
            elapsedMilliseconds: elapsedMilliseconds,
            sampleCount: sampleCount,
            threadCount: threadCount,
            audioContext: audioContext,
            singleSegment: singleSegment,
            noTimestamps: noTimestamps,
            tokenTimestamps: tokenTimestamps,
            maxSegmentLength: maxSegmentLength,
            decodingProfile: decodingProfile
        )
    }

    static func defaultThreadCount(processorCount: Int) -> Int32 {
        Int32(max(1, min(4, processorCount - 2)))
    }
}

nonisolated struct WhisperCppBenchmarkConfiguration: Equatable, Identifiable {
    let threadCount: Int32
    let audioContext: Int32
    let language: String

    var id: String {
        "\(threadCount)-\(audioContext)-\(language)"
    }

    var displayName: String {
        "threads=\(threadCount), audio_ctx=\(audioContext), language=\(language)"
    }
}

nonisolated struct WhisperCppBenchmarkResult: Equatable {
    let configuration: WhisperCppBenchmarkConfiguration
    let elapsedSeconds: TimeInterval
    let timings: WhisperCppTimings?
    let textLength: Int
}

nonisolated enum WhisperCppBenchmarkPlan {
    static func configurations(
        processorCount: Int = ProcessInfo.processInfo.processorCount,
        preferredLanguage: String
    ) -> [WhisperCppBenchmarkConfiguration] {
        let maxThreads = Int(WhisperCppDecodingOptions.defaultThreadCount(processorCount: processorCount))
        let threadCounts = [maxThreads]
        let audioContexts: [Int32] = [0]
        let languages = normalizedLanguages(preferredLanguage)

        return threadCounts.flatMap { threadCount in
            audioContexts.flatMap { audioContext in
                languages.map { language in
                    WhisperCppBenchmarkConfiguration(
                        threadCount: Int32(threadCount),
                        audioContext: audioContext,
                        language: language
                    )
                }
            }
        }
    }

    private static func normalizedLanguages(_ preferredLanguage: String) -> [String] {
        let normalized = preferredLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized != "auto" else {
            return ["auto"]
        }
        return [normalized, "auto"]
    }
}
