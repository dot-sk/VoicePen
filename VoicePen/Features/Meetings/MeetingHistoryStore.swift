import Combine
import Foundation

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

    func appendArchivedAudioURL(_ url: URL, for id: MeetingHistoryEntry.ID) throws {
        let result = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try ArchivedAudioHistoryLinks.insert(
                url: url,
                ownerKind: .meetingHistory,
                ownerID: id,
                in: database
            )
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
            try ArchivedAudioHistoryLinks.delete(ownerKind: .meetingHistory, ownerID: id, in: database)
            let statement = try database.prepare("DELETE FROM meeting_history WHERE id = ?;")
            statement.bindText(id.uuidString, at: 1)
            try statement.stepDone()
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
            try ArchivedAudioHistoryLinks.deleteAll(ownerKind: .meetingHistory, in: database)
            try database.execute("DELETE FROM meeting_history;")
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

    private func loadResult(from database: SQLiteConnection) throws -> MeetingHistoryLoadResult {
        MeetingHistoryLoadResult(
            entries: try fetchEntrySummaries(from: database),
            storageStats: try fetchStorageStats(from: database)
        )
    }

    private func publish(_ result: MeetingHistoryLoadResult) {
        entries = result.entries
        storageStats = result.storageStats
    }

    private func withDatabase<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        let database = try SQLiteConnection.open(
            at: databaseURL,
            fileManager: fileManager,
            makeError: MeetingHistoryStoreError.sqlite
        )
        return try body(database)
    }

    private func insert(_ entry: MeetingHistoryEntry, into database: SQLiteConnection) throws {
        let statement = try database.prepare(
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
                speaker_count,
                text_storage_format,
                transcript_text_compressed,
                recovery_audio_json
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
        )

        statement.bindText(entry.id.uuidString, at: 1)
        statement.bindDouble(entry.createdAt.timeIntervalSince1970, at: 2)
        statement.bindDouble(entry.duration, at: 3)
        statement.bindText(entry.transcriptText, at: 4)
        statement.bindText(entry.status.rawValue, at: 5)
        statement.bindText(try jsonString(entry.sourceFlags), at: 6)

        if let errorMessage = entry.errorMessage {
            statement.bindText(errorMessage, at: 7)
        } else {
            statement.bindNull(at: 7)
        }

        if let timings = entry.timings {
            statement.bindText(try jsonString(timings), at: 8)
        } else {
            statement.bindNull(at: 8)
        }

        if let modelMetadata = entry.modelMetadata {
            statement.bindText(try jsonString(modelMetadata), at: 9)
        } else {
            statement.bindNull(at: 9)
        }

        statement.bindInt64(Int64(entry.usageWordCount), at: 10)
        if let speakerCount = entry.speakerCount {
            statement.bindInt64(Int64(speakerCount), at: 11)
        } else {
            statement.bindNull(at: 11)
        }
        statement.bindText(VoiceHistoryTextStorageFormat.plain, at: 12)
        statement.bindNull(at: 13)
        if let recoveryAudio = entry.recoveryAudio {
            statement.bindText(try jsonString(recoveryAudio), at: 14)
        } else {
            statement.bindNull(at: 14)
        }
        try statement.stepDone()
    }

    private func compressStoredTranscriptIfNeeded(in database: SQLiteConnection) throws {
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

    private func evictStoredTranscriptIfNeeded(in database: SQLiteConnection) throws {
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

    private func fetchStoredTranscriptRows(from database: SQLiteConnection) throws -> [MeetingStoredTextRow] {
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

    private func fetchPayloadTranscriptRows(from database: SQLiteConnection) throws -> [MeetingStoredTextRow] {
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

    private func fetchTranscriptRows(_ sql: String, from database: SQLiteConnection) throws -> [MeetingStoredTextRow] {
        let statement = try database.prepare(sql)

        var rows: [MeetingStoredTextRow] = []
        while true {
            switch try statement.step() {
            case .row:
                rows.append(
                    MeetingStoredTextRow(
                        id: statement.string(at: 0),
                        transcriptText: statement.string(at: 1),
                        textStorageFormat: statement.string(at: 2),
                        compressedTranscriptText: statement.optionalData(at: 3),
                        recognizedWordCount: statement.optionalInt(at: 4)
                    ))
            case .done:
                return rows
            }
        }
    }

    private func compressStoredTranscript(_ row: MeetingStoredTextRow, in database: SQLiteConnection) throws {
        let compressedTranscriptText = try VoiceHistoryTextCompressor.compress(row.transcriptText)
        let statement = try database.prepare(
            """
            UPDATE meeting_history
            SET transcript_text = '',
                text_storage_format = ?,
                transcript_text_compressed = ?
            WHERE id = ?;
            """
        )

        statement.bindText(VoiceHistoryTextStorageFormat.zlib, at: 1)
        statement.bindBlob(compressedTranscriptText, at: 2)
        statement.bindText(row.id, at: 3)
        try statement.stepDone()
    }

    private func evictStoredTranscript(_ row: MeetingStoredTextRow, in database: SQLiteConnection) throws {
        let statement = try database.prepare(
            """
            UPDATE meeting_history
            SET transcript_text = '',
                text_storage_format = ?,
                transcript_text_compressed = NULL,
                recognized_word_count = ?
            WHERE id = ?;
            """
        )

        statement.bindText(VoiceHistoryTextStorageFormat.evicted, at: 1)
        statement.bindInt64(Int64(try row.resolvedWordCount()), at: 2)
        statement.bindText(row.id, at: 3)
        try statement.stepDone()
    }

    private func fetchEntrySummaries(from database: SQLiteConnection) throws -> [MeetingHistoryEntry] {
        let statement = try database.prepare(
            """
            SELECT id, created_at, duration, substr(transcript_text, 1, ?), status, source_flags_json, error_message, timings_json, model_metadata_json, recognized_word_count, speaker_count, text_storage_format, recovery_audio_json
            FROM meeting_history
            ORDER BY created_at DESC;
            """
        )

        statement.bindInt(Int32(Self.transcriptPreviewLimit), at: 1)

        var fetchedEntries: [MeetingHistoryEntry] = []
        while true {
            switch try statement.step() {
            case .row:
                fetchedEntries.append(try entrySummary(from: statement))
            case .done:
                return try entriesWithArchivedAudioURLs(fetchedEntries, from: database)
            }
        }
    }

    private func fetchEntry(id: MeetingHistoryEntry.ID, from database: SQLiteConnection) throws -> MeetingHistoryEntry? {
        let statement = try database.prepare(
            """
            SELECT id, created_at, duration, transcript_text, status, source_flags_json, error_message, timings_json, model_metadata_json, recognized_word_count, speaker_count, text_storage_format, transcript_text_compressed, recovery_audio_json
            FROM meeting_history
            WHERE id = ?;
            """
        )

        statement.bindText(id.uuidString, at: 1)

        switch try statement.step() {
        case .row:
            let entry = try entry(from: statement)
            return try entriesWithArchivedAudioURLs([entry], from: database).first
        case .done:
            return nil
        }
    }

    private func entriesWithArchivedAudioURLs(
        _ entries: [MeetingHistoryEntry],
        from database: SQLiteConnection
    ) throws -> [MeetingHistoryEntry] {
        let linksByID = try ArchivedAudioHistoryLinks.fetch(ownerKind: .meetingHistory, in: database)
        return entries.map { entry in
            var entry = entry
            entry.archivedAudioURLs = linksByID[entry.id] ?? []
            return entry
        }
    }

    private func fetchRecoveryAudio(id: MeetingHistoryEntry.ID, from database: SQLiteConnection) throws -> MeetingRecoveryAudioManifest? {
        let statement = try database.prepare(
            """
            SELECT recovery_audio_json
            FROM meeting_history
            WHERE id = ?;
            """
        )

        statement.bindText(id.uuidString, at: 1)

        switch try statement.step() {
        case .row:
            return try decodeOptional(MeetingRecoveryAudioManifest.self, from: statement.optionalString(at: 0))
        case .done:
            return nil
        }
    }

    private func fetchRecoveryAudioEntries(from database: SQLiteConnection) throws -> [MeetingRecoveryAudioEntry] {
        let statement = try database.prepare(
            """
            SELECT id, recovery_audio_json
            FROM meeting_history
            WHERE recovery_audio_json IS NOT NULL
            ORDER BY created_at DESC;
            """
        )

        var entries: [MeetingRecoveryAudioEntry] = []
        while true {
            switch try statement.step() {
            case .row:
                guard let id = UUID(uuidString: statement.string(at: 0)) else {
                    throw MeetingHistoryStoreError.invalidRow("Invalid meeting entry id")
                }
                guard let manifest = try decodeOptional(MeetingRecoveryAudioManifest.self, from: statement.optionalString(at: 1)) else {
                    throw MeetingHistoryStoreError.invalidRow("Invalid meeting recovery audio")
                }
                entries.append(MeetingRecoveryAudioEntry(id: id, manifest: manifest))
            case .done:
                return entries
            }
        }
    }

    private func entry(from statement: SQLiteStatement) throws -> MeetingHistoryEntry {
        guard let id = UUID(uuidString: statement.string(at: 0)) else {
            throw MeetingHistoryStoreError.invalidRow("Invalid meeting entry id")
        }

        let format = statement.string(at: 11)
        let storedText = try transcriptText(
            format: format,
            plainText: statement.string(at: 3),
            compressedText: statement.optionalData(at: 12)
        )

        return MeetingHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: statement.double(at: 1)),
            duration: statement.double(at: 2),
            transcriptText: storedText.text,
            status: MeetingRecordingStatus(rawValue: statement.string(at: 4)) ?? .failed,
            sourceFlags: try decode(MeetingSourceFlags.self, from: statement.string(at: 5)),
            errorMessage: statement.optionalString(at: 6),
            timings: try decodeOptional(MeetingPipelineTimings.self, from: statement.optionalString(at: 7)),
            modelMetadata: try decodeOptional(VoiceTranscriptionModelMetadata.self, from: statement.optionalString(at: 8)),
            recognizedWordCount: statement.optionalInt(at: 9),
            speakerCount: statement.optionalInt(at: 10),
            recoveryAudio: try decodeOptional(MeetingRecoveryAudioManifest.self, from: statement.optionalString(at: 13)),
            isTextPayloadEvicted: storedText.isEvicted
        )
    }

    private func entrySummary(from statement: SQLiteStatement) throws -> MeetingHistoryEntry {
        guard let id = UUID(uuidString: statement.string(at: 0)) else {
            throw MeetingHistoryStoreError.invalidRow("Invalid meeting entry id")
        }

        let format = statement.string(at: 11)
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
            transcriptPreview = statement.string(at: 3)
            isTextPayloadEvicted = false
        }

        return MeetingHistoryEntry(
            id: id,
            createdAt: Date(timeIntervalSince1970: statement.double(at: 1)),
            duration: statement.double(at: 2),
            transcriptText: transcriptPreview,
            status: MeetingRecordingStatus(rawValue: statement.string(at: 4)) ?? .failed,
            sourceFlags: try decode(MeetingSourceFlags.self, from: statement.string(at: 5)),
            errorMessage: statement.optionalString(at: 6),
            timings: try decodeOptional(MeetingPipelineTimings.self, from: statement.optionalString(at: 7)),
            modelMetadata: try decodeOptional(VoiceTranscriptionModelMetadata.self, from: statement.optionalString(at: 8)),
            recognizedWordCount: statement.optionalInt(at: 9),
            speakerCount: statement.optionalInt(at: 10),
            recoveryAudio: try decodeOptional(MeetingRecoveryAudioManifest.self, from: statement.optionalString(at: 12)),
            isTextPayloadEvicted: isTextPayloadEvicted
        )
    }

    private func transcriptText(
        format: String,
        plainText: String,
        compressedText: Data?
    ) throws -> (text: String, isEvicted: Bool) {
        let payload = StoredTextPayload(
            format: format,
            components: [
                StoredTextComponent(plainText: plainText, compressedText: compressedText)
            ],
            missingCompressedPayloadError: {
                MeetingHistoryStoreError.invalidRow("Compressed meeting transcript is missing payload")
            }
        )
        let texts = try payload.resolvedTexts()
        return (texts.first ?? "", payload.isEvicted)
    }

    private func fetchStorageStats(from database: SQLiteConnection) throws -> VoiceHistoryStorageStats {
        let statement = try database.prepare(
            """
            SELECT
                COUNT(*),
                COALESCE(SUM(length(CAST(transcript_text AS BLOB))), 0),
                COALESCE(SUM(COALESCE(length(transcript_text_compressed), 0)), 0)
            FROM meeting_history;
            """
        )

        guard try statement.step() == .row else {
            throw MeetingHistoryStoreError.sqlite("Unable to read meeting history storage stats")
        }

        return VoiceHistoryStorageStats(
            entryCount: statement.int(at: 0),
            plainTextBytes: Int(statement.int64(at: 1)),
            compressedTextBytes: Int(statement.int64(at: 2)),
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

    private func clearRecoveryAudio(id: MeetingHistoryEntry.ID, in database: SQLiteConnection) throws {
        let statement = try database.prepare(
            """
            UPDATE meeting_history
            SET recovery_audio_json = NULL
            WHERE id = ?;
            """
        )

        statement.bindText(id.uuidString, at: 1)
        try statement.stepDone()
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
        payload.byteCount
    }

    func resolvedWordCount() throws -> Int {
        if let recognizedWordCount {
            return recognizedWordCount
        }

        return VoiceHistoryEntry.wordCount(in: try payload.preferredText())
    }

    private var payload: StoredTextPayload {
        StoredTextPayload(
            format: textStorageFormat,
            components: [
                StoredTextComponent(plainText: transcriptText, compressedText: compressedTranscriptText)
            ],
            missingCompressedPayloadError: {
                MeetingHistoryStoreError.invalidRow("Compressed meeting transcript is missing payload")
            }
        )
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
