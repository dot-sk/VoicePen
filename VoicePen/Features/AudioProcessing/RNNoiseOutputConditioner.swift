import Foundation

nonisolated struct RNNoiseOutputConditioningResult: Equatable, Sendable {
    let samples: [Float]
    let inputPeak: Float
    let outputPeak: Float
    let attenuationApplied: Bool
}

nonisolated enum RNNoiseOutputConditioner {
    static let headroomPeak: Float = 0.95

    static func condition(_ samples: [Float]) throws -> RNNoiseOutputConditioningResult {
        var inputPeak: Float = 0
        for sample in samples {
            guard sample.isFinite else {
                throw RNNoiseOutputConditionerError.nonFiniteSample
            }
            inputPeak = max(inputPeak, abs(sample))
        }

        guard inputPeak > 1 else {
            return RNNoiseOutputConditioningResult(
                samples: samples,
                inputPeak: inputPeak,
                outputPeak: inputPeak,
                attenuationApplied: false
            )
        }

        let gain = headroomPeak / inputPeak
        let conditionedSamples = samples.map { $0 * gain }
        guard
            conditionedSamples.allSatisfy(\.isFinite),
            let outputPeak = conditionedSamples.map({ abs($0) }).max(),
            outputPeak <= 1
        else {
            throw RNNoiseOutputConditionerError.couldNotConditionOutput
        }

        return RNNoiseOutputConditioningResult(
            samples: conditionedSamples,
            inputPeak: inputPeak,
            outputPeak: outputPeak,
            attenuationApplied: true
        )
    }
}

nonisolated enum RNNoiseOutputConditionerError: LocalizedError, Equatable {
    case nonFiniteSample
    case couldNotConditionOutput

    var errorDescription: String? {
        switch self {
        case .nonFiniteSample:
            return "RNNoise output contains a non-finite sample."
        case .couldNotConditionOutput:
            return "RNNoise output could not be conditioned into the supported range."
        }
    }
}
