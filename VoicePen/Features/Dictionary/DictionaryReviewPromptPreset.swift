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
                - canonical may be an exact workflow term, e.g. Spec Driven
                - canonical may be an exact programming/documentation term, e.g. frontmatter
                - canonical may be a base concept/word family, e.g. модель
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
                - project workflow terms, e.g. спека, Spec Driven, implementation spec
                - repo files, acronyms, commands, APIs, frameworks, model names, file formats
                - developer/documentation terms that ASR mangled, e.g. frontmatter
                - ordinary words only when ASR produces an impossible or very unnatural form repeatedly
                - phrase-level variants when a standalone variant would be ambiguous

                Bad candidates:
                - transient side-discussion tools mentioned once or twice
                - words that appeared correctly
                - terms with no mistaken variant
                - capitalization-only preferences
                - broad style or grammar rewrites
                - speculative guesses
                - standalone variants that are valid ordinary words and may cause false corrections

                Exact artifact rule:
                If canonical is a filename, acronym, command, API, library, framework, model name, product name, workflow name, or file format, use the exact canonical spelling.

                Linguistic hint rule:
                If canonical is an ordinary word, treat it as a meaning hint.
                The downstream model should choose the correct grammatical form in context.
                For example, canonical "модель" with variant "моделя" may become "модель", "модели", "моделью", etc., depending on context.

                Uncorrected mistake rule:
                raw_text == final_text is weak evidence against adding an entry, not a hard exclusion.
                Still add an entry when the phrase is clearly broken in context and points to a high-impact technical artifact, workflow term, file format, programming term, project convention, or recurring malformed word.
                Do a dedicated pass for such cases before returning the final CSV.

                Mandatory technical recovery pass:
                After the normal raw_text vs final_text comparison, do an extra pass over every raw_text entry, including rows where raw_text == final_text.
                The user may not manually correct broken ASR output before validation. Therefore raw_text == final_text does not always mean the phrase is correct.
                In this pass, include an entry when a phrase is obviously semantically broken in context and strongly points to a high-impact technical artifact, workflow term, file format, programming term, or project convention.

                Strong examples:
                - "агенции МД", "агент MD", "агенты MD", "agents md", "agent md" => AGENTS.md
                - "aspect driven", "inspect driven" in repo/spec workflow context => Spec Driven
                - "implementation спектр" in spec/planning context => implementation spec
                - "фронтметр" in MDX/spec/document context => frontmatter
                - "с Пеки", "с Пеке", "с пики" in review/validator/spec context => спека

                Do not require final_text to contain the corrected form for this pass.

                Single high-impact artifact rule:
                A mistaken variant does not need to recur if all of the following are true:
                1. The surrounding context is technical or project-specific.
                2. The phrase is unnatural or semantically broken as written.
                3. There is a clear canonical technical term with much higher likelihood.
                4. The canonical term would materially improve future transcription quality.

                This rule is especially important for filenames, workflow names, spec terminology, repo conventions, APIs, formats, and developer tools.

                Collision-safe variant rule:
                If a mistaken variant is also a valid ordinary word, do not add it as a standalone variant.
                Use the shortest context phrase that disambiguates the intended technical term.

                Bad:
                спека,спектр
                Metal,металл

                Good:
                implementation spec,implementation спектр
                Metal,переход на металл; метал врубать

                Transient mention exclusion:
                Do not add tools/products/brands merely because they were mentioned.
                Include them only if there is a clear mistaken variant and the variant is useful.

                Exclude:
                Warp,варп
                Ghostty,гости

                But include phrase-level variants for non-transient technical concepts when context is clear:
                Spec Driven,aspect driven; inspect driven
                frontmatter,фронтметр
                implementation spec,implementation спектр

                Before returning CSV, verify:
                1. Did I inspect raw_text == final_text rows for still-broken technical phrases?
                2. Did I recover project workflow terms such as spec/specs, Spec Driven, implementation spec, ADR, frontmatter?
                3. Did I avoid standalone variants that are valid ordinary words and instead use context phrases?
                4. Did I exclude transient products/tools unless there is a clear mistaken ASR variant?
                5. Did I include only entries with at least one concrete mistaken variant?
                6. Did I avoid adding words that merely appeared correctly?
                7. Did I avoid duplicating current dictionary entries?
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
