import Foundation

nonisolated enum AudioSilenceTrimmer {
    static let defaultThreshold: Float = 0.008
    static let defaultPaddingDuration: TimeInterval = 0.15
    static let minimumTrimmedDuration: TimeInterval = 0.1

    static func trimRange(
        samples: [Float],
        sampleRate: Double,
        threshold: Float = defaultThreshold,
        paddingDuration: TimeInterval = defaultPaddingDuration,
        minimumTrimmedDuration: TimeInterval = minimumTrimmedDuration
    ) -> Range<Int>? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }

        guard let audibleRange = audibleRange(samples: samples, threshold: threshold) else {
            return nil
        }

        let paddingFrames = max(0, Int(sampleRate * paddingDuration))
        let lowerBound = max(0, audibleRange.lowerBound - paddingFrames)
        let upperBound = min(samples.count, audibleRange.upperBound + paddingFrames)
        guard lowerBound < upperBound else { return nil }

        let trimmedFrames = samples.count - (upperBound - lowerBound)
        let minimumTrimmedFrames = Int(sampleRate * minimumTrimmedDuration)
        guard trimmedFrames >= minimumTrimmedFrames else {
            return nil
        }

        return lowerBound..<upperBound
    }

    static func containsSpeech(
        samples: [Float],
        threshold: Float = defaultThreshold
    ) -> Bool {
        audibleRange(samples: samples, threshold: threshold) != nil
    }

    private static func audibleRange(samples: [Float], threshold: Float) -> Range<Int>? {
        guard let firstAudibleIndex = samples.firstIndex(where: { abs($0) >= threshold }),
              let lastAudibleIndex = samples.lastIndex(where: { abs($0) >= threshold }) else {
            return nil
        }

        return firstAudibleIndex..<(lastAudibleIndex + 1)
    }
}
