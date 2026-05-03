import Foundation

nonisolated struct DictionaryReviewPromptHistoryEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var rawText: String
    var finalText: String
    var status: VoiceHistoryStatus
    var modelMetadata: VoiceTranscriptionModelMetadata?

    init(
        id: UUID,
        createdAt: Date,
        rawText: String,
        finalText: String,
        status: VoiceHistoryStatus,
        modelMetadata: VoiceTranscriptionModelMetadata? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.finalText = finalText
        self.status = status
        self.modelMetadata = modelMetadata
    }

    init(_ entry: VoiceHistoryEntry, modelMetadata: VoiceTranscriptionModelMetadata? = nil) {
        self.init(
            id: entry.id,
            createdAt: entry.createdAt,
            rawText: entry.rawText,
            finalText: entry.finalText,
            status: entry.status,
            modelMetadata: modelMetadata ?? entry.modelMetadata
        )
    }
}

nonisolated struct DictionaryReviewPromptBuilder {
    func build(
        preset: DictionaryReviewPromptPreset = .dictionaryImprovement,
        dictionaryEntries: [TermEntry],
        historyEntries: [VoiceHistoryEntry],
        historyLimit: HistoryReviewLimit = .defaultValue
    ) -> String {
        build(
            preset: preset,
            dictionaryEntries: dictionaryEntries,
            promptHistoryEntries: historyEntries.map { DictionaryReviewPromptHistoryEntry($0) },
            historyLimit: historyLimit
        )
    }

    func build(
        preset: DictionaryReviewPromptPreset = .dictionaryImprovement,
        dictionaryEntries: [TermEntry],
        promptHistoryEntries historyEntries: [DictionaryReviewPromptHistoryEntry],
        historyLimit: HistoryReviewLimit = .defaultValue
    ) -> String {
        let dictionaryCSV = dictionaryRows(from: dictionaryEntries)
        let eligibleHistoryRows = eligibleHistoryEntries(from: historyEntries, limit: historyLimit)
        let historyCSV = historyRows(from: eligibleHistoryRows)

        return """
            Dictionary Review Prompt

            Privacy:
            This prompt is copied to the local clipboard and may contain transcription history. VoicePen does not send it anywhere automatically.

            Preset:
            \(preset.title)

            \(preset.reviewInstructions)

            CSV-only response contract:
            Return only CSV. No markdown, prose, explanations, or extra columns.
            Header:
            canonical,variants
            Rows: one canonical value plus at least one variant; separate variants with semicolons.
            Quote fields containing commas or quotes; escape quotes by doubling them.
            Do not duplicate current dictionary entries.

            Current dictionary entries:
            ```csv
            canonical,variants
            \(dictionaryCSV)
            ```

            Recent eligible transcription history, newest first, limited to \(historyLimit.rawValue) entries:
            ```csv
            raw_text,final_text
            \(historyCSV)
            ```
            """
    }

    private func eligibleHistoryEntries(
        from entries: [DictionaryReviewPromptHistoryEntry],
        limit: HistoryReviewLimit
    ) -> [DictionaryReviewPromptHistoryEntry] {
        entries
            .filter { entry in
                entry.status == .insertAttempted
                    && !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !entry.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(limit.rawValue)
            .map { entry in
                DictionaryReviewPromptHistoryEntry(
                    id: entry.id,
                    createdAt: entry.createdAt,
                    rawText: entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines),
                    finalText: entry.finalText.trimmingCharacters(in: .whitespacesAndNewlines),
                    status: entry.status,
                    modelMetadata: entry.modelMetadata
                )
            }
    }

    private func dictionaryRows(from entries: [TermEntry]) -> String {
        entries
            .sorted { lhs, rhs in
                let comparison = lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.id < rhs.id
            }
            .map { entry in
                csvRow([entry.canonical, entry.variants.joined(separator: "; ")])
            }
            .joined(separator: "\n")
    }

    private func historyRows(from entries: [DictionaryReviewPromptHistoryEntry]) -> String {
        entries
            .map { entry in
                return csvRow([
                    entry.rawText,
                    entry.finalText
                ])
            }
            .joined(separator: "\n")
    }

    private func csvRow(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }

        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

}
