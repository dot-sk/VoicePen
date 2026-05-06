import Combine
import Foundation
import SQLite3

@MainActor
final class MeetingHistoryStore: ObservableObject {
    private static let transcriptPreviewLimit = 500
    private static let compressedTranscriptPreview = "Transcript stored locally; select to load."

    @Published private(set) var entries: [MeetingHistoryEntry] = []
    @Published private(set) var storageStats = VoiceHistoryStorageStats()

    private let databaseURL: URL
    private let transcriptCompressionLimitBytes: Int
    private let transcriptPayloadLimitBytes: Int
    private let compressionBatchCount: Int
    private let evictionBatchCount: Int
    private let fileManager: FileManager

    init(
        databaseURL: URL,
        transcriptCompressionLimitBytes: Int = 40 * 1024 * 1024,
        transcriptPayloadLimitBytes: Int = 40 * 1024 * 1024,
        compressionBatchCount: Int = 10,
        evictionBatchCount: Int = 10,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.transcriptCompressionLimitBytes = max(0, transcriptCompressionLimitBytes)
        self.transcriptPayloadLimitBytes = max(0, transcriptPayloadLimitBytes)
        self.compressionBatchCount = max(1, compressionBatchCount)
        self.evictionBatchCount = max(1, evictionBatchCount)
        self.fileManager = fileManager
    }

    func load() throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            return try loadResult(from: database)
        }
        publish(result)
    }

    func loadEntry(id: MeetingHistoryEntry.ID) throws -> MeetingHistoryEntry? {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            return try fetchEntry(id: id, from: database)
        }
    }

    func append(_ entry: MeetingHistoryEntry) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try insert(entry, into: database)
            try compressStoredTranscriptIfNeeded(in: database)
            return try loadResult(from: database)
        }
        publish(result)
    }

    func delete(id: MeetingHistoryEntry.ID) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            if let recoveryAudio = try fetchRecoveryAudio(id: id, from: database) {
                try removeRecoveryAudio(recoveryAudio)
            }
            let statement = try prepare("DELETE FROM meeting_history WHERE id = ?;", in: database)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
            try stepDone(statement, database: database)
            return try loadResult(from: database)
        }
        publish(result)
    }

    func clear() throws {
        let stats = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            for recoveryAudio in try fetchRecoveryAudioEntries(from: database) {
                try removeRecoveryAudio(recoveryAudio.manifest)
            }
            try execute("DELETE FROM meeting_history;", in: database)
            return try fetchStorageStats(from: database)
        }
        entries = []
        storageStats = stats
    }

    func cleanupExpiredRecoveryAudio(now: Date = Date()) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            let recoveryAudioEntries = try fetchRecoveryAudioEntries(from: database)
            for entry in recoveryAudioEntries {
                guard entry.manifest.isExpired(at: now)
                else { continue }

                try removeRecoveryAudio(entry.manifest)
                try clearRecoveryAudio(id: entry.id, in: database)
            }
            return try loadResult(from: database)
        }
        publish(result)
    }

    private func loadResult(from database: OpaquePointer) throws -> MeetingHistoryLoadResult {
        MeetingHistoryLoadResult(
            entries: try fetchEntrySummaries(from: database),
            storageStats: try fetchStorageStats(from: database)
        )
    }

    private func publish(_ result: MeetingHistoryLoadResult) {
        entries = result.entries
        storageStats = result.storageStats
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

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
            throw MeetingHistoryStoreError.sqlite(message)
        }

        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func insert(_ entry: MeetingHistoryEntry, into database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO meeting_history (
                id,
                created_at,
                duration,
                transcript_text,
                status,
                source_flags_json,
                error_message,
                timings_json,
                model_metadata_json,
                recognized_word_count,
                text_storage_format,
                transcript_text_compressed,
                recovery_audio_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, entry.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, entry.createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 3, entry.duration)
        sqlite3_bind_text(statement, 4, entry.transcriptText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, entry.status.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, try jsonString(entry.sourceFlags), -1, SQLITE_TRANSIENT)

        if let errorMessage = entry.errorMessage {
            sqlite3_bind_text(statement, 7, errorMessage, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 7)
        }

        if let timings = entry.timings {
            sqlite3_bind_text(statement, 8, try jsonString(timings), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 8)
        }

        if let modelMetadata = entry.modelMetadata {
            sqlite3_bind_text(statement, 9, try jsonString(modelMetadata), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 9)
        }

        sqlite3_bind_int64(statement, 10, Int64(entry.usageWordCount))
        sqlite3_bind_text(statement, 11, VoiceHistoryTextStorageFormat.plain, -1, SQLITE_TRANSIENT)
        sqlite3_bind_null(statement, 12)
        if let recoveryAudio = entry.recoveryAudio {
            sqlite3_bind_text(statement, 13, try jsonString(recoveryAudio), -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 13)
        }
        try stepDone(statement, database: database)
    }

    private func compressStoredTranscriptIfNeeded(in database: OpaquePointer) throws {
        let rows = try fetchStoredTranscriptRows(from: database)
        let totalPlainBytes = rows.reduce(0) { $0 + $1.textByteCount }

        if totalPlainBytes > transcriptCompressionLimitBytes {
            let idsToCompress =
                rows
                .dropFirst()
                .filter { $0.textByteCount > 0 }
                .suffix(compressionBatchCount)

            for row in idsToCompress {
                try compressStoredTranscript(row, in: database)
            }
        }

        try evictStoredTranscriptIfNeeded(in: database)
    }

    private func evictStoredTranscriptIfNeeded(in database: OpaquePointer) throws {
        let stats = try fetchStorageStats(from: database)
        guard stats.textPayloadBytes > transcriptPayloadLimitBytes else { return }

        let idsToEvict =
            try fetchPayloadTranscriptRows(from: database)
            .dropFirst()
            .filter { $0.textByteCount > 0 }
            .suffix(evictionBatchCount)

        for row in idsToEvict {
            try evictStoredTranscript(row, in: database)
        }
    }

    private func fetchStoredTranscriptRows(from database: OpaquePointer) throws -> [MeetingStoredTextRow] {
        try fetchTranscriptRows(
            """
            SELECT id, transcript_text, text_storage_format, transcript_text_compressed, recognized_word_count
            FROM meeting_history
            WHERE text_storage_format = '\(VoiceHistoryTextStorageFormat.plain)'
            ORDER BY created_at DESC;
            """,
            from: database
        )
    }

    private func fetchPayloadTranscriptRows(from database: OpaquePointer) throws -> [MeetingStoredTextRow] {
        try fetchTranscriptRows(
            """
            SELECT id, transcript_text, text_storage_format, transcript_text_compressed, recognized_word_count
            FROM meeting_history
            WHERE text_storage_format != '\(VoiceHistoryTextStorageFormat.evicted)'
            ORDER BY created_at DESC;
            """,
            from: database
        )
    }

    private func fetchTranscriptRows(_ sql: String, from database: OpaquePointer) throws -> [MeetingStoredTextRow] {
        let statement = try prepare(sql, in: database)
        defer { sqlite3_finalize(statement) }

        var rows: [MeetingStoredTextRow] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append(
                    MeetingStoredTextRow(
                        id: stringColumn(statement, index: 0),
                        transcriptText: stringColumn(statement, index: 1),
                        textStorageFormat: stringColumn(statement, index: 2),
                        compressedTranscriptText: optionalDataColumn(statement, index: 3),
                        recognizedWordCount: optionalIntColumn(statement, index: 4)
                    ))
            case SQLITE_DONE:
                return rows
            default:
                throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func compressStoredTranscript(_ row: MeetingStoredTextRow, in database: OpaquePointer) throws {
        let compressedTranscriptText = try VoiceHistoryTextCompressor.compress(row.transcriptText)
        let statement = try prepare(
            """
            UPDATE meeting_history
            SET transcript_text = '',
                text_storage_format = ?,
                transcript_text_compressed = ?
            WHERE id = ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, VoiceHistoryTextStorageFormat.zlib, -1, SQLITE_TRANSIENT)
        bindBlob(compressedTranscriptText, to: statement, index: 2)
        sqlite3_bind_text(statement, 3, row.id, -1, SQLITE_TRANSIENT)
        try stepDone(statement, database: database)
    }

    private func evictStoredTranscript(_ row: MeetingStoredTextRow, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            UPDATE meeting_history
            SET transcript_text = '',
                text_storage_format = ?,
                transcript_text_compressed = NULL,
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

    private func fetchEntrySummaries(from database: OpaquePointer) throws -> [MeetingHistoryEntry] {
        let statement = try prepare(
            """
            SELECT id, created_at, duration, substr(transcript_text, 1, ?), status, source_flags_json, error_message, timings_json, model_metadata_json, recognized_word_count, text_storage_format, recovery_audio_json
            FROM meeting_history
            ORDER BY created_at DESC;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(Self.transcriptPreviewLimit))

        var fetchedEntries: [MeetingHistoryEntry] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                fetchedEntries.append(try entrySummary(from: statement))
            case SQLITE_DONE:
                return fetchedEntries
            default:
                throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func fetchEntry(id: MeetingHistoryEntry.ID, from database: OpaquePointer) throws -> MeetingHistoryEntry? {
        let statement = try prepare(
            """
            SELECT id, created_at, duration, transcript_text, status, source_flags_json, error_message, timings_json, model_metadata_json, recognized_word_count, text_storage_format, transcript_text_compressed, recovery_audio_json
            FROM meeting_history
            WHERE id = ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return try entry(from: statement)
        case SQLITE_DONE:
            return nil
        default:
            throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func fetchRecoveryAudio(id: MeetingHistoryEntry.ID, from database: OpaquePointer) throws -> MeetingRecoveryAudioManifest? {
        let statement = try prepare(
            """
            SELECT recovery_audio_json
            FROM meeting_history
            WHERE id = ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return try decodeOptional(MeetingRecoveryAudioManifest.self, from: optionalStringColumn(statement, index: 0))
        case SQLITE_DONE:
            return nil
        default:
            throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func fetchRecoveryAudioEntries(from database: OpaquePointer) throws -> [MeetingRecoveryAudioEntry] {
        let statement = try prepare(
            """
            SELECT id, recovery_audio_json
            FROM meeting_history
            WHERE recovery_audio_json IS NOT NULL
            ORDER BY created_at DESC;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        var entries: [MeetingRecoveryAudioEntry] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
                    throw MeetingHistoryStoreError.invalidRow("Invalid meeting entry id")
                }
                guard let manifest = try decodeOptional(MeetingRecoveryAudioManifest.self, from: optionalStringColumn(statement, index: 1)) else {
                    throw MeetingHistoryStoreError.invalidRow("Invalid meeting recovery audio")
                }
                entries.append(MeetingRecoveryAudioEntry(id: id, manifest: manifest))
            case SQLITE_DONE:
                return entries
            default:
                throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func entry(from statement: OpaquePointer) throws -> MeetingHistoryEntry {
        guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
            throw MeetingHistoryStoreError.invalidRow("Invalid meeting entry id")
        }

        let format = stringColumn(statement, index: 10)
        let storedText = try transcriptText(
            format: format,
            plainText: stringColumn(statement, index: 3),
            compressedText: optionalDataColumn(statement, index: 11)
        )

        return MeetingHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            duration: sqlite3_column_double(statement, 2),
            transcriptText: storedText.text,
            status: MeetingRecordingStatus(rawValue: stringColumn(statement, index: 4)) ?? .failed,
            sourceFlags: try decode(MeetingSourceFlags.self, from: stringColumn(statement, index: 5)),
            errorMessage: optionalStringColumn(statement, index: 6),
            timings: try decodeOptional(MeetingPipelineTimings.self, from: optionalStringColumn(statement, index: 7)),
            modelMetadata: try decodeOptional(VoiceTranscriptionModelMetadata.self, from: optionalStringColumn(statement, index: 8)),
            recognizedWordCount: optionalIntColumn(statement, index: 9),
            recoveryAudio: try decodeOptional(MeetingRecoveryAudioManifest.self, from: optionalStringColumn(statement, index: 12)),
            isTextPayloadEvicted: storedText.isEvicted
        )
    }

    private func entrySummary(from statement: OpaquePointer) throws -> MeetingHistoryEntry {
        guard let id = UUID(uuidString: stringColumn(statement, index: 0)) else {
            throw MeetingHistoryStoreError.invalidRow("Invalid meeting entry id")
        }

        let format = stringColumn(statement, index: 10)
        let transcriptPreview: String
        let isTextPayloadEvicted: Bool
        switch format {
        case VoiceHistoryTextStorageFormat.evicted:
            transcriptPreview = ""
            isTextPayloadEvicted = true
        case VoiceHistoryTextStorageFormat.zlib:
            transcriptPreview = Self.compressedTranscriptPreview
            isTextPayloadEvicted = false
        default:
            transcriptPreview = stringColumn(statement, index: 3)
            isTextPayloadEvicted = false
        }

        return MeetingHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            duration: sqlite3_column_double(statement, 2),
            transcriptText: transcriptPreview,
            status: MeetingRecordingStatus(rawValue: stringColumn(statement, index: 4)) ?? .failed,
            sourceFlags: try decode(MeetingSourceFlags.self, from: stringColumn(statement, index: 5)),
            errorMessage: optionalStringColumn(statement, index: 6),
            timings: try decodeOptional(MeetingPipelineTimings.self, from: optionalStringColumn(statement, index: 7)),
            modelMetadata: try decodeOptional(VoiceTranscriptionModelMetadata.self, from: optionalStringColumn(statement, index: 8)),
            recognizedWordCount: optionalIntColumn(statement, index: 9),
            recoveryAudio: try decodeOptional(MeetingRecoveryAudioManifest.self, from: optionalStringColumn(statement, index: 11)),
            isTextPayloadEvicted: isTextPayloadEvicted
        )
    }

    private func transcriptText(
        format: String,
        plainText: String,
        compressedText: Data?
    ) throws -> (text: String, isEvicted: Bool) {
        if format == VoiceHistoryTextStorageFormat.evicted {
            return ("", true)
        }

        guard format == VoiceHistoryTextStorageFormat.zlib else {
            return (plainText, false)
        }

        guard let compressedText else {
            throw MeetingHistoryStoreError.invalidRow("Compressed meeting transcript is missing payload")
        }
        return (try VoiceHistoryTextCompressor.decompress(compressedText), false)
    }

    private func fetchStorageStats(from database: OpaquePointer) throws -> VoiceHistoryStorageStats {
        let statement = try prepare(
            """
            SELECT
                COUNT(*),
                COALESCE(SUM(length(CAST(transcript_text AS BLOB))), 0),
                COALESCE(SUM(COALESCE(length(transcript_text_compressed), 0)), 0)
            FROM meeting_history;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }

        return VoiceHistoryStorageStats(
            entryCount: Int(sqlite3_column_int(statement, 0)),
            plainTextBytes: Int(sqlite3_column_int64(statement, 1)),
            compressedTextBytes: Int(sqlite3_column_int64(statement, 2)),
            databaseFileBytes: databaseFileSize()
        )
    }

    private func databaseFileSize() -> Int {
        guard let attributes = try? fileManager.attributesOfItem(atPath: databaseURL.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.intValue
    }

    private func clearRecoveryAudio(id: MeetingHistoryEntry.ID, in database: OpaquePointer) throws {
        let statement = try prepare(
            """
            UPDATE meeting_history
            SET recovery_audio_json = NULL
            WHERE id = ?;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        try stepDone(statement, database: database)
    }

    private func removeRecoveryAudio(_ manifest: MeetingRecoveryAudioManifest?) throws {
        guard let manifest else { return }
        let directories = Set(manifest.chunks.map { $0.url.deletingLastPathComponent() })
        for directory in directories where fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw MeetingHistoryStoreError.invalidRow("Invalid JSON text")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func decodeOptional<T: Decodable>(_ type: T.Type, from json: String?) throws -> T? {
        guard let json else { return nil }
        return try decode(type, from: json)
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw MeetingHistoryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
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

private struct MeetingHistoryLoadResult {
    var entries: [MeetingHistoryEntry]
    var storageStats: VoiceHistoryStorageStats
}

private struct MeetingRecoveryAudioEntry {
    var id: MeetingHistoryEntry.ID
    var manifest: MeetingRecoveryAudioManifest
}

private struct MeetingStoredTextRow {
    var id: String
    var transcriptText: String
    var textStorageFormat: String
    var compressedTranscriptText: Data?
    var recognizedWordCount: Int?

    var textByteCount: Int {
        if textStorageFormat == VoiceHistoryTextStorageFormat.zlib {
            return compressedTranscriptText?.count ?? 0
        }

        return transcriptText.utf8.count
    }

    func resolvedWordCount() throws -> Int {
        if let recognizedWordCount {
            return recognizedWordCount
        }

        if textStorageFormat == VoiceHistoryTextStorageFormat.zlib {
            guard let compressedTranscriptText else {
                throw MeetingHistoryStoreError.invalidRow("Compressed meeting transcript is missing payload")
            }
            return VoiceHistoryEntry.wordCount(in: try VoiceHistoryTextCompressor.decompress(compressedTranscriptText))
        }

        return VoiceHistoryEntry.wordCount(in: transcriptText)
    }
}

enum MeetingHistoryStoreError: LocalizedError {
    case sqlite(String)
    case invalidRow(String)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "Meeting history database error: \(message)"
        case let .invalidRow(message):
            return "Invalid meeting history database row: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
