import Foundation

nonisolated enum ArchivedAudioLinkOwnerKind: String, Sendable {
    case voiceHistory = "voice_history"
    case meetingHistory = "meeting_history"
}

nonisolated enum ArchivedAudioHistoryLinks {
    static func insert(
        url: URL,
        ownerKind: ArchivedAudioLinkOwnerKind,
        ownerID: UUID,
        in database: SQLiteConnection,
        createdAt: Date = Date()
    ) throws {
        let statement = try database.prepare(
            """
            INSERT OR IGNORE INTO archived_audio_links (
                owner_kind,
                owner_id,
                url,
                created_at
            ) VALUES (?, ?, ?, ?);
            """
        )

        statement.bindText(ownerKind.rawValue, at: 1)
        statement.bindText(ownerID.uuidString, at: 2)
        statement.bindText(url.path, at: 3)
        statement.bindDouble(createdAt.timeIntervalSince1970, at: 4)
        try statement.stepDone()
    }

    static func delete(
        ownerKind: ArchivedAudioLinkOwnerKind,
        ownerID: UUID,
        in database: SQLiteConnection
    ) throws {
        let statement = try database.prepare(
            """
            DELETE FROM archived_audio_links
            WHERE owner_kind = ? AND owner_id = ?;
            """
        )

        statement.bindText(ownerKind.rawValue, at: 1)
        statement.bindText(ownerID.uuidString, at: 2)
        try statement.stepDone()
    }

    static func deleteAll(
        ownerKind: ArchivedAudioLinkOwnerKind,
        in database: SQLiteConnection
    ) throws {
        let statement = try database.prepare(
            """
            DELETE FROM archived_audio_links
            WHERE owner_kind = ?;
            """
        )

        statement.bindText(ownerKind.rawValue, at: 1)
        try statement.stepDone()
    }

    static func fetch(
        ownerKind: ArchivedAudioLinkOwnerKind,
        in database: SQLiteConnection
    ) throws -> [UUID: [URL]] {
        let statement = try database.prepare(
            """
            SELECT owner_id, url
            FROM archived_audio_links
            WHERE owner_kind = ?
            ORDER BY created_at ASC, url ASC;
            """
        )

        statement.bindText(ownerKind.rawValue, at: 1)

        var links: [UUID: [URL]] = [:]
        while true {
            switch try statement.step() {
            case .row:
                guard let ownerID = UUID(uuidString: statement.string(at: 0)) else {
                    continue
                }
                links[ownerID, default: []].append(URL(fileURLWithPath: statement.string(at: 1)))
            case .done:
                return links
            }
        }
    }
}
