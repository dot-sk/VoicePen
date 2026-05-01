import Foundation

nonisolated struct VoicePipelineTimings: Codable, Equatable, Sendable {
    var recording: TimeInterval?
    var preprocessing: TimeInterval?
    var transcription: TimeInterval?
    var normalization: TimeInterval?
    var insertion: TimeInterval?

    init(
        recording: TimeInterval? = nil,
        preprocessing: TimeInterval? = nil,
        transcription: TimeInterval? = nil,
        normalization: TimeInterval? = nil,
        insertion: TimeInterval? = nil
    ) {
        self.recording = recording
        self.preprocessing = preprocessing
        self.transcription = transcription
        self.normalization = normalization
        self.insertion = insertion
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
