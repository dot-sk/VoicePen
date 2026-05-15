import Foundation

nonisolated struct VoiceHistoryFilter: Equatable, Sendable {
    var query: String
    var status: VoiceHistoryStatus?

    init(query: String = "", status: VoiceHistoryStatus? = nil) {
        self.query = query
        self.status = status
    }

    func filteredEntries(from entries: [VoiceHistoryEntry]) -> [VoiceHistoryEntry] {
        let matchingStatusEntries = entries.filter { entry in
            matchesStatus(entry)
        }

        return TranscriptSearchFilter(query: query)
            .filteredEntries(from: matchingStatusEntries) { entry in
                VoiceHistorySearchDocument.document(for: entry)
            }
    }

    private func matchesStatus(_ entry: VoiceHistoryEntry) -> Bool {
        guard let status else { return true }
        return entry.status == status
    }

}

nonisolated enum VoiceHistorySearchDocument {
    static func document(for entry: VoiceHistoryEntry) -> TranscriptSearchDocument {
        var fields = [
            entry.finalText,
            entry.errorMessage ?? "",
            entry.status.title
        ]

        fields.append(contentsOf: TranscriptSearchFieldText.dateText(for: entry.createdAt))

        if let duration = entry.duration {
            fields.append(durationText(duration))
        }
        if let modelDisplayName = entry.modelMetadata?.displayName {
            fields.append(modelDisplayName)
        }
        if let appVersion = entry.modelMetadata?.visibleAppVersion {
            fields.append(appVersion)
        }

        return TranscriptSearchDocument(fields: fields)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", max(0, duration))
    }
}
