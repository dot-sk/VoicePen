import Foundation

nonisolated enum VoicePenConfig {
    static let modelDisplayName = "Fast Multilingual (Whisper Q5_0)"
    static let modelId = "ggml-large-v3-turbo-q5_0"
    static let modelVersion = "large-v3-turbo-q5_0"
    static let modelSizeLabel = "1.7 GB"
    static let modelSourceRepo = "ggerganov/whisper.cpp"
    static let defaultLanguage = "auto"
    static let minimumRecordingDuration: TimeInterval = 0.4
    static let clipboardRestoreDelay: TimeInterval = 0.7
    static let glossaryLimit = 40
    static let shortRecordingPromptMaximumDuration: TimeInterval = 10
    static let defaultHotkeyHoldDuration: TimeInterval = 0.15
    static let minimumHotkeyHoldDuration: TimeInterval = 0.1
    static let maximumHotkeyHoldDuration: TimeInterval = 0.5
    static let accessibilityPermissionPollInterval: Duration = .seconds(1)
    static let historyCopyFeedbackDuration: Duration = .milliseconds(1_400)
    static let recordingLevelRefreshInterval: Duration = .milliseconds(80)
    static let dictationProcessingTimeout: Duration = .seconds(30)
    static let modelDownloadTimeout: Duration = .seconds(3_600)
    static let modelWarmupTimeout: Duration = .seconds(30)
    static let meetingCaptureStartTimeout: Duration = .seconds(10)
    static let meetingMaximumRecordingDuration: TimeInterval = 120 * 60
    static let meetingProcessingTimeout: Duration = .seconds(1_800)
    static let meetingChunkProcessingTimeout: Duration = .seconds(180)
    static let meetingRecoveryAudioTTL: TimeInterval = 7 * 24 * 60 * 60
    static var modesFeatureEnabled: Bool {
        featureFlag(
            environmentKey: "VOICEPEN_ENABLE_MODES",
            infoDictionaryKey: "VPEnableModes"
        )
    }
    static var aiFeatureEnabled: Bool {
        featureFlag(
            environmentKey: "VOICEPEN_ENABLE_AI",
            infoDictionaryKey: "VPEnableAI"
        )
    }
    static var appSupportFolderName: String {
        let configuredName = Bundle.main.object(forInfoDictionaryKey: "VPApplicationSupportFolderName") as? String
        let trimmedName = configuredName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedName, !trimmedName.isEmpty else {
            return "VoicePen"
        }
        return trimmedName
    }
    static var appVersion: String {
        let shortVersion = trimmedBundleString("CFBundleShortVersionString")
        let buildVersion = trimmedBundleString("CFBundleVersion")

        switch (shortVersion, buildVersion) {
        case let (shortVersion?, buildVersion?) where shortVersion != buildVersion:
            return "\(shortVersion) (\(buildVersion))"
        case let (shortVersion?, _):
            return shortVersion
        case let (_, buildVersion?):
            return buildVersion
        case (nil, nil):
            return "Unknown"
        }
    }
    static let minimumSpeechSignalDuration: TimeInterval = 0.16

    static func featureFlag(
        environmentKey: String,
        infoDictionaryKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionaryValue: Any? = nil
    ) -> Bool {
        if let rawValue = environment[environmentKey] {
            return booleanFeatureFlagValue(rawValue)
        }

        if let boolean = infoDictionaryValue as? Bool {
            return boolean
        }

        if let string = infoDictionaryValue as? String {
            return booleanFeatureFlagValue(string)
        }

        if infoDictionaryValue == nil,
            let bundleValue = Bundle.main.object(forInfoDictionaryKey: infoDictionaryKey)
        {
            return featureFlag(
                environmentKey: environmentKey,
                infoDictionaryKey: infoDictionaryKey,
                environment: environment,
                infoDictionaryValue: bundleValue
            )
        }

        return false
    }

    private static func booleanFeatureFlagValue(_ rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on", "enabled":
            return true
        default:
            return false
        }
    }

    private static func trimmedBundleString(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
