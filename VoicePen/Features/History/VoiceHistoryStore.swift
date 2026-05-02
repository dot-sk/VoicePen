import Combine
import Foundation
import SQLite3

@MainActor
final class VoiceHistoryStore: ObservableObject {
    @Published private(set) var entries: [VoiceHistoryEntry] = []
    @Published private(set) var usageStats = VoiceTranscriptionUsageStats()

    private let databaseURL: URL
    private let maxEntries: Int

    init(historyURL: URL, maxEntries: Int = 200) {
        self.databaseURL = historyURL
        self.maxEntries = maxEntries
    }

    func load() throws {
        let fetchedEntries = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            return try fetchEntries(from: database)
        }
        entries = fetchedEntries
        usageStats = VoiceTranscriptionUsageStats(entries: fetchedEntries)
    }

    func append(_ entry: VoiceHistoryEntry) throws {
        let fetchedEntries = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try insert(entry, into: database)
            try pruneEntries(in: database)
            return try fetchEntries(from: database)
        }
        entries = fetchedEntries
        usageStats = VoiceTranscriptionUsageStats(entries: fetchedEntries)
    }

    func clear() throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try execute("DELETE FROM voice_history;", in: database)
        }
        entries = []
        usageStats = VoiceTranscriptionUsageStats()
    }

    func delete(id: VoiceHistoryEntry.ID) throws {
        let fetchedEntries = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try deleteEntry(id: id, from: database)
            return try fetchEntries(from: database)
        }
        entries = fetchedEntries
        usageStats = VoiceTranscriptionUsageStats(entries: fetchedEntries)
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            throw VoiceHistoryStoreError.sqlite(message)
        }

        defer {
            sqlite3_close(database)
        }

        return try body(database)
    }

    private func insert(_ entry: VoiceHistoryEntry, into database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO voice_history (
                id,
                created_at,
                duration,
                raw_text,
                final_text,
                status,
                error_message,
                timings_json,
                model_metadata_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, entry.createdAt.timeIntervalSince1970)

        if let duration = entry.duration {
            sqlite3_bind_double(statement, 3, duration)
        } else {
            sqlite3_bind_null(statement, 3)
        }

        sqlite3_bind_text(statement, 4, entry.rawText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, entry.finalText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, entry.status.rawValue, -1, SQLITE_TRANSIENT)

        if let errorMessage = entry.errorMessage {
            sqlite3_bind_text(statement, 7, errorMessage, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 7)
        }

        if let timingsJSON = try timingsJSON(from: entry.timings) {
            sqlite3_bind_text(statement, 8, timingsJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 8)
        }

        if let modelMetadataJSON = try modelMetadataJSON(from: entry.modelMetadata) {
            sqlite3_bind_text(statement, 9, modelMetadataJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 9)
        }

        try stepDone(statement, database: database)
    }

    private func pruneEntries(in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            DELETE FROM voice_history
            WHERE id NOT IN (
                SELECT id FROM voice_history
                ORDER BY created_at DESC
                LIMIT ?
            );
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(maxEntries))
        try stepDone(statement, database: database)
    }

    private func deleteEntry(id: VoiceHistoryEntry.ID, from database: OpaquePointer) throws {
        let statement = try prepare(
            "DELETE FROM voice_history WHERE id = ?;",
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        try stepDone(statement, database: database)
    }

    private func fetchEntries(from database: OpaquePointer) throws -> [VoiceHistoryEntry] {
        let statement = try prepare(
            """
            SELECT id, created_at, duration, raw_text, final_text, status, error_message, timings_json, model_metadata_json
            FROM voice_history
            ORDER BY created_at DESC
            LIMIT ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(maxEntries))

        var fetchedEntries: [VoiceHistoryEntry] = []

        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                fetchedEntries.append(try entry(from: statement))
            case SQLITE_DONE:
                return fetchedEntries
            default:
                throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func entry(from statement: OpaquePointer) throws -> VoiceHistoryEntry {
        guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
            throw VoiceHistoryStoreError.invalidRow("Invalid history entry id")
        }

        let statusRawValue = stringColumn(statement, index: 5)
        let status = VoiceHistoryStatus(rawValue: statusRawValue) ?? .failed

        return VoiceHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            duration: optionalDoubleColumn(statement, index: 2),
            rawText: stringColumn(statement, index: 3),
            finalText: stringColumn(statement, index: 4),
            status: status,
            errorMessage: optionalStringColumn(statement, index: 6),
            timings: try timings(from: optionalStringColumn(statement, index: 7)),
            modelMetadata: try modelMetadata(from: optionalStringColumn(statement, index: 8))
        )
    }

    private func timingsJSON(from timings: VoicePipelineTimings?) throws -> String? {
        guard let timings else { return nil }

        let data = try JSONEncoder().encode(timings)
        return String(data: data, encoding: .utf8)
    }

    private func timings(from json: String?) throws -> VoicePipelineTimings? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(VoicePipelineTimings.self, from: data)
    }

    private func modelMetadataJSON(from modelMetadata: VoiceTranscriptionModelMetadata?) throws -> String? {
        guard let modelMetadata else { return nil }

        let data = try JSONEncoder().encode(modelMetadata)
        return String(data: data, encoding: .utf8)
    }

    private func modelMetadata(from json: String?) throws -> VoiceTranscriptionModelMetadata? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try JSONDecoder().decode(VoiceTranscriptionModelMetadata.self, from: data)
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private func optionalStringColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return stringColumn(statement, index: index)
    }

    private func optionalDoubleColumn(_ statement: OpaquePointer, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }
}

private enum VoiceHistoryStoreError: LocalizedError {
    case sqlite(String)
    case invalidRow(String)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "History database error: \(message)"
        case let .invalidRow(message):
            return "Invalid history database row: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
