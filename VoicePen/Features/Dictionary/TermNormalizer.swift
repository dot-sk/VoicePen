import Foundation

nonisolated struct TermNormalizer {
    private let entries: [TermEntry]

    init(entries: [TermEntry]) {
        self.entries = entries
    }

    func normalize(_ rawText: String) throws -> String {
        var normalized = rawText
        let activeEntries = entries
            .sorted { lhs, rhs in
                if lhs.canonical.count == rhs.canonical.count {
                    return lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical) == .orderedAscending
                }
                return lhs.canonical.count > rhs.canonical.count
            }

        for entry in activeEntries {
            let variants = entry.variants
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted {
                    if $0.count == $1.count {
                        return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    }
                    return $0.count > $1.count
                }

            for variant in variants {
                let escaped = NSRegularExpression.escapedPattern(for: variant)
                let pattern = #"(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
                normalized = regex.stringByReplacingMatches(
                    in: normalized,
                    options: [],
                    range: range,
                    withTemplate: entry.canonical
                )
            }
        }

        return normalized
    }
}
