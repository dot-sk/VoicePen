import Combine
import Foundation
import SQLite3

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published private(set) var transcriptionLanguage: String
    @Published private(set) var selectedModelId: String
    @Published private(set) var speechPreprocessingMode: SpeechPreprocessingMode
    @Published private(set) var hotkeyPreference: HotkeyPreference
    @Published private(set) var hotkeyHoldDuration: TimeInterval
    @Published private(set) var openAtLogin: Bool

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
        self.openAtLogin = false
    }

    func load(defaultModelId: String) throws {
        let values = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            let language = try fetchValue(forKey: Self.languageKey, from: database) ?? VoicePenConfig.defaultLanguage
            let modelId = try fetchValue(forKey: Self.selectedModelKey, from: database) ?? defaultModelId
            let preprocessing = try fetchValue(forKey: Self.speechPreprocessingKey, from: database) ?? SpeechPreprocessingMode.off.rawValue
            let hotkey = try fetchValue(forKey: Self.hotkeyPreferenceKey, from: database) ?? HotkeyPreference.option.rawValue
            let holdDuration = try fetchValue(forKey: Self.hotkeyHoldDurationKey, from: database)
                ?? String(VoicePenConfig.defaultHotkeyHoldDuration)
            let openAtLogin = try fetchValue(forKey: Self.openAtLoginKey, from: database) ?? "false"
            return (
                language, modelId, preprocessing, hotkey, holdDuration, openAtLogin
            )
        }
        transcriptionLanguage = Self.normalizeLanguage(values.0)
        selectedModelId = Self.normalizeModelId(values.1, fallback: defaultModelId)
        speechPreprocessingMode = Self.normalizeSpeechPreprocessingMode(values.2)
        hotkeyPreference = Self.normalizeHotkeyPreference(values.3)
        hotkeyHoldDuration = Self.normalizeHotkeyHoldDuration(values.4)
        openAtLogin = Self.normalizeBoolean(values.5)
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

    func updateOpenAtLogin(_ isEnabled: Bool) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try setValue(String(isEnabled), forKey: Self.openAtLoginKey, in: database)
        }
        openAtLogin = isEnabled
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            throw AppSettingsStoreError.sqlite(message)
        }

        defer {
            sqlite3_close(database)
        }

        return try body(database)
    }

    private func fetchValue(forKey key: String, from database: OpaquePointer) throws -> String? {
        let statement = try prepare("SELECT value FROM app_settings WHERE key = ? LIMIT 1;", in: database)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard let text = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: text)
    }

    private func setValue(_ value: String, forKey key: String, in database: OpaquePointer) throws {
        let statement = try prepare(
            "INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?);",
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, key, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, value, -1, SQLITE_TRANSIENT)
        try stepDone(statement, database: database)
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw AppSettingsStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AppSettingsStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw AppSettingsStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
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

        return min(max(value, 0.1), 2.0)
    }

    private static func normalizeBoolean(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
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
    private static let hotkeyPreferenceKey = "hotkey.preference"
    private static let hotkeyHoldDurationKey = "hotkey.holdDuration"
    private static let openAtLoginKey = "app.openAtLogin"
}

struct TranscriptionLanguage: Identifiable, Equatable {
    var id: String { code }
    let code: String
    let name: String

    var displayName: String {
        "\(name) (\(code))"
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

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
