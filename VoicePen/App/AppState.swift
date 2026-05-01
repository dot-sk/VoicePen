import Foundation

enum AppState: Equatable {
    case starting
    case ready
    case recording
    case transcribing
    case downloadingModel(progress: Double?)
    case preparingModel(String)
    case missingMicrophonePermission
    case missingAccessibilityPermission
    case missingModel
    case error(String)

    var menuTitle: String {
        switch self {
        case .starting:
            return "Starting"
        case .ready:
            return "Ready"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case let .downloadingModel(progress):
            if let progress {
                return "Downloading model \(Int(progress * 100))%"
            }
            return "Downloading model"
        case let .preparingModel(message):
            return message
        case .missingMicrophonePermission:
            return "Microphone permission missing"
        case .missingAccessibilityPermission:
            return "Accessibility permission missing"
        case .missingModel:
            return "Model missing"
        case .error:
            return "Error"
        }
    }
}
