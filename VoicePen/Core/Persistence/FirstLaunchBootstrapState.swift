import Foundation

nonisolated enum FirstLaunchBootstrapState {
    static let completedKey = "app.firstLaunchBootstrapCompleted"

    static func isCompleted(in database: SQLiteConnection) throws -> Bool {
        let statement = try database.prepare("SELECT value FROM app_settings WHERE key = ? LIMIT 1;")
        statement.bindText(completedKey, at: 1)

        guard try statement.step() == .row else { return false }
        return normalizeBoolean(statement.string(at: 0))
    }

    static func markCompleted(in database: SQLiteConnection) throws {
        let statement = try database.prepare("INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?);")
        statement.bindText(completedKey, at: 1)
        statement.bindText("true", at: 2)
        try statement.stepDone()
    }

    static func canSeedFreshDefaults(in database: SQLiteConnection) throws -> Bool {
        guard try !isCompleted(in: database) else { return false }
        return try settingCount(in: database) == 0
            && voiceHistoryEntryCount(in: database) == 0
            && meetingHistoryEntryCount(in: database) == 0
    }

    private static func settingCount(in database: SQLiteConnection) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM app_settings WHERE key != ?;")
        statement.bindText(completedKey, at: 1)

        guard try statement.step() == .row else {
            throw FirstLaunchBootstrapStateError.invalidRow("Unable to count app settings")
        }
        return statement.int(at: 0)
    }

    private static func voiceHistoryEntryCount(in database: SQLiteConnection) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM voice_history;")

        guard try statement.step() == .row else {
            throw FirstLaunchBootstrapStateError.invalidRow("Unable to count voice history entries")
        }
        return statement.int(at: 0)
    }

    private static func meetingHistoryEntryCount(in database: SQLiteConnection) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM meeting_history;")

        guard try statement.step() == .row else {
            throw FirstLaunchBootstrapStateError.invalidRow("Unable to count meeting history entries")
        }
        return statement.int(at: 0)
    }

    private static func normalizeBoolean(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes":
            return true
        default:
            return false
        }
    }
}

private enum FirstLaunchBootstrapStateError: LocalizedError {
    case invalidRow(String)

    var errorDescription: String? {
        switch self {
        case let .invalidRow(message):
            return "Invalid first launch bootstrap row: \(message)"
        }
    }
}
