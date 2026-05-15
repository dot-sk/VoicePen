import Foundation

nonisolated struct TranscriptSearchDocument: Equatable, Sendable {
    var fields: [String]
}

nonisolated struct TranscriptSearchFilter: Equatable, Sendable {
    var query: String

    init(query: String = "") {
        self.query = query
    }

    func filteredEntries<Entry>(
        from entries: [Entry],
        document: (Entry) -> TranscriptSearchDocument
    ) -> [Entry] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return entries }

        return entries.filter { entry in
            document(entry).fields.contains { field in
                field.localizedStandardContains(normalizedQuery)
            }
        }
    }
}

nonisolated enum TranscriptSearchFieldText {
    static func dateText(for date: Date) -> [String] {
        [
            date.formatted(date: .abbreviated, time: .shortened),
            date.formatted(date: .numeric, time: .shortened),
            date.formatted(date: .complete, time: .omitted),
            stableDateFormatter(format: "yyyy-MM-dd").string(from: date),
            stableDateFormatter(format: "HH:mm").string(from: date)
        ]
    }

    private static func stableDateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
