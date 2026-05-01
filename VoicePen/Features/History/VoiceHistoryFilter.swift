import Foundation

nonisolated struct VoiceHistoryFilter: Equatable, Sendable {
    var query: String
    var status: VoiceHistoryStatus?

    init(query: String = "", status: VoiceHistoryStatus? = nil) {
        self.query = query
        self.status = status
    }

    func filteredEntries(from entries: [VoiceHistoryEntry]) -> [VoiceHistoryEntry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            matchesStatus(entry) && matchesQuery(entry, query: normalizedQuery)
        }
    }

    private func matchesStatus(_ entry: VoiceHistoryEntry) -> Bool {
        guard let status else { return true }
        return entry.status == status
    }

    private func matchesQuery(_ entry: VoiceHistoryEntry, query: String) -> Bool {
        guard !query.isEmpty else { return true }

        return [
            entry.rawText,
            entry.finalText,
            entry.errorMessage ?? "",
            entry.status.title
        ]
        .contains { text in
            text.localizedStandardContains(query)
        }
    }
}
