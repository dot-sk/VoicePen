import Foundation

nonisolated struct HistoryDayGroup<Entry: Sendable>: Sendable {
    var day: Date
    var title: String
    var entries: [Entry]
}

nonisolated struct HistoryDayGroups<Entry: Sendable>: Sendable {
    let groups: [HistoryDayGroup<Entry>]

    init(
        entries: [Entry],
        now: Date,
        calendar: Calendar = .current,
        date: (Entry) -> Date
    ) {
        var groups: [HistoryDayGroup<Entry>] = []

        for entry in entries {
            let day = calendar.startOfDay(for: date(entry))

            if groups.indices.last.map({ calendar.isDate(groups[$0].day, inSameDayAs: day) }) == true {
                groups[groups.count - 1].entries.append(entry)
            } else {
                groups.append(
                    HistoryDayGroup(
                        day: day,
                        title: Self.title(for: day, now: now, calendar: calendar),
                        entries: [entry]
                    )
                )
            }
        }

        self.groups = groups
    }

    private static func title(for day: Date, now: Date, calendar: Calendar) -> String {
        let today = calendar.startOfDay(for: now)
        if calendar.isDate(day, inSameDayAs: today) {
            return "Today"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            calendar.isDate(day, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }

        return day.formatted(.dateTime.year().month(.abbreviated).day())
    }
}
