import Combine
import Foundation

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
        let normalizedDictionary = DictionaryFile(entries: DictionaryMerger.normalizedEntries(newDictionary.entries))
        try withDatabase { database in
            try DatabaseMigrator.migrate(database)
            try database.transaction {
                try database.execute("DELETE FROM dictionary_entries;")
                for entry in normalizedDictionary.entries {
                    try insert(entry, into: database)
                }
            }
        }
        dictionary = normalizedDictionary
    }

    func upsertEntry(_ entry: TermEntry) throws {
        try replaceDictionary(DictionaryFile(entries: dictionary.entries + [entry]))
    }

    func importEntries(_ importedEntries: [TermEntry]) throws {
        let mergedEntries = try DictionaryMerger.mergedEntries(
            existingEntries: dictionary.entries,
            importedEntries: importedEntries
        )
        try replaceDictionary(DictionaryFile(entries: mergedEntries))
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

    private func withDatabase<T>(_ body: (SQLiteConnection) throws -> T) throws -> T {
        let database = try SQLiteConnection.open(
            at: databaseURL,
            fileManager: fileManager,
            makeError: DictionaryStoreError.sqlite
        )
        return try body(database)
    }

    private func seedSampleDictionaryIfNeeded(in database: SQLiteConnection) throws {
        let count = try dictionaryEntryCount(in: database)
        guard count == 0 else { return }

        for entry in Self.sampleDictionary.entries {
            try insert(entry, into: database)
        }
    }

    private func fetchDictionary(from database: SQLiteConnection) throws -> DictionaryFile {
        DictionaryFile(
            entries: try fetchEntries(from: database)
        )
    }

    private func dictionaryEntryCount(in database: SQLiteConnection) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM dictionary_entries;")

        guard try statement.step() == .row else {
            throw DictionaryStoreError.invalidRow("Unable to count dictionary entries")
        }
        return statement.int(at: 0)
    }

    private func insert(_ entry: TermEntry, into database: SQLiteConnection) throws {
        let statement = try database.prepare(
            """
            INSERT OR REPLACE INTO dictionary_entries (
                id,
                canonical,
                variants
            ) VALUES (?, ?, ?);
            """
        )

        statement.bindText(entry.id, at: 1)
        statement.bindText(entry.canonical, at: 2)
        statement.bindText(entry.variants.joined(separator: "\n"), at: 3)

        try statement.stepDone()
    }

    private func fetchEntries(from database: SQLiteConnection) throws -> [TermEntry] {
        let statement = try database.prepare(
            """
            SELECT id, canonical, variants
            FROM dictionary_entries
            ORDER BY canonical COLLATE NOCASE ASC;
            """
        )

        var entries: [TermEntry] = []
        while true {
            switch try statement.step() {
            case .row:
                entries.append(
                    TermEntry(
                        id: statement.string(at: 0),
                        canonical: statement.string(at: 1),
                        variants: splitList(statement.string(at: 2))
                    )
                )
            case .done:
                return entries
            }
        }
    }

    private func splitList(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static let sampleDictionary = DictionaryFile(
        entries: [
            TermEntry(
                id: "postgresql",
                canonical: "PostgreSQL",
                variants: [
                    "постгрес", "постгресе", "постгресом", "постгреса", "постгресу", "постгрескуэль", "postgres", "postgre sequel", "Postgres", "postgre sql", "Postgre SQL"
                ]
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
