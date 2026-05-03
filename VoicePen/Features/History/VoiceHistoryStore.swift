import Combine
import Foundation
import SQLite3

@MainActor
final class VoiceHistoryStore: ObservableObject {
    @Published private(set) var entries: [VoiceHistoryEntry] = []
    @Published private(set) var usageStats = VoiceTranscriptionUsageStats()
    @Published private(set) var storageStats = VoiceHistoryStorageStats()

    private let databaseURL: URL
    private let textStorageLimitBytes: Int
    private let textPayloadStorageLimitBytes: Int
    private let textPruneBatchCount: Int
    private let textEvictionBatchCount: Int

    init(
        historyURL: URL,
        textStorageLimitBytes: Int = 20 * 1024 * 1024,
        textPayloadStorageLimitBytes: Int = 20 * 1024 * 1024,
        textPruneBatchCount: Int = 20,
        textEvictionBatchCount: Int = 20
    ) {
        self.databaseURL = historyURL
        self.textStorageLimitBytes = max(0, textStorageLimitBytes)
        self.textPayloadStorageLimitBytes = max(0, textPayloadStorageLimitBytes)
        self.textPruneBatchCount = max(1, textPruneBatchCount)
        self.textEvictionBatchCount = max(1, textEvictionBatchCount)
    }

    func load() throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            let fetchedEntries = try fetchEntries(from: database)
            return HistoryLoadResult(
                entries: fetchedEntries,
                storageStats: try fetchStorageStats(from: database)
            )
        }
        entries = result.entries
        usageStats = VoiceTranscriptionUsageStats(entries: result.entries)
        storageStats = result.storageStats
    }

    func append(_ entry: VoiceHistoryEntry) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try insert(entry, into: database)
            try compressStoredTextIfNeeded(in: database)
            let fetchedEntries = try fetchEntries(from: database)
            return HistoryLoadResult(
                entries: fetchedEntries,
                storageStats: try fetchStorageStats(from: database)
            )
        }
        entries = result.entries
        usageStats = VoiceTranscriptionUsageStats(entries: result.entries)
        storageStats = result.storageStats
    }

    func clear() throws {
        let stats = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try execute("DELETE FROM voice_history;", in: database)
            return try fetchStorageStats(from: database)
        }
        entries = []
        usageStats = VoiceTranscriptionUsageStats()
        storageStats = stats
    }

    func delete(id: VoiceHistoryEntry.ID) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try deleteEntry(id: id, from: database)
            let fetchedEntries = try fetchEntries(from: database)
            return HistoryLoadResult(
                entries: fetchedEntries,
                storageStats: try fetchStorageStats(from: database)
            )
        }
        entries = result.entries
        usageStats = VoiceTranscriptionUsageStats(entries: result.entries)
        storageStats = result.storageStats
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var database: OpaquePointer?
        guard
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
                nil
            ) == SQLITE_OK, let database
        else {
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
                model_metadata_json,
                recognized_word_count,
                diagnostic_notes_json,
                text_storage_format,
                raw_text_compressed,
                final_text_compressed
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
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

        sqlite3_bind_int64(statement, 10, Int64(entry.usageWordCount))
        if let diagnosticNotesJSON = try diagnosticNotesJSON(from: entry.diagnosticNotes) {
            sqlite3_bind_text(statement, 11, diagnosticNotesJSON, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 11)
        }
        sqlite3_bind_text(statement, 12, VoiceHistoryTextStorageFormat.plain, -1, SQLITE_TRANSIENT)
        sqlite3_bind_null(statement, 13)
        sqlite3_bind_null(statement, 14)

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

    private func compressStoredTextIfNeeded(in database: OpaquePointer) throws {
        let rows = try fetchStoredTextRows(from: database)
        let totalTextBytes = rows.reduce(0) { $0 + $1.textByteCount }

        if totalTextBytes > textStorageLimitBytes {
            let idsToPrune =
                rows
                .dropFirst()
                .filter { $0.textByteCount > 0 }
                .suffix(textPruneBatchCount)

            for row in idsToPrune {
                try compressStoredText(row, in: database)
            }
        }

        try evictStoredTextIfNeeded(in: database)
    }

    private func fetchStoredTextRows(from database: OpaquePointer) throws -> [StoredTextRow] {
        let statement = try prepare(
            """
            SELECT id, raw_text, final_text, text_storage_format, raw_text_compressed, final_text_compressed, recognized_word_count
            FROM voice_history
            WHERE text_storage_format = '\(VoiceHistoryTextStorageFormat.plain)'
            ORDER BY created_at DESC;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        var rows: [StoredTextRow] = []

        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                let rawText = stringColumn(statement, index: 1)
                let finalText = stringColumn(statement, index: 2)
                rows.append(
                    StoredTextRow(
                        id: stringColumn(statement, index: 0),
                        rawText: rawText,
                        finalText: finalText,
                        textStorageFormat: stringColumn(statement, index: 3),
                        compressedRawText: optionalDataColumn(statement, index: 4),
                        compressedFinalText: optionalDataColumn(statement, index: 5),
                        recognizedWordCount: optionalIntColumn(statement, index: 6)
                    ))
            case SQLITE_DONE:
                return rows
            default:
                throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func compressStoredText(_ row: StoredTextRow, in database: OpaquePointer) throws {
        let compressedRawText = try VoiceHistoryTextCompressor.compress(row.rawText)
        let compressedFinalText = try VoiceHistoryTextCompressor.compress(row.finalText)
        let statement = try prepare(
            """
            UPDATE voice_history
            SET raw_text = '',
                final_text = '',
                text_storage_format = ?,
                raw_text_compressed = ?,
                final_text_compressed = ?
            WHERE id = ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, VoiceHistoryTextStorageFormat.zlib, -1, SQLITE_TRANSIENT)
        bindBlob(compressedRawText, to: statement, index: 2)
        bindBlob(compressedFinalText, to: statement, index: 3)
        sqlite3_bind_text(statement, 4, row.id, -1, SQLITE_TRANSIENT)
        try stepDone(statement, database: database)
    }

    private func evictStoredTextIfNeeded(in database: OpaquePointer) throws {
        let storageStats = try fetchStorageStats(from: database)
        guard storageStats.textPayloadBytes > textPayloadStorageLimitBytes else { return }

        let idsToEvict = try fetchTextPayloadRows(from: database)
            .dropFirst()
            .filter { $0.textByteCount > 0 }
            .suffix(textEvictionBatchCount)

        for row in idsToEvict {
            try evictStoredText(row, in: database)
        }
    }

    private func fetchTextPayloadRows(from database: OpaquePointer) throws -> [StoredTextRow] {
        let statement = try prepare(
            """
            SELECT id, raw_text, final_text, text_storage_format, raw_text_compressed, final_text_compressed, recognized_word_count
            FROM voice_history
            WHERE text_storage_format != '\(VoiceHistoryTextStorageFormat.evicted)'
            ORDER BY created_at DESC;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        var rows: [StoredTextRow] = []

        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                rows.append(
                    StoredTextRow(
                        id: stringColumn(statement, index: 0),
                        rawText: stringColumn(statement, index: 1),
                        finalText: stringColumn(statement, index: 2),
                        textStorageFormat: stringColumn(statement, index: 3),
                        compressedRawText: optionalDataColumn(statement, index: 4),
                        compressedFinalText: optionalDataColumn(statement, index: 5),
                        recognizedWordCount: optionalIntColumn(statement, index: 6)
                    ))
            case SQLITE_DONE:
                return rows
            default:
                throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func evictStoredText(_ row: StoredTextRow, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            UPDATE voice_history
            SET raw_text = '',
                final_text = '',
                text_storage_format = ?,
                raw_text_compressed = NULL,
                final_text_compressed = NULL,
                recognized_word_count = ?
            WHERE id = ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, VoiceHistoryTextStorageFormat.evicted, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, Int64(try row.resolvedWordCount()))
        sqlite3_bind_text(statement, 3, row.id, -1, SQLITE_TRANSIENT)
        try stepDone(statement, database: database)
    }

    private func fetchEntries(from database: OpaquePointer) throws -> [VoiceHistoryEntry] {
        let statement = try prepare(
            """
            SELECT id, created_at, duration, raw_text, final_text, status, error_message, timings_json, model_metadata_json, text_storage_format, raw_text_compressed, final_text_compressed, recognized_word_count, diagnostic_notes_json
            FROM voice_history
            ORDER BY created_at DESC;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

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
        let textStorageFormat = stringColumn(statement, index: 9)
        let storedText = try historyText(
            format: textStorageFormat,
            rawText: stringColumn(statement, index: 3),
            finalText: stringColumn(statement, index: 4),
            compressedRawText: optionalDataColumn(statement, index: 10),
            compressedFinalText: optionalDataColumn(statement, index: 11)
        )

        return VoiceHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            duration: optionalDoubleColumn(statement, index: 2),
            rawText: storedText.rawText,
            finalText: storedText.finalText,
            status: status,
            errorMessage: optionalStringColumn(statement, index: 6),
            timings: try timings(from: optionalStringColumn(statement, index: 7)),
            modelMetadata: try modelMetadata(from: optionalStringColumn(statement, index: 8)),
            diagnosticNotes: try diagnosticNotes(from: optionalStringColumn(statement, index: 13)),
            recognizedWordCount: optionalIntColumn(statement, index: 12),
            isTextPayloadEvicted: storedText.isEvicted
        )
    }

    private func historyText(
        format: String,
        rawText: String,
        finalText: String,
        compressedRawText: Data?,
        compressedFinalText: Data?
    ) throws -> StoredHistoryText {
        if format == VoiceHistoryTextStorageFormat.evicted {
            return StoredHistoryText(rawText: "", finalText: "", isEvicted: true)
        }

        guard format == VoiceHistoryTextStorageFormat.zlib else {
            return StoredHistoryText(rawText: rawText, finalText: finalText)
        }

        guard let compressedRawText, let compressedFinalText else {
            throw VoiceHistoryStoreError.invalidRow("Compressed history text is missing payload")
        }

        return StoredHistoryText(
            rawText: try VoiceHistoryTextCompressor.decompress(compressedRawText),
            finalText: try VoiceHistoryTextCompressor.decompress(compressedFinalText),
            isEvicted: false
        )
    }

    private func fetchStorageStats(from database: OpaquePointer) throws -> VoiceHistoryStorageStats {
        let statement = try prepare(
            """
            SELECT
                COUNT(*),
                COALESCE(SUM(length(CAST(raw_text AS BLOB)) + length(CAST(final_text AS BLOB))), 0),
                COALESCE(SUM(COALESCE(length(raw_text_compressed), 0) + COALESCE(length(final_text_compressed), 0)), 0)
            FROM voice_history;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw VoiceHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }

        return VoiceHistoryStorageStats(
            entryCount: Int(sqlite3_column_int(statement, 0)),
            plainTextBytes: Int(sqlite3_column_int64(statement, 1)),
            compressedTextBytes: Int(sqlite3_column_int64(statement, 2)),
            databaseFileBytes: databaseFileSize()
        )
    }

    private func databaseFileSize() -> Int {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: databaseURL.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
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

    private func diagnosticNotesJSON(from diagnosticNotes: [String]) throws -> String? {
        guard !diagnosticNotes.isEmpty else { return nil }

        let data = try JSONEncoder().encode(diagnosticNotes)
        return String(data: data, encoding: .utf8)
    }

    private func diagnosticNotes(from json: String?) throws -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return try JSONDecoder().decode([String].self, from: data)
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

    private func optionalIntColumn(_ statement: OpaquePointer, index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func optionalDataColumn(_ statement: OpaquePointer, index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard byteCount > 0 else { return Data() }
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: byteCount)
    }

    private func bindBlob(_ data: Data, to statement: OpaquePointer, index: Int32) {
        guard !data.isEmpty else {
            sqlite3_bind_blob(statement, index, nil, 0, SQLITE_TRANSIENT)
            return
        }

        _ = data.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
        }
    }
}

nonisolated struct VoiceHistoryStorageStats: Equatable, Sendable {
    var entryCount: Int = 0
    var plainTextBytes: Int = 0
    var compressedTextBytes: Int = 0
    var databaseFileBytes: Int = 0

    var textPayloadBytes: Int {
        plainTextBytes + compressedTextBytes
    }

    var formattedTextPayloadSize: String {
        Self.formattedByteCount(textPayloadBytes)
    }

    var formattedDatabaseFileSize: String {
        Self.formattedByteCount(databaseFileBytes)
    }

    private static func formattedByteCount(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, byteCount)), countStyle: .file)
    }
}

private struct HistoryLoadResult {
    var entries: [VoiceHistoryEntry]
    var storageStats: VoiceHistoryStorageStats
}

enum VoiceHistoryStoreError: LocalizedError {
    case sqlite(String)
    case invalidRow(String)
    case compressionFailed
    case decompressionFailed
    case invalidCompressedText

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "History database error: \(message)"
        case let .invalidRow(message):
            return "Invalid history database row: \(message)"
        case .compressionFailed:
            return "Unable to compress history text"
        case .decompressionFailed:
            return "Unable to decompress history text"
        case .invalidCompressedText:
            return "Compressed history text is not valid UTF-8"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
