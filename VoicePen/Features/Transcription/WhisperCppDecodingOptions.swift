import Foundation

nonisolated struct WhisperCppDecodingOptions: Equatable {
    static let defaultSampleRate: Double = 16_000
    static let shortUtteranceMaximumDuration: TimeInterval = 10

    let singleSegment: Bool
    let noTimestamps: Bool
    let audioContext: Int32
    let threadCount: Int32

    static func resolve(
        sampleCount: Int,
        sampleRate: Double = defaultSampleRate,
        isWarmup: Bool = false,
        processorCount: Int = ProcessInfo.processInfo.processorCount,
        audioContext: Int32 = 0
    ) -> WhisperCppDecodingOptions {
        let threadCount = defaultThreadCount(processorCount: processorCount)

        guard !isWarmup else {
            return WhisperCppDecodingOptions(
                singleSegment: true,
                noTimestamps: true,
                audioContext: audioContext,
                threadCount: threadCount
            )
        }

        guard sampleCount > 0, sampleRate > 0 else {
            return WhisperCppDecodingOptions(
                singleSegment: false,
                noTimestamps: true,
                audioContext: audioContext,
                threadCount: threadCount
            )
        }

        let duration = Double(sampleCount) / sampleRate
        return WhisperCppDecodingOptions(
            singleSegment: duration <= shortUtteranceMaximumDuration,
            noTimestamps: true,
            audioContext: audioContext,
            threadCount: threadCount
        )
    }

    static func defaultThreadCount(processorCount: Int) -> Int32 {
        Int32(max(1, min(8, processorCount - 2)))
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
        let threadCounts = [4, 6, 8]
            .filter { $0 <= maxThreads }
            .ifEmpty([maxThreads])
        let audioContexts: [Int32] = [0, 768]
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

nonisolated private extension Array {
    func ifEmpty(_ fallback: @autoclosure () -> [Element]) -> [Element] {
        isEmpty ? fallback() : self
    }
}
