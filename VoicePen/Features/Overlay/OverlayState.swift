import Foundation

enum OverlayState: Equatable {
    case hidden
    case recording(startedAt: Date, level: Double?)
    case transcribing(stage: TranscriptionStage, progress: Double?)
    case error(message: String)
    case done(message: String)
}

enum TranscriptionStage: String, Equatable {
    case preparingAudio = "Preparing"
    case loadingModel = "Loading model"
    case transcribing = "Transcribing"
    case normalizing = "Normalizing"
    case pasting = "Pasting"
}

extension OverlayState {
    var isInteractive: Bool {
        if case .transcribing = self {
            return true
        }
        return false
    }
}
