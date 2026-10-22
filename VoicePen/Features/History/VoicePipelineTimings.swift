import Foundation

nonisolated struct VoicePipelineTimings: Codable, Equatable, Sendable {
    var recording: TimeInterval?
    var preprocessing: TimeInterval?
    var transcription: TimeInterval?
    var normalization: TimeInterval?
    var insertion: TimeInterval?
    var recordingFinalization: TimeInterval?
    var modelReadiness: TimeInterval?
    var releaseToInsertion: TimeInterval?

    init(
        recording: TimeInterval? = nil,
        preprocessing: TimeInterval? = nil,
        transcription: TimeInterval? = nil,
        normalization: TimeInterval? = nil,
        insertion: TimeInterval? = nil,
        recordingFinalization: TimeInterval? = nil,
        modelReadiness: TimeInterval? = nil,
        releaseToInsertion: TimeInterval? = nil
    ) {
        self.recording = recording
        self.preprocessing = preprocessing
        self.transcription = transcription
        self.normalization = normalization
        self.insertion = insertion
        self.recordingFinalization = recordingFinalization
        self.modelReadiness = modelReadiness
        self.releaseToInsertion = releaseToInsertion
    }

    var measuredProcessingDuration: TimeInterval {
        [
            preprocessing,
            transcription,
            normalization,
            insertion
        ]
        .compactMap(\.self)
        .reduce(0, +)
    }
}
