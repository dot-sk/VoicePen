import Foundation

nonisolated enum AudioSilenceTrimmer {
    static let defaultThreshold: Float = 0.008
    static let defaultPaddingDuration: TimeInterval = 0.3
    static let minimumTrimmedDuration: TimeInterval = 0.1
    static let defaultAnalysisWindowDuration: TimeInterval = 0.03

    static func trimRange(
        samples: [Float],
        sampleRate: Double,
        threshold: Float = defaultThreshold,
        paddingDuration: TimeInterval = defaultPaddingDuration,
        minimumTrimmedDuration: TimeInterval = minimumTrimmedDuration,
        minimumSpeechDuration: TimeInterval = 0
    ) -> Range<Int>? {
        guard !samples.isEmpty, sampleRate > 0 else { return nil }

        guard let audibleRange = audibleRange(
            samples: samples,
            sampleRate: sampleRate,
            threshold: threshold,
            minimumSpeechDuration: minimumSpeechDuration
        ) else {
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
        sampleRate: Double = 1,
        threshold: Float = defaultThreshold,
        minimumSpeechDuration: TimeInterval = 0
    ) -> Bool {
        audibleRange(
            samples: samples,
            sampleRate: sampleRate,
            threshold: threshold,
            minimumSpeechDuration: minimumSpeechDuration
        ) != nil
    }

    private static func audibleRange(
        samples: [Float],
        sampleRate: Double,
        threshold: Float,
        minimumSpeechDuration: TimeInterval
    ) -> Range<Int>? {
        guard !samples.isEmpty, sampleRate > 0 else {
            return nil
        }

        let minimumSpeechFrames = max(1, Int(sampleRate * minimumSpeechDuration))
        let windowSize = max(1, Int(sampleRate * defaultAnalysisWindowDuration))
        let hopSize = max(1, windowSize / 2)

        var firstAudibleIndex: Int?
        var lastAudibleIndex: Int?
        var currentRunStart: Int?
        var longestRunFrames = 0

        var start = 0
        while start < samples.count {
            let end = min(samples.count, start + windowSize)
            let window = samples[start..<end]
            let meanSquare = window.reduce(Float(0)) { partial, sample in
                partial + sample * sample
            } / Float(max(1, window.count))
            let rootMeanSquare = sqrt(meanSquare)

            if rootMeanSquare >= threshold {
                firstAudibleIndex = firstAudibleIndex ?? start
                lastAudibleIndex = end
                currentRunStart = currentRunStart ?? start
                longestRunFrames = max(longestRunFrames, end - (currentRunStart ?? start))
            } else {
                currentRunStart = nil
            }

            start += hopSize
        }

        guard let firstAudibleIndex,
              let lastAudibleIndex,
              longestRunFrames >= minimumSpeechFrames else {
            return nil
        }

        return firstAudibleIndex..<lastAudibleIndex
    }
}
