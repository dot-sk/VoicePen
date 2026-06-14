enum VoicePenMenuStatusAppState: Equatable {
    case starting
    case ready
    case meetingRecording
    case meetingProcessing
    case downloadingModel(progress: Double?)
    case preparingModel(String)
    case missingMicrophonePermission
    case missingAccessibilityPermission
    case missingSystemAudioPermission
    case missingModel
    case error(String)
}

enum VoicePenStatusMenuAction: Equatable {
    case dictationStart(hint: String)
    case dictationStop
    case dictationCancel
    case meetingStart
    case meetingStop
    case meetingCancel
    case recognitionLanguage
    case copyLastTranscription
    case insertLastTranscription
    case openVoicePenWindow
    case openConfigFile
    case checkForUpdates
    case quit
    case separator
}

struct VoicePenStatusMenuModel: Equatable {
    let showsStartDictation: Bool
    let showsStopDictation: Bool
    let showsCancelTranscription: Bool
    let showsStartMeetingRecording: Bool
    let showsStopMeetingRecording: Bool
    let hasLatestTranscriptionText: Bool
    let pushToTalkHotkeyHint: String
    let selectedTranscriptionLanguageCode: String
    let languageOptions: [VoicePenMenuLanguageOption]
    let menuBarSystemImage: String
    let usesMeetingRecordingTint: Bool

    init(
        appState: VoicePenMenuStatusAppState,
        showsStartDictation: Bool,
        showsStopDictation: Bool,
        showsCancelTranscription: Bool,
        showsStartMeetingRecording: Bool,
        showsStopMeetingRecording: Bool,
        hasLatestTranscriptionText: Bool,
        pushToTalkHotkeyHint: String,
        selectedTranscriptionLanguageCode: String,
        languageOptions: [VoicePenMenuLanguageOption],
        isDictationStarting: Bool,
        isDictationRecording: Bool,
        isDictationTranscribing: Bool
    ) {
        self.showsStartDictation = showsStartDictation
        self.showsStopDictation = showsStopDictation
        self.showsCancelTranscription = showsCancelTranscription
        self.showsStartMeetingRecording = showsStartMeetingRecording
        self.showsStopMeetingRecording = showsStopMeetingRecording
        self.hasLatestTranscriptionText = hasLatestTranscriptionText
        self.pushToTalkHotkeyHint = pushToTalkHotkeyHint
        self.selectedTranscriptionLanguageCode = selectedTranscriptionLanguageCode
        self.languageOptions = languageOptions
        self.menuBarSystemImage = Self.menuBarSystemImage(
            appState: appState,
            isDictationStarting: isDictationStarting,
            isDictationRecording: isDictationRecording,
            isDictationTranscribing: isDictationTranscribing
        )
        self.usesMeetingRecordingTint = appState == .meetingRecording
    }

    var showsDictationCommands: Bool {
        showsStartDictation || showsStopDictation || showsCancelTranscription
    }

    var showsMeetingCommands: Bool {
        showsStartMeetingRecording || showsStopMeetingRecording
    }

    var menuActions: [VoicePenStatusMenuAction] {
        var items: [VoicePenStatusMenuAction] = []

        if showsDictationCommands {
            if showsStartDictation {
                items.append(.dictationStart(hint: pushToTalkHotkeyHint))
            }
            if showsStopDictation {
                items.append(.dictationStop)
            }
            if showsCancelTranscription {
                items.append(.dictationCancel)
            }
            items.append(.separator)
        }

        if showsMeetingCommands {
            if showsStartMeetingRecording {
                items.append(.meetingStart)
            }
            if showsStopMeetingRecording {
                items.append(.meetingStop)
                items.append(.meetingCancel)
            }
            items.append(.separator)
        }

        items.append(.recognitionLanguage)

        if hasLatestTranscriptionText {
            items.append(.separator)
            items.append(.copyLastTranscription)
            items.append(.insertLastTranscription)
        }

        items.append(.separator)
        items.append(.openVoicePenWindow)
        items.append(.openConfigFile)
        items.append(.checkForUpdates)
        items.append(.separator)
        items.append(.quit)

        return items
    }

    private static func menuBarSystemImage(
        appState: VoicePenMenuStatusAppState,
        isDictationStarting: Bool,
        isDictationRecording: Bool,
        isDictationTranscribing: Bool
    ) -> String {
        if appState == .meetingRecording || isDictationStarting || isDictationRecording {
            "record.circle.fill"
        } else if isDictationTranscribing {
            "waveform"
        } else if showsProcessingIcon(for: appState) {
            "waveform"
        } else if showsWarningIcon(for: appState) {
            "exclamationmark.triangle.fill"
        } else {
            "mic.fill"
        }
    }

    private static func showsProcessingIcon(for appState: VoicePenMenuStatusAppState) -> Bool {
        switch appState {
        case .meetingProcessing, .downloadingModel, .preparingModel:
            return true
        default:
            return false
        }
    }

    private static func showsWarningIcon(for appState: VoicePenMenuStatusAppState) -> Bool {
        switch appState {
        case .missingMicrophonePermission, .missingAccessibilityPermission,
            .missingSystemAudioPermission, .missingModel, .error:
            return true
        default:
            return false
        }
    }
}

struct VoicePenMenuLanguageOption: Equatable {
    let code: String
    let name: String
}
