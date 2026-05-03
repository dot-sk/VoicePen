import Foundation

nonisolated struct PromptGlossaryBuilder {
    func build(entries: [TermEntry], limit: Int, language: String = "en") -> String {
        let terms =
            entries
            .sorted { $0.canonical.localizedCaseInsensitiveCompare($1.canonical) == .orderedAscending }
            .prefix(limit)
            .map(\.canonical)

        guard !terms.isEmpty else { return "" }
        let termList = terms.joined(separator: ", ")

        if language == "auto" {
            return "\(termList)."
        }

        if language == "ru" {
            return "Технические термины, которые могут встретиться: \(termList)."
        }

        return "Technical terms that may appear: \(termList)."
    }
}
