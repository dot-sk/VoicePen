import Foundation

nonisolated struct DictionaryEntryFilter: Equatable, Sendable {
    var query: String

    init(query: String = "") {
        self.query = query
    }

    func filteredEntries(from entries: [TermEntry]) -> [TermEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter { entry in
            ([entry.canonical] + entry.variants)
                .contains { $0.localizedStandardContains(normalizedQuery) }
        }
    }
}
