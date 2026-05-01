import Foundation

nonisolated enum TranscriptionLanguageResolver {
    static func resolve(_ language: String, locale: Locale = .current) -> String {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedLanguage == "system" else {
            return normalizedLanguage
        }

        let identifier = locale.identifier.lowercased()
        let code = identifier
            .split { character in
                character == "_" || character == "-"
            }
            .first
            .map(String.init) ?? ""

        return code.isEmpty ? "auto" : code
    }
}
