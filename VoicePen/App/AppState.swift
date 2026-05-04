import Foundation

enum AppState: Equatable {
    case starting
    case ready
    case recording
    case transcribing
    case meetingRecording
    case meetingPaused
    case meetingProcessing
    case downloadingModel(progress: Double?)
    case preparingModel(String)
    case missingMicrophonePermission
    case missingAccessibilityPermission
    case missingSystemAudioPermission
    case missingModel
    case error(String)

    var canStartMeetingRecording: Bool {
        switch self {
        case .ready, .missingModel, .missingAccessibilityPermission:
            return true
        default:
            return false
        }
    }

    var isMeetingCaptureActive: Bool {
        switch self {
        case .meetingRecording, .meetingPaused:
            return true
        default:
            return false
        }
    }

    var showsMeetingRecordingPanel: Bool {
        isMeetingCaptureActive || self == .meetingProcessing
    }

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
        case .meetingRecording:
            return "Meeting recording"
        case .meetingPaused:
            return "Meeting paused"
        case .meetingProcessing:
            return "Processing meeting"
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
        case .missingSystemAudioPermission:
            return "System audio permission missing"
        case .missingModel:
            return "Model missing"
        case .error:
            return "Error"
        }
    }
}
