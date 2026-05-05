import Foundation

enum TranscriptionError: LocalizedError, Equatable {
    case modelMissing(expectedPaths: [String])
    case modelLoadFailed(String)
    case accelerationUnavailable(modelId: String, message: String)
    case transcriptionFailed(String)
    case transcriptionTimedOut
    case modelWarmupTimedOut
    case emptyResult
    case unsupportedModel(String)

    var errorDescription: String? {
        switch self {
        case let .modelMissing(expectedPaths):
            """
            VoicePen could not find the local transcription model.
            Expected:
            \(expectedPaths.joined(separator: "\n"))
            """
        case let .modelLoadFailed(message):
            "VoicePen could not load the transcription model: \(message)"
        case let .accelerationUnavailable(modelId, message):
            "VoicePen cannot run \(modelId) without Core ML acceleration: \(message)"
        case let .transcriptionFailed(message):
            "VoicePen transcription failed: \(message)"
        case .transcriptionTimedOut:
            "VoicePen transcription timed out. Please try again."
        case .modelWarmupTimedOut:
            "VoicePen model warmup timed out. Recording can still retry the model."
        case .emptyResult:
            "VoicePen received an empty transcription."
        case let .unsupportedModel(modelId):
            "VoicePen does not know how to use transcription model: \(modelId)."
        }
    }

    var shortMessage: String {
        switch self {
        case .modelMissing:
            "Model missing"
        case .modelLoadFailed:
            "Model load failed"
        case .accelerationUnavailable:
            "Acceleration unavailable"
        case .transcriptionFailed:
            "Transcription failed"
        case .transcriptionTimedOut:
            "Transcription timed out"
        case .modelWarmupTimedOut:
            "Model warmup timed out"
        case .emptyResult:
            "Empty transcription"
        case .unsupportedModel:
            "Unsupported model"
        }
    }
}
