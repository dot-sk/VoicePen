import Foundation

nonisolated struct WhisperCppDecodingOptions: Equatable {
    static let defaultSampleRate: Double = 16_000
    static let shortUtteranceMaximumDuration: TimeInterval = 10

    let singleSegment: Bool

    static func resolve(
        sampleCount: Int,
        sampleRate: Double = defaultSampleRate,
        isWarmup: Bool = false
    ) -> WhisperCppDecodingOptions {
        guard !isWarmup else {
            return WhisperCppDecodingOptions(singleSegment: true)
        }

        guard sampleCount > 0, sampleRate > 0 else {
            return WhisperCppDecodingOptions(singleSegment: false)
        }

        let duration = Double(sampleCount) / sampleRate
        return WhisperCppDecodingOptions(
            singleSegment: duration <= shortUtteranceMaximumDuration
        )
    }
}
