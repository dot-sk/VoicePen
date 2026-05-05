import Foundation

nonisolated struct VoiceHistoryEntryAgeGroups: Equatable, Sendable {
    static let defaultOlderThan: TimeInterval = 7 * 24 * 60 * 60

    let recent: [VoiceHistoryEntry]
    let older: [VoiceHistoryEntry]

    init(
        entries: [VoiceHistoryEntry],
        now: Date,
        olderThan: TimeInterval = Self.defaultOlderThan
    ) {
        let cutoff = now.addingTimeInterval(-olderThan)
        var recent: [VoiceHistoryEntry] = []
        var older: [VoiceHistoryEntry] = []

        for entry in entries {
            if entry.createdAt < cutoff {
                older.append(entry)
            } else {
                recent.append(entry)
            }
        }

        self.recent = recent
        self.older = older
    }
}
