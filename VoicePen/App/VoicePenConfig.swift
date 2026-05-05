import Foundation

nonisolated enum VoicePenConfig {
    static let modelDisplayName = "Whisper large-v3 turbo q5_0"
    static let modelId = "ggml-large-v3-turbo-q5_0"
    static let modelVersion = "large-v3-turbo-q5_0"
    static let modelSizeLabel = "1.7 GB"
    static let modelSourceRepo = "ggerganov/whisper.cpp"
    static let defaultLanguage = "auto"
    static let minimumRecordingDuration: TimeInterval = 0.4
    static let clipboardRestoreDelay: TimeInterval = 0.7
    static let glossaryLimit = 40
    static let shortRecordingPromptMaximumDuration: TimeInterval = 10
    static let defaultHotkeyHoldDuration: TimeInterval = 0.35
    static let accessibilityPermissionPollInterval: Duration = .seconds(1)
    static let historyCopyFeedbackDuration: Duration = .milliseconds(1_400)
    static let recordingLevelRefreshInterval: Duration = .milliseconds(80)
    static let dictationProcessingTimeout: Duration = .seconds(30)
    static let modelDownloadTimeout: Duration = .seconds(3_600)
    static let modelWarmupTimeout: Duration = .seconds(30)
    static let meetingCaptureStartTimeout: Duration = .seconds(10)
    static let meetingProcessingTimeout: Duration = .seconds(1_800)
    static let meetingChunkProcessingTimeout: Duration = .seconds(180)
    static var appSupportFolderName: String {
        let configuredName = Bundle.main.object(forInfoDictionaryKey: "VPApplicationSupportFolderName") as? String
        let trimmedName = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedName, !trimmedName.isEmpty else {
            return "VoicePen"
        }
        return trimmedName
    }
    static let minimumSpeechSignalDuration: TimeInterval = 0.16
}
