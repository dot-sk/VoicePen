import Foundation

nonisolated enum DictionaryReviewPromptPreset: String, CaseIterable, Identifiable, Sendable {
    case dictionaryImprovement
    case technicalTerms
    case productWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dictionaryImprovement:
            return "Dictionary improvement"
        case .technicalTerms:
            return "Technical terms"
        case .productWork:
            return "Product work"
        }
    }

    var reviewInstructions: String {
        switch self {
        case .dictionaryImprovement:
            return """
            Review goal:
            Infer a small set of high-value dictionary entries from transcription history.

            The dictionary is used as prompt context, not as literal search-and-replace.
            Therefore:
            - canonical may be an exact technical artifact, e.g. AGENTS.md
            - or a base concept/word family, e.g. модель
            - variants are mistaken ASR forms that should help the model infer the intended meaning

            Add entries only when they help the model recover the user's intended meaning from recurring or high-impact transcription mistakes.

            Important:
            Do not collect merely important-looking words.
            Do not collect tools/products/brands just because they were mentioned.
            Collect only clear mistaken variants.
            If nothing is strong, return only the CSV header.

            Good candidates:
            - recurring malformed variants
            - obvious high-impact technical artifacts, even when raw_text == final_text
            - repo files, acronyms, commands, APIs, frameworks, model names, workflow terms
            - ordinary words only when ASR produces an impossible or very unnatural form repeatedly

            Bad candidates:
            - transient side-discussion tools mentioned once or twice
            - words that appeared correctly
            - terms with no mistaken variant
            - capitalization-only preferences
            - broad style or grammar rewrites
            - speculative guesses

            Exact artifact rule:
            If canonical is a filename, acronym, command, API, library, framework, model name, or product name, use the exact canonical spelling.

            Linguistic hint rule:
            If canonical is an ordinary word, treat it as a meaning hint.
            The downstream model should choose the correct grammatical form in context.
            For example, canonical "модель" with variant "моделя" may become "модель", "модели", "моделью", etc., depending on context.

            Uncorrected mistake rule:
            raw_text == final_text usually means no entry.
            Exception: include the entry if the phrase is obviously still a broken transcription of a high-impact technical artifact or recurring malformed word.

            Transient mention exclusion:
            Do not add terms like Warp or Ghostty merely because they appeared in a terminal discussion.
            Include them only if there is a clear mistaken variant that recurs or the user explicitly marks them as dictionary-worthy.

            Examples to include:
            AGENTS.md,агенции МД; агент MD; агенты MD; agents md; agent md
            модель,моделя

            Examples to exclude:
            Warp,варп; warp
            Ghostty,гости; госте; ghostty

            Reason:
            Warp and Ghostty are transient side-discussion tool names without strong evidence that they are recurring transcription problems.
            """
        case .technicalTerms:
            return """
            Review goal:
            Prioritize high-value product names, dev terms, APIs, tools, company vocabulary, and mixed-language work terms.

            Selection rules:
            Keep the dictionary small. Add only high-confidence raw-to-final corrections for repeated or especially annoying mistakes.
            Skip terms the model already handled correctly, even if they look important.
            Prefer an empty import over speculative, one-off, or low-impact entries. If nothing is strong, return only the CSV header.
            """
        case .productWork:
            return """
            Review goal:
            Prioritize high-value feature names, metrics, roadmap terms, customers, teams, tracker terms, and business vocabulary.

            Selection rules:
            Keep the dictionary small. Add only high-confidence raw-to-final corrections for repeated or especially annoying mistakes.
            Skip terms the model already handled correctly, even if they look important.
            Prefer an empty import over speculative, one-off, or low-impact entries. If nothing is strong, return only the CSV header.
            """
        }
    }
}

nonisolated enum HistoryReviewLimit: Int, CaseIterable, Identifiable, Sendable {
    case ten = 10
    case fifty = 50
    case hundred = 100

    static let defaultValue: HistoryReviewLimit = .fifty

    var id: Int { rawValue }
}
