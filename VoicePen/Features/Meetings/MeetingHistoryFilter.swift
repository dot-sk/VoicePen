import Foundation

nonisolated struct MeetingHistoryFilter: Equatable, Sendable {
    var query: String

    init(query: String = "") {
        self.query = query
    }

    func filteredEntries(from entries: [MeetingHistoryEntry]) -> [MeetingHistoryEntry] {
        TranscriptSearchFilter(query: query).filteredEntries(from: entries) { entry in
            MeetingHistorySearchDocument.document(for: entry)
        }
    }
}

nonisolated enum MeetingHistorySearchDocument {
    static func document(for entry: MeetingHistoryEntry) -> TranscriptSearchDocument {
        TranscriptSearchDocument(fields: searchableText(for: entry))
    }

    private static func searchableText(for entry: MeetingHistoryEntry) -> [String] {
        var text = [
            entry.transcriptText,
            entry.previewText,
            entry.errorMessage ?? "",
            entry.status.title,
            durationText(entry.duration),
            entry.modelMetadata?.displayName ?? ""
        ]

        text.append(sourceText(label: "Microphone", isCaptured: entry.sourceFlags.microphoneCaptured))
        text.append(sourceText(label: "System audio", isCaptured: entry.sourceFlags.systemAudioCaptured))
        text.append(contentsOf: TranscriptSearchFieldText.dateText(for: entry.createdAt))

        if let appVersion = entry.modelMetadata?.visibleAppVersion {
            text.append(appVersion)
        }

        return text
    }

    private static func sourceText(label: String, isCaptured: Bool) -> String {
        let status = isCaptured ? "Captured" : "Not captured"
        return "\(label) \(status)"
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(0, duration)
        if seconds < 60 {
            return "\(displayedSeconds(seconds)) sec"
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private static func displayedSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else {
            return 0
        }
        return max(1, Int(seconds.rounded()))
    }
}
