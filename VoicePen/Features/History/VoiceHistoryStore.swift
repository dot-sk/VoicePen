import Combine
import Foundation

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

    func appendArchivedAudioURL(_ url: URL, for id: VoiceHistoryEntry.ID) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try ArchivedAudioHistoryLinks.insert(
                url: url,
                ownerKind: .voiceHistory,
                ownerID: id,
                in: database
            )
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
            try database.execute("DELETE FROM voice_history;")
            try ArchivedAudioHistoryLinks.deleteAll(ownerKind: .voiceHistory, in: database)
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
            try ArchivedAudioHistoryLinks.delete(ownerKind: .voiceHistory, ownerID: id, in: database)
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

    private func withDatabase<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        let database = try SQLiteConnection.open(
            at: databaseURL,
            makeError: VoiceHistoryStoreError.sqlite
        )
        return try body(database)
    }

    private func insert(_ entry: VoiceHistoryEntry, into database: SQLiteConnection) throws {
        let statement = try database.prepare(
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
            """
        )

        statement.bindText(entry.id.uuidString, at: 1)
        statement.bindDouble(entry.createdAt.timeIntervalSince1970, at: 2)

        if let duration = entry.duration {
            statement.bindDouble(duration, at: 3)
        } else {
            statement.bindNull(at: 3)
        }

        statement.bindText(entry.rawText, at: 4)
        statement.bindText(entry.finalText, at: 5)
        statement.bindText(entry.status.rawValue, at: 6)

        if let errorMessage = entry.errorMessage {
            statement.bindText(errorMessage, at: 7)
        } else {
            statement.bindNull(at: 7)
        }

        if let timingsJSON = try timingsJSON(from: entry.timings) {
            statement.bindText(timingsJSON, at: 8)
        } else {
            statement.bindNull(at: 8)
        }

        if let modelMetadataJSON = try modelMetadataJSON(from: entry.modelMetadata) {
            statement.bindText(modelMetadataJSON, at: 9)
        } else {
            statement.bindNull(at: 9)
        }

        statement.bindInt64(Int64(entry.usageWordCount), at: 10)
        if let diagnosticNotesJSON = try diagnosticNotesJSON(from: entry.diagnosticNotes) {
            statement.bindText(diagnosticNotesJSON, at: 11)
        } else {
            statement.bindNull(at: 11)
        }
        statement.bindText(VoiceHistoryTextStorageFormat.plain, at: 12)
        statement.bindNull(at: 13)
        statement.bindNull(at: 14)

        try statement.stepDone()
    }

    private func deleteEntry(id: VoiceHistoryEntry.ID, from database: SQLiteConnection) throws {
        let statement = try database.prepare("DELETE FROM voice_history WHERE id = ?;")

        statement.bindText(id.uuidString, at: 1)
        try statement.stepDone()
    }

    private func compressStoredTextIfNeeded(in database: SQLiteConnection) throws {
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

    private func fetchStoredTextRows(from database: SQLiteConnection) throws -> [StoredTextRow] {
        let statement = try database.prepare(
            """
            SELECT id, raw_text, final_text, text_storage_format, raw_text_compressed, final_text_compressed, recognized_word_count
            FROM voice_history
            WHERE text_storage_format = '\(VoiceHistoryTextStorageFormat.plain)'
            ORDER BY created_at DESC;
            """
        )

        var rows: [StoredTextRow] = []

        while true {
            switch try statement.step() {
            case .row:
                let rawText = statement.string(at: 1)
                let finalText = statement.string(at: 2)
                rows.append(
                    StoredTextRow(
                        id: statement.string(at: 0),
                        rawText: rawText,
                        finalText: finalText,
                        textStorageFormat: statement.string(at: 3),
                        compressedRawText: statement.optionalData(at: 4),
                        compressedFinalText: statement.optionalData(at: 5),
                        recognizedWordCount: statement.optionalInt(at: 6)
                    ))
            case .done:
                return rows
            }
        }
    }

    private func compressStoredText(_ row: StoredTextRow, in database: SQLiteConnection) throws {
        let compressedRawText = try VoiceHistoryTextCompressor.compress(row.rawText)
        let compressedFinalText = try VoiceHistoryTextCompressor.compress(row.finalText)
        let statement = try database.prepare(
            """
            UPDATE voice_history
            SET raw_text = '',
                final_text = '',
                text_storage_format = ?,
                raw_text_compressed = ?,
                final_text_compressed = ?
            WHERE id = ?;
            """
        )

        statement.bindText(VoiceHistoryTextStorageFormat.zlib, at: 1)
        statement.bindBlob(compressedRawText, at: 2)
        statement.bindBlob(compressedFinalText, at: 3)
        statement.bindText(row.id, at: 4)
        try statement.stepDone()
    }

    private func evictStoredTextIfNeeded(in database: SQLiteConnection) throws {
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

    private func fetchTextPayloadRows(from database: SQLiteConnection) throws -> [StoredTextRow] {
        let statement = try database.prepare(
            """
            SELECT id, raw_text, final_text, text_storage_format, raw_text_compressed, final_text_compressed, recognized_word_count
            FROM voice_history
            WHERE text_storage_format != '\(VoiceHistoryTextStorageFormat.evicted)'
            ORDER BY created_at DESC;
            """
        )

        var rows: [StoredTextRow] = []

        while true {
            switch try statement.step() {
            case .row:
                rows.append(
                    StoredTextRow(
                        id: statement.string(at: 0),
                        rawText: statement.string(at: 1),
                        finalText: statement.string(at: 2),
                        textStorageFormat: statement.string(at: 3),
                        compressedRawText: statement.optionalData(at: 4),
                        compressedFinalText: statement.optionalData(at: 5),
                        recognizedWordCount: statement.optionalInt(at: 6)
                    ))
            case .done:
                return rows
            }
        }
    }

    private func evictStoredText(_ row: StoredTextRow, in database: SQLiteConnection) throws {
        let statement = try database.prepare(
            """
            UPDATE voice_history
            SET raw_text = '',
                final_text = '',
                text_storage_format = ?,
                raw_text_compressed = NULL,
                final_text_compressed = NULL,
                recognized_word_count = ?
            WHERE id = ?;
            """
        )

        statement.bindText(VoiceHistoryTextStorageFormat.evicted, at: 1)
        statement.bindInt64(Int64(try row.resolvedWordCount()), at: 2)
        statement.bindText(row.id, at: 3)
        try statement.stepDone()
    }

    private func fetchEntries(from database: SQLiteConnection) throws -> [VoiceHistoryEntry] {
        let statement = try database.prepare(
            """
            SELECT id, created_at, duration, raw_text, final_text, status, error_message, timings_json, model_metadata_json, text_storage_format, raw_text_compressed, final_text_compressed, recognized_word_count, diagnostic_notes_json
            FROM voice_history
            ORDER BY created_at DESC;
            """
        )

        var fetchedEntries: [VoiceHistoryEntry] = []

        while true {
            switch try statement.step() {
            case .row:
                fetchedEntries.append(try entry(from: statement))
            case .done:
                return try entriesWithArchivedAudioURLs(fetchedEntries, from: database)
            }
        }
    }

    private func entriesWithArchivedAudioURLs(
        _ entries: [VoiceHistoryEntry],
        from database: SQLiteConnection
    ) throws -> [VoiceHistoryEntry] {
        let linksByID = try ArchivedAudioHistoryLinks.fetch(ownerKind: .voiceHistory, in: database)
        return entries.map { entry in
            var entry = entry
            entry.archivedAudioURLs = linksByID[entry.id] ?? []
            return entry
        }
    }

    private func entry(from statement: SQLiteStatement) throws -> VoiceHistoryEntry {
        guard let id = UUID(uuidString: statement.string(at: 0)) else {
            throw VoiceHistoryStoreError.invalidRow("Invalid history entry id")
        }

        let statusRawValue = statement.string(at: 5)
        let status = VoiceHistoryStatus(rawValue: statusRawValue) ?? .failed
        let textStorageFormat = statement.string(at: 9)
        let storedText = try historyText(
            format: textStorageFormat,
            rawText: statement.string(at: 3),
            finalText: statement.string(at: 4),
            compressedRawText: statement.optionalData(at: 10),
            compressedFinalText: statement.optionalData(at: 11)
        )

        return VoiceHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: statement.double(at: 1)),
            duration: statement.optionalDouble(at: 2),
            rawText: storedText.rawText,
            finalText: storedText.finalText,
            status: status,
            errorMessage: statement.optionalString(at: 6),
            timings: try timings(from: statement.optionalString(at: 7)),
            modelMetadata: try modelMetadata(from: statement.optionalString(at: 8)),
            diagnosticNotes: try diagnosticNotes(from: statement.optionalString(at: 13)),
            recognizedWordCount: statement.optionalInt(at: 12),
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
        let payload = StoredTextPayload(
            format: format,
            components: [
                StoredTextComponent(plainText: rawText, compressedText: compressedRawText),
                StoredTextComponent(plainText: finalText, compressedText: compressedFinalText)
            ],
            missingCompressedPayloadError: {
                VoiceHistoryStoreError.invalidRow("Compressed history text is missing payload")
            }
        )
        let texts = try payload.resolvedTexts()
        return StoredHistoryText(
            rawText: texts.first ?? "",
            finalText: texts.dropFirst().first ?? "",
            isEvicted: payload.isEvicted
        )
    }

    private func fetchStorageStats(from database: SQLiteConnection) throws -> VoiceHistoryStorageStats {
        let statement = try database.prepare(
            """
            SELECT
                COUNT(*),
                COALESCE(SUM(length(CAST(raw_text AS BLOB)) + length(CAST(final_text AS BLOB))), 0),
                COALESCE(SUM(COALESCE(length(raw_text_compressed), 0) + COALESCE(length(final_text_compressed), 0)), 0)
            FROM voice_history;
            """
        )

        guard try statement.step() == .row else {
            throw VoiceHistoryStoreError.sqlite("Unable to read history storage stats")
        }

        return VoiceHistoryStorageStats(
            entryCount: statement.int(at: 0),
            plainTextBytes: Int(statement.int64(at: 1)),
            compressedTextBytes: Int(statement.int64(at: 2)),
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

    var formattedDiskUsageSize: String {
        formattedDatabaseFileSize
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
