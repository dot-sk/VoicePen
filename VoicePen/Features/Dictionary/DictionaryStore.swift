import Combine
import Foundation
import SQLite3

@MainActor
final class DictionaryStore: ObservableObject {
    @Published private(set) var dictionary = DictionaryFile(entries: [])

    private let databaseURL: URL
    private let fileManager: FileManager
    private let glossaryBuilder: PromptGlossaryBuilder

    init(
        dictionaryURL: URL,
        fileManager: FileManager = .default,
        glossaryBuilder: PromptGlossaryBuilder? = nil
    ) {
        self.databaseURL = dictionaryURL
        self.fileManager = fileManager
        self.glossaryBuilder = glossaryBuilder ?? PromptGlossaryBuilder()
    }

    var entries: [TermEntry] {
        dictionary.entries
    }

    func load() throws {
        dictionary = try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try seedSampleDictionaryIfNeeded(in: database)
            return try fetchDictionary(from: database)
        }
    }

    func save() throws {
        try replaceDictionary(dictionary)
    }

    func replaceDictionary(_ newDictionary: DictionaryFile) throws {
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try execute("BEGIN IMMEDIATE TRANSACTION;", in: database)
            do {
                try execute("DELETE FROM dictionary_entries;", in: database)
                for entry in newDictionary.entries {
                    try insert(entry, into: database)
                }
                try execute("COMMIT;", in: database)
            } catch {
                try? execute("ROLLBACK;", in: database)
                throw error
            }
        }
        dictionary = newDictionary
    }

    func upsertEntry(_ entry: TermEntry) throws {
        var entries = dictionary.entries.filter { $0.id != entry.id }
        entries.append(entry)
        entries.sort { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
        try replaceDictionary(DictionaryFile(entries: entries))
    }

    func importEntries(_ importedEntries: [TermEntry]) throws {
        var entriesByCanonical: [String: TermEntry] = [:]
        for entry in dictionary.entries {
            entriesByCanonical[entry.canonical.lowercased()] = entry
        }

        for entry in importedEntries {
            entriesByCanonical[entry.canonical.lowercased()] = entry
        }

        let entries = entriesByCanonical.values.sorted {
            $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending
        }
        try replaceDictionary(DictionaryFile(entries: entries))
    }

    func deleteEntry(id: String) throws {
        let entries = dictionary.entries.filter { $0.id != id }
        try replaceDictionary(DictionaryFile(entries: entries))
    }

    func promptGlossary(limit: Int, language: String = "en") throws -> String {
        glossaryBuilder.build(entries: entries, limit: limit, language: language)
    }

    func makeNormalizer() -> TermNormalizer {
        TermNormalizer(entries: entries)
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
            throw DictionaryStoreError.sqlite(message)
        }

        defer {
            sqlite3_close(database)
        }

        return try body(database)
    }

    private func seedSampleDictionaryIfNeeded(in database: OpaquePointer) throws {
        let count = try dictionaryEntryCount(in: database)
        guard count == 0 else { return }

        for entry in Self.sampleDictionary.entries {
            try insert(entry, into: database)
        }
    }

    private func fetchDictionary(from database: OpaquePointer) throws -> DictionaryFile {
        DictionaryFile(
            entries: try fetchEntries(from: database)
        )
    }

    private func dictionaryEntryCount(in database: OpaquePointer) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM dictionary_entries;", in: database)
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw DictionaryStoreError.invalidRow("Unable to count dictionary entries")
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func insert(_ entry: TermEntry, into database: OpaquePointer) throws {
        let statement = try prepare(
            """
            INSERT OR REPLACE INTO dictionary_entries (
                id,
                canonical,
                variants
            ) VALUES (?, ?, ?);
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, entry.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, entry.canonical, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, entry.variants.joined(separator: "\n"), -1, SQLITE_TRANSIENT)

        try stepDone(statement, database: database)
    }

    private func fetchEntries(from database: OpaquePointer) throws -> [TermEntry] {
        let statement = try prepare(
            """
            SELECT id, canonical, variants
            FROM dictionary_entries
            ORDER BY canonical COLLATE NOCASE ASC;
            """,
            in: database
        )
        defer { sqlite3_finalize(statement) }

        var entries: [TermEntry] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                entries.append(
                    TermEntry(
                        id: stringColumn(statement, index: 0),
                        canonical: stringColumn(statement, index: 1),
                        variants: splitList(stringColumn(statement, index: 2))
                    )
                )
            case SQLITE_DONE:
                return entries
            default:
                throw DictionaryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
            }
        }
    }

    private func splitList(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw DictionaryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func prepare(_ sql: String, in database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw DictionaryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DictionaryStoreError.sqlite(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func stringColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }

    private static let sampleDictionary = DictionaryFile(
        entries: [
            TermEntry(
                id: "postgresql",
                canonical: "PostgreSQL",
                variants: ["постгрес", "постгресе", "постгресом", "постгреса", "постгресу", "постгрескуэль", "postgres", "postgre sequel", "Postgres", "postgre sql", "Postgre SQL"]
            ),
            TermEntry(
                id: "typescript",
                canonical: "TypeScript",
                variants: ["тайпскрипт", "тайп скрипт", "type script", "Typescript"]
            ),
            TermEntry(
                id: "nextjs",
                canonical: "Next.js",
                variants: ["некст джей эс", "next js", "nextjs", "NextJS", "Next JS"]
            ),
            TermEntry(
                id: "trpc",
                canonical: "tRPC",
                variants: ["ти ар пи си", "т р п с", "trpc", "TRPC", "t rpc", "t-rpc"]
            ),
            TermEntry(
                id: "prisma",
                canonical: "Prisma",
                variants: ["призма", "prisma", "Prisma ORM", "призма orm"]
            ),
            TermEntry(
                id: "redis",
                canonical: "Redis",
                variants: ["редис", "redis", "REDIS"]
            )
        ]
    )
}

private enum DictionaryStoreError: LocalizedError {
    case sqlite(String)
    case invalidRow(String)

    var errorDescription: String? {
        switch self {
        case let .sqlite(message):
            return "Dictionary database error: \(message)"
        case let .invalidRow(message):
            return "Invalid dictionary database row: \(message)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
