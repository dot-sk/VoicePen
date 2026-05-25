import Foundation

nonisolated struct TermNormalizer {
    private let replacementRules: [ReplacementRule]

    init(entries: [TermEntry]) {
        self.replacementRules =
            entries
            .sorted { lhs, rhs in
                if lhs.canonical.count == rhs.canonical.count {
                    return lhs.canonical.localizedCaseInsensitiveCompare(rhs.canonical) == .orderedAscending
                }
                return lhs.canonical.count > rhs.canonical.count
            }
            .flatMap { entry in
                entry.variants
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .sorted {
                        if $0.count == $1.count {
                            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                        }
                        return $0.count > $1.count
                    }
                    .map { variant in
                        ReplacementRule(canonical: entry.canonical, variant: variant)
                    }
            }
    }

    func normalize(_ rawText: String) throws -> String {
        var normalized = rawText

        for rule in replacementRules {
            let regex = try rule.regex.get()
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            normalized = regex.stringByReplacingMatches(
                in: normalized,
                options: [],
                range: range,
                withTemplate: rule.canonical
            )
        }

        return normalized
    }

    private struct ReplacementRule {
        let canonical: String
        let regex: Result<NSRegularExpression, Error>

        init(canonical: String, variant: String) {
            self.canonical = canonical
            let escaped = NSRegularExpression.escapedPattern(for: variant)
            let pattern = #"(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
            self.regex = Result {
                try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            }
        }
    }
}
