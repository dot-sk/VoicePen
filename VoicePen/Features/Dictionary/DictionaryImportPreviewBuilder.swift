import Foundation

nonisolated struct DictionaryImportPreview: Equatable, Sendable {
    var importedEntryCount: Int
    var importedEntries: [TermEntry]
    var postImportEntries: [TermEntry]
    var affectedEntryCount: Int
    var examples: [DictionaryImportPreviewExample]
}

nonisolated struct DictionaryImportPreviewExample: Equatable, Sendable {
    var historyEntryID: VoiceHistoryEntry.ID
    var createdAt: Date
    var rawText: String
    var currentFinalText: String
    var simulatedFinalText: String
    var diff: [DictionaryWordDiffToken]
}

nonisolated struct DictionaryImportPreviewBuilder: Sendable {
    private let exampleLimit: Int
    private let mergeEntries: @Sendable ([TermEntry], [TermEntry]) -> [TermEntry]

    init(
        exampleLimit: Int = 10,
        mergeEntries: @escaping @Sendable ([TermEntry], [TermEntry]) -> [TermEntry] = {
            DictionaryMerger().merge(currentEntries: $0, pendingEntries: $1)
        }
    ) {
        self.exampleLimit = max(0, exampleLimit)
        self.mergeEntries = mergeEntries
    }

    func build(
        currentEntries: [TermEntry],
        pendingEntries: [TermEntry],
        historyEntries: [VoiceHistoryEntry],
        limit: Int
    ) throws -> DictionaryImportPreview {
        let postImportEntries = mergeEntries(currentEntries, pendingEntries)
        let normalizer = TermNormalizer(entries: postImportEntries)
        let eligibleEntries = Self.eligibleEntries(from: historyEntries, limit: limit)

        var affectedEntryCount = 0
        var examples: [DictionaryImportPreviewExample] = []

        for entry in eligibleEntries {
            let simulatedFinalText = try normalizer.normalize(entry.rawText)
            guard simulatedFinalText != entry.finalText else { continue }

            affectedEntryCount += 1
            if examples.count < exampleLimit {
                examples.append(
                    DictionaryImportPreviewExample(
                        historyEntryID: entry.id,
                        createdAt: entry.createdAt,
                        rawText: entry.rawText,
                        currentFinalText: entry.finalText,
                        simulatedFinalText: simulatedFinalText,
                        diff: DictionaryWordDiff.compare(
                            from: entry.finalText,
                            to: simulatedFinalText
                        )
                    )
                )
            }
        }

        return DictionaryImportPreview(
            importedEntryCount: pendingEntries.count,
            importedEntries: pendingEntries,
            postImportEntries: postImportEntries,
            affectedEntryCount: affectedEntryCount,
            examples: examples
        )
    }

    private static func eligibleEntries(from entries: [VoiceHistoryEntry], limit: Int) -> [VoiceHistoryEntry] {
        guard limit > 0 else { return [] }

        return entries
            .filter { entry in
                entry.status == .insertAttempted &&
                    !entry.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !entry.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            }
            .prefix(limit)
            .map { $0 }
    }
}
