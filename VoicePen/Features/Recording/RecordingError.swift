import Foundation

enum RecordingError: LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case couldNotStart
    case missingOutputFile

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            "VoicePen is already recording."
        case .notRecording:
            "VoicePen is not recording."
        case .couldNotStart:
            "VoicePen could not start recording."
        case .missingOutputFile:
            "VoicePen could not find the recorded audio file."
        }
    }
}
