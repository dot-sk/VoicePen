import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var transcriptionLanguage: String
    @Published private(set) var selectedModelId: String
    @Published private(set) var speechPreprocessingMode: SpeechPreprocessingMode
    @Published private(set) var hotkeyPreference: HotkeyPreference
    @Published private(set) var hotkeyHoldDuration: TimeInterval
    @Published private(set) var boostDictationInputGain: Bool
    @Published private(set) var meetingVoiceLevelingEnabled: Bool
    @Published private(set) var saveDictationAudioEnabled: Bool
    @Published private(set) var saveMeetingAudioEnabled: Bool
    @Published private(set) var savedAudioStorageLimitGB: Int
    @Published private(set) var meetingTranscriptTimecodesEnabled: Bool
    @Published private(set) var meetingDiarizationEnabled: Bool
    @Published private(set) var meetingSystemAudioSourceMode: MeetingSystemAudioSourceMode
    @Published private(set) var meetingAudioAppSelections: [MeetingAudioAppSelection]
    @Published private(set) var appAppearanceMode: AppAppearanceMode
    @Published private(set) var openAtLogin: Bool
    @Published private(set) var developerModeOverride: DeveloperMode?
    @Published private(set) var hasAcknowledgedMeetingRecordingConsent: Bool

    private let databaseURL: URL
    private let fileManager: FileManager

    init(databaseURL: URL, fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.transcriptionLanguage = VoicePenConfig.defaultLanguage
        self.selectedModelId = VoicePenConfig.modelId
        self.speechPreprocessingMode = .off
        self.hotkeyPreference = .option
        self.hotkeyHoldDuration = VoicePenConfig.defaultHotkeyHoldDuration
        self.boostDictationInputGain = true
        self.meetingVoiceLevelingEnabled = true
        self.saveDictationAudioEnabled = false
        self.saveMeetingAudioEnabled = false
        self.savedAudioStorageLimitGB = VoicePenConfig.defaultSavedAudioStorageLimitGB
        self.meetingTranscriptTimecodesEnabled = true
        self.meetingDiarizationEnabled = false
        self.meetingSystemAudioSourceMode = .all
        self.meetingAudioAppSelections = []
        self.appAppearanceMode = .system
        self.openAtLogin = false
        self.developerModeOverride = nil
        self.hasAcknowledgedMeetingRecordingConsent = false
    }

    func load(defaultModelId: String) throws {
        let values = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            let language = try fetchValue(forKey: Self.languageKey, from: database) ?? VoicePenConfig.defaultLanguage
            let modelId = try fetchValue(forKey: Self.selectedModelKey, from: database) ?? defaultModelId
            let preprocessing = try fetchValue(forKey: Self.speechPreprocessingKey, from: database) ?? SpeechPreprocessingMode.off.rawValue
            let hotkey = try fetchValue(forKey: Self.hotkeyPreferenceKey, from: database) ?? HotkeyPreference.option.rawValue
            let holdDuration =
                try fetchValue(forKey: Self.hotkeyHoldDurationKey, from: database)
                ?? String(VoicePenConfig.defaultHotkeyHoldDuration)
            let boostDictationInputGain =
                try fetchValue(forKey: Self.boostDictationInputGainKey, from: database)
                ?? "true"
            let meetingVoiceLeveling =
                try fetchValue(forKey: Self.meetingVoiceLevelingEnabledKey, from: database)
                ?? "true"
            let saveDictationAudio =
                try fetchValue(forKey: Self.saveDictationAudioEnabledKey, from: database)
                ?? "false"
            let saveMeetingAudio =
                try fetchValue(forKey: Self.saveMeetingAudioEnabledKey, from: database)
                ?? "false"
            let savedAudioStorageLimitGB =
                try fetchValue(forKey: Self.savedAudioStorageLimitGBKey, from: database)
                ?? String(VoicePenConfig.defaultSavedAudioStorageLimitGB)
            let meetingTranscriptTimecodes =
                try fetchValue(forKey: Self.meetingTranscriptTimecodesEnabledKey, from: database)
                ?? "true"
            let meetingDiarization =
                try fetchValue(forKey: Self.meetingDiarizationEnabledKey, from: database)
                ?? "false"
            let meetingSystemAudioSourceMode =
                try fetchValue(forKey: Self.meetingSystemAudioSourceModeKey, from: database)
                ?? MeetingSystemAudioSourceMode.all.rawValue
            let meetingAudioAppSelections = try fetchValue(forKey: Self.meetingAudioAppSelectionsKey, from: database)
            let appAppearanceMode =
                try fetchValue(forKey: Self.appAppearanceModeKey, from: database)
                ?? AppAppearanceMode.system.rawValue
            let openAtLogin = try fetchValue(forKey: Self.openAtLoginKey, from: database) ?? "false"
            let developerModeOverride = try fetchValue(forKey: Self.developerModeOverrideKey, from: database)
            let meetingConsent = try fetchValue(forKey: Self.meetingConsentKey, from: database) ?? "false"
            return LoadedSettings(
                language: language,
                modelId: modelId,
                preprocessing: preprocessing,
                hotkey: hotkey,
                holdDuration: holdDuration,
                boostDictationInputGain: boostDictationInputGain,
                meetingVoiceLeveling: meetingVoiceLeveling,
                saveDictationAudio: saveDictationAudio,
                saveMeetingAudio: saveMeetingAudio,
                savedAudioStorageLimitGB: savedAudioStorageLimitGB,
                meetingTranscriptTimecodes: meetingTranscriptTimecodes,
                meetingDiarization: meetingDiarization,
                meetingSystemAudioSourceMode: meetingSystemAudioSourceMode,
                meetingAudioAppSelections: meetingAudioAppSelections,
                appAppearanceMode: appAppearanceMode,
                openAtLogin: openAtLogin,
                developerModeOverride: developerModeOverride,
                meetingConsent: meetingConsent
            )
        }
        transcriptionLanguage = Self.normalizeLanguage(values.language)
        selectedModelId = Self.normalizeModelId(values.modelId, fallback: defaultModelId)
        speechPreprocessingMode = Self.normalizeSpeechPreprocessingMode(values.preprocessing)
        hotkeyPreference = Self.normalizeHotkeyPreference(values.hotkey)
        hotkeyHoldDuration = Self.normalizeHotkeyHoldDuration(values.holdDuration)
        boostDictationInputGain = Self.normalizeBoolean(values.boostDictationInputGain)
        meetingVoiceLevelingEnabled = Self.normalizeBoolean(values.meetingVoiceLeveling)
        saveDictationAudioEnabled = Self.normalizeBoolean(values.saveDictationAudio)
        saveMeetingAudioEnabled = Self.normalizeBoolean(values.saveMeetingAudio)
        savedAudioStorageLimitGB = Self.normalizeSavedAudioStorageLimitGB(values.savedAudioStorageLimitGB)
        meetingTranscriptTimecodesEnabled = Self.normalizeBoolean(values.meetingTranscriptTimecodes)
        meetingDiarizationEnabled = Self.normalizeBoolean(values.meetingDiarization)
        meetingSystemAudioSourceMode = Self.normalizeMeetingSystemAudioSourceMode(values.meetingSystemAudioSourceMode)
        meetingAudioAppSelections = Self.normalizeMeetingAudioAppSelections(values.meetingAudioAppSelections)
        appAppearanceMode = Self.normalizeAppAppearanceMode(values.appAppearanceMode)
        openAtLogin = Self.normalizeBoolean(values.openAtLogin)
        developerModeOverride = Self.normalizeDeveloperModeOverride(values.developerModeOverride)
        hasAcknowledgedMeetingRecordingConsent = Self.normalizeBoolean(values.meetingConsent)
    }

    func updateTranscriptionLanguage(_ language: String) throws {
        let normalizedLanguage = Self.normalizeLanguage(language)
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(normalizedLanguage, forKey: Self.languageKey, in: database)
        }
        transcriptionLanguage = normalizedLanguage
    }

    func updateSelectedModelId(_ modelId: String) throws {
        let normalizedModelId = Self.normalizeModelId(modelId, fallback: selectedModelId)
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(normalizedModelId, forKey: Self.selectedModelKey, in: database)
        }
        selectedModelId = normalizedModelId
    }

    func updateSpeechPreprocessingMode(_ mode: SpeechPreprocessingMode) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(mode.rawValue, forKey: Self.speechPreprocessingKey, in: database)
        }
        speechPreprocessingMode = mode
    }

    func updateHotkeyPreference(_ preference: HotkeyPreference) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(preference.rawValue, forKey: Self.hotkeyPreferenceKey, in: database)
        }
        hotkeyPreference = preference
    }

    func updateHotkeyHoldDuration(_ duration: TimeInterval) throws {
        let normalizedDuration = Self.normalizeHotkeyHoldDuration(String(duration))
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(normalizedDuration), forKey: Self.hotkeyHoldDurationKey, in: database)
        }
        hotkeyHoldDuration = normalizedDuration
    }

    func updateBoostDictationInputGain(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.boostDictationInputGainKey, in: database)
        }
        boostDictationInputGain = isEnabled
    }

    func updateMeetingVoiceLevelingEnabled(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.meetingVoiceLevelingEnabledKey, in: database)
        }
        meetingVoiceLevelingEnabled = isEnabled
    }

    func updateSaveDictationAudioEnabled(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.saveDictationAudioEnabledKey, in: database)
        }
        saveDictationAudioEnabled = isEnabled
    }

    func updateSaveMeetingAudioEnabled(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.saveMeetingAudioEnabledKey, in: database)
        }
        saveMeetingAudioEnabled = isEnabled
    }

    func updateSavedAudioStorageLimitGB(_ limit: Int) throws {
        let normalizedLimit = Self.normalizeSavedAudioStorageLimitGB(String(limit))
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(normalizedLimit), forKey: Self.savedAudioStorageLimitGBKey, in: database)
        }
        savedAudioStorageLimitGB = normalizedLimit
    }

    func updateMeetingTranscriptTimecodesEnabled(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.meetingTranscriptTimecodesEnabledKey, in: database)
        }
        meetingTranscriptTimecodesEnabled = isEnabled
    }

    func updateMeetingDiarizationEnabled(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.meetingDiarizationEnabledKey, in: database)
        }
        meetingDiarizationEnabled = isEnabled
    }

    func updateMeetingSystemAudioSourceMode(_ mode: MeetingSystemAudioSourceMode) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(mode.rawValue, forKey: Self.meetingSystemAudioSourceModeKey, in: database)
        }
        meetingSystemAudioSourceMode = mode
    }

    func updateMeetingAudioAppSelections(_ selections: [MeetingAudioAppSelection]) throws {
        let normalizedSelections = Self.normalizeMeetingAudioAppSelections(selections)
        let encodedSelections = try Self.encodeMeetingAudioAppSelections(normalizedSelections)
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(encodedSelections, forKey: Self.meetingAudioAppSelectionsKey, in: database)
        }
        meetingAudioAppSelections = normalizedSelections
    }

    func updateOpenAtLogin(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.openAtLoginKey, in: database)
        }
        openAtLogin = isEnabled
    }

    func updateAppAppearanceMode(_ mode: AppAppearanceMode) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(mode.rawValue, forKey: Self.appAppearanceModeKey, in: database)
        }
        appAppearanceMode = mode
    }

    func updateDeveloperModeOverride(_ mode: DeveloperMode) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(mode.rawValue, forKey: Self.developerModeOverrideKey, in: database)
        }
        developerModeOverride = mode
    }

    func updateMeetingRecordingConsentAcknowledged(_ isAcknowledged: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isAcknowledged), forKey: Self.meetingConsentKey, in: database)
        }
        hasAcknowledgedMeetingRecordingConsent = isAcknowledged
    }

    private func withDatabase<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        let database = try SQLiteConnection.open(
            at: databaseURL,
            fileManager: fileManager,
            makeError: AppSettingsStoreError.sqlite
        )
        return try body(database)
    }

    private func fetchValue(forKey key: String, from database: SQLiteConnection) throws -> String? {
        let statement = try database.prepare("SELECT value FROM app_settings WHERE key = ? LIMIT 1;")

        statement.bindText(key, at: 1)

        guard try statement.step() == .row else {
            return nil
        }

        return statement.optionalString(at: 0)
    }

    private func setValue(_ value: String, forKey key: String, in database: SQLiteConnection) throws {
        let statement = try database.prepare("INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?);")

        statement.bindText(key, at: 1)
        statement.bindText(value, at: 2)
        try statement.stepDone()
    }

    private static func normalizeLanguage(_ language: String) -> String {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return supportedLanguages.contains(where: { $0.code == normalizedLanguage })
            ? normalizedLanguage
            : VoicePenConfig.defaultLanguage
    }

    private static func normalizeModelId(_ modelId: String, fallback: String) -> String {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedModelId.isEmpty ? fallback : normalizedModelId
    }

    private static func normalizeSpeechPreprocessingMode(_ mode: String) -> SpeechPreprocessingMode {
        SpeechPreprocessingMode(rawValue: mode.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .off
    }

    private static func normalizeHotkeyPreference(_ preference: String) -> HotkeyPreference {
        HotkeyPreference(rawValue: preference.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .option
    }

    private static func normalizeHotkeyHoldDuration(_ duration: String) -> TimeInterval {
        guard let value = Double(duration.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return VoicePenConfig.defaultHotkeyHoldDuration
        }

        return min(
            max(value, VoicePenConfig.minimumHotkeyHoldDuration),
            VoicePenConfig.maximumHotkeyHoldDuration
        )
    }

    private static func normalizeBoolean(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
    }

    private static func normalizeSavedAudioStorageLimitGB(_ value: String) -> Int {
        guard let limit = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return VoicePenConfig.defaultSavedAudioStorageLimitGB
        }

        return min(
            max(limit, VoicePenConfig.minimumSavedAudioStorageLimitGB),
            VoicePenConfig.maximumSavedAudioStorageLimitGB
        )
    }

    private static func normalizeDeveloperModeOverride(_ value: String?) -> DeveloperMode? {
        guard let value else { return nil }
        return DeveloperMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func normalizeMeetingSystemAudioSourceMode(_ value: String) -> MeetingSystemAudioSourceMode {
        MeetingSystemAudioSourceMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .all
    }

    private static func normalizeAppAppearanceMode(_ value: String) -> AppAppearanceMode {
        AppAppearanceMode(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .system
    }

    private static func normalizeMeetingAudioAppSelections(_ value: String?) -> [MeetingAudioAppSelection] {
        guard
            let value,
            let data = value.data(using: .utf8),
            let selections = try? JSONDecoder().decode([MeetingAudioAppSelection].self, from: data)
        else {
            return []
        }
        return normalizeMeetingAudioAppSelections(selections)
    }

    private static func normalizeMeetingAudioAppSelections(
        _ selections: [MeetingAudioAppSelection]
    ) -> [MeetingAudioAppSelection] {
        var seen = Set<String>()
        var normalizedSelections: [MeetingAudioAppSelection] = []
        for selection in selections {
            let normalizedSelection = MeetingAudioAppSelection(
                displayName: selection.displayName,
                bundleIdentifier: selection.bundleIdentifier
            )
            guard normalizedSelection.isValid, seen.insert(normalizedSelection.bundleIdentifier).inserted else {
                continue
            }
            normalizedSelections.append(normalizedSelection)
        }
        return normalizedSelections
    }

    private static func encodeMeetingAudioAppSelections(_ selections: [MeetingAudioAppSelection]) throws -> String {
        let data = try JSONEncoder().encode(selections)
        return String(decoding: data, as: UTF8.self)
    }

    static let supportedLanguages: [TranscriptionLanguage] = [
        TranscriptionLanguage(code: "auto", name: "Auto-detect"),
        TranscriptionLanguage(code: "system", name: "System language"),
        TranscriptionLanguage(code: "ru", name: "Russian"),
        TranscriptionLanguage(code: "en", name: "English")
    ]

    private static let languageKey = "transcription.language"
    private static let selectedModelKey = "transcription.selectedModelId"
    private static let speechPreprocessingKey = "audio.speechPreprocessingMode"
    private static let boostDictationInputGainKey = "audio.boostDictationInputGain"
    private static let meetingVoiceLevelingEnabledKey = "audio.meetingVoiceLevelingEnabled"
    private static let saveDictationAudioEnabledKey = "audio.saveDictationAudioEnabled"
    private static let saveMeetingAudioEnabledKey = "audio.saveMeetingAudioEnabled"
    private static let savedAudioStorageLimitGBKey = "audio.savedAudioStorageLimitGB"
    private static let meetingTranscriptTimecodesEnabledKey = "meeting.transcriptTimecodesEnabled"
    private static let meetingDiarizationEnabledKey = "meeting.diarizationEnabled"
    private static let meetingSystemAudioSourceModeKey = "meeting.systemAudioSourceMode"
    private static let meetingAudioAppSelectionsKey = "meeting.systemAudioAppSelections"
    private static let appAppearanceModeKey = "app.appearanceMode"
    private static let hotkeyPreferenceKey = "hotkey.preference"
    private static let hotkeyHoldDurationKey = "hotkey.holdDuration"
    private static let openAtLoginKey = "app.openAtLogin"
    private static let developerModeOverrideKey = "developer.modeOverride"
    private static let meetingConsentKey = "meeting.recordingConsentAcknowledged"
}

struct TranscriptionLanguage: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String

    var displayName: String {
        "\(name) (\(code))"
    }
}

private struct LoadedSettings {
    let language: String
    let modelId: String
    let preprocessing: String
    let hotkey: String
    let holdDuration: String
    let boostDictationInputGain: String
    let meetingVoiceLeveling: String
    let saveDictationAudio: String
    let saveMeetingAudio: String
    let savedAudioStorageLimitGB: String
    let meetingTranscriptTimecodes: String
    let meetingDiarization: String
    let meetingSystemAudioSourceMode: String
    let meetingAudioAppSelections: String?
    let appAppearanceMode: String
    let openAtLogin: String
    let developerModeOverride: String?
    let meetingConsent: String
}

nonisolated enum AppAppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }
}

private enum AppSettingsStoreError: LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "Settings database error: \(message)"
        }
    }
}
