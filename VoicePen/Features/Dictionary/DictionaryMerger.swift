import Foundation

nonisolated struct DictionaryMerger: Sendable {
    func merge(currentEntries: [TermEntry], pendingEntries: [TermEntry]) -> [TermEntry] {
        Self.normalizedEntries(currentEntries + pendingEntries)
    }

    static func normalizedEntries(_ entries: [TermEntry]) -> [TermEntry] {
        var order: [String] = []
        var entriesByCanonicalKey: [String: TermEntry] = [:]

        for entry in entries {
            let canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !canonical.isEmpty else { continue }

            let key = normalizedKey(canonical)
            if entriesByCanonicalKey[key] == nil {
                order.append(key)
            }

            entriesByCanonicalKey[key] = TermEntry(
                id: normalizedID(entry.id),
                canonical: canonical,
                variants: uniquedVariants(entry.variants)
            )
        }

        var normalizedEntries = order.compactMap { entriesByCanonicalKey[$0] }
        var ownerByVariantKey: [String: Int] = [:]

        for entryIndex in normalizedEntries.indices {
            var keptVariants: [String] = []
            for variant in normalizedEntries[entryIndex].variants {
                let key = normalizedKey(variant)
                if let previousOwner = ownerByVariantKey[key] {
                    normalizedEntries[previousOwner].variants.removeAll {
                        normalizedKey($0) == key
                    }
                }

                ownerByVariantKey[key] = entryIndex
                keptVariants.append(variant)
            }
            normalizedEntries[entryIndex].variants = keptVariants
        }

        return normalizedEntries.sorted {
            $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending
        }
    }

    static func mergedEntries(existingEntries: [TermEntry], importedEntries: [TermEntry]) throws -> [TermEntry] {
        try validateImportedEntries(importedEntries)
        return normalizedEntries(existingEntries + importedEntries)
    }

    static func validateImportedEntries(_ entries: [TermEntry]) throws {
        guard !entries.isEmpty else {
            throw DictionaryImportValidationError.emptyImport
        }

        for entry in entries {
            guard !entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DictionaryImportValidationError.missingRequiredFields
            }

            guard entry.variants.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw DictionaryImportValidationError.missingRequiredFields
            }
        }
    }

    private static func normalizedID(_ id: String) -> String {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedID.isEmpty ? UUID().uuidString : trimmedID
    }

    private static func uniquedVariants(_ variants: [String]) -> [String] {
        var seenKeys: Set<String> = []
        var result: [String] = []

        for variant in variants {
            let trimmedVariant = variant.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedVariant.isEmpty else { continue }

            let key = normalizedKey(trimmedVariant)
            guard seenKeys.insert(key).inserted else { continue }
            result.append(trimmedVariant)
        }

        return result
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

nonisolated enum DictionaryImportValidationError: LocalizedError, Equatable, Sendable {
    case emptyImport
    case missingRequiredFields

    var errorDescription: String? {
        switch self {
        case .emptyImport:
            return "The import does not contain dictionary terms."
        case .missingRequiredFields:
            return "Every imported dictionary term must include a canonical value and at least one variant."
        }
    }
}
