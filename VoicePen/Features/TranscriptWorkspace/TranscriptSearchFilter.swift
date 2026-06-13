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
            stableDayText(for: date),
            stableTimeText(for: date)
        ]
    }

    private static let stableCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static func stableDayText(for date: Date) -> String {
        let components = stableCalendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func stableTimeText(for date: Date) -> String {
        let components = stableCalendar.dateComponents([.hour, .minute], from: date)
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }
}
