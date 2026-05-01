import Foundation
import SQLite3

nonisolated enum DatabaseMigrator {
    static let currentSchemaVersion = 3

    private static let migrations: [DatabaseMigration] = [
        DatabaseMigration(
            version: 1,
            name: "Initial VoicePen schema",
            statements: [
                """
                CREATE TABLE IF NOT EXISTS app_settings (
                    key TEXT PRIMARY KEY NOT NULL,
                    value TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS dictionary_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    canonical TEXT NOT NULL,
                    variants TEXT NOT NULL
                );
                """,
                """
                CREATE INDEX IF NOT EXISTS idx_dictionary_entries_canonical
                ON dictionary_entries(canonical COLLATE NOCASE ASC);
                """,
                """
                CREATE TABLE IF NOT EXISTS voice_history (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at REAL NOT NULL,
                    duration REAL,
                    raw_text TEXT NOT NULL,
                    final_text TEXT NOT NULL,
                    status TEXT NOT NULL,
                    error_message TEXT
                );
                """,
                """
                CREATE INDEX IF NOT EXISTS idx_voice_history_created_at
                ON voice_history(created_at DESC);
                """
            ]
        ),
        DatabaseMigration(
            version: 2,
            name: "Simplify dictionary schema",
            statements: [
                "DROP TABLE IF EXISTS dictionary_entries;",
                """
                CREATE TABLE dictionary_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    canonical TEXT NOT NULL,
                    variants TEXT NOT NULL
                );
                """,
                """
                CREATE INDEX IF NOT EXISTS idx_dictionary_entries_canonical
                ON dictionary_entries(canonical COLLATE NOCASE ASC);
                """
            ]
        ),
        DatabaseMigration(
            version: 3,
            name: "Add voice pipeline timings",
            statements: [
                """
                ALTER TABLE voice_history
                ADD COLUMN timings_json TEXT;
                """
            ]
        )
    ]

    static func migrate(_ database: OpaquePointer) throws {
        let initialVersion = try userVersion(in: database)
        guard initialVersion <= currentSchemaVersion else {
            throw DatabaseMigrationError.unsupportedFutureVersion(
                databaseVersion: initialVersion,
                appVersion: currentSchemaVersion
            )
        }

        for migration in migrations where migration.version > initialVersion {
            try run(migration, in: database)
        }
    }

    static func userVersion(in database: OpaquePointer) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DatabaseMigrationError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DatabaseMigrationError.sqlite(String(cString: sqlite3_errmsg(database)))
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private static func run(_ migration: DatabaseMigration, in database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;", in: database)
        do {
            for statement in migration.statements {
                try execute(statement, in: database)
            }
            try execute("PRAGMA user_version = \(migration.version);", in: database)
            try execute("COMMIT;", in: database)
        } catch {
            try? execute("ROLLBACK;", in: database)
            throw DatabaseMigrationError.failed(version: migration.version, name: migration.name, underlying: error)
        }
    }

    private static func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw DatabaseMigrationError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }
}

nonisolated struct DatabaseMigration {
    let version: Int
    let name: String
    let statements: [String]
}

enum DatabaseMigrationError: LocalizedError {
    case sqlite(String)
    case unsupportedFutureVersion(databaseVersion: Int, appVersion: Int)
    case failed(version: Int, name: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "Database migration error: \(message)"
        case let .unsupportedFutureVersion(databaseVersion, appVersion):
            return "Database schema version \(databaseVersion) is newer than this VoicePen build supports (\(appVersion))."
        case let .failed(version, name, underlying):
            return "Database migration \(version) (\(name)) failed: \(underlying.localizedDescription)"
        }
    }
}
