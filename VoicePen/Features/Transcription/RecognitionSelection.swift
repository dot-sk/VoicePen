import Foundation

nonisolated struct RecognitionSelection: Equatable {
    var language: String
    var modelID: String
    var rememberedModels: [String: String]

    static func supports(_ model: ModelManifestModel, language: String, locale: Locale = .current) -> Bool {
        let resolved = TranscriptionLanguageResolver.resolve(language, locale: locale)
        if resolved == "auto" {
            return model.supportedLanguageCodes.contains("multilingual") || model.supportedLanguageCodes.count > 1
        }
        return model.supports(language: resolved)
    }

    func selectingLanguage(_ language: String, models: [ModelManifestModel], recommendedID: String, installedIDs: Set<String>, locale: Locale = .current) -> Self? {
        let compatible = models.filter { Self.supports($0, language: language, locale: locale) }
        let installed = compatible.filter { installedIDs.contains($0.id) }
        guard
            let model = compatible.first(where: { $0.id == rememberedModels[language] })
                ?? compatible.first(where: { $0.id == modelID })
                ?? installed.first(where: { $0.id == recommendedID })
                ?? installed.first
                ?? compatible.first(where: { $0.id == recommendedID })
                ?? compatible.first
        else { return nil }
        return remembering(model: model, language: language, models: models, locale: locale)
    }

    func selectingModel(_ model: ModelManifestModel, models: [ModelManifestModel], locale: Locale = .current) -> Self {
        let selectedLanguage: String
        if Self.supports(model, language: language, locale: locale) {
            selectedLanguage = language
        } else {
            selectedLanguage = model.supportedLanguageCodes.first(where: { $0 != "multilingual" }) ?? "auto"
        }
        return remembering(model: model, language: selectedLanguage, models: models, locale: locale)
    }

    private func remembering(model: ModelManifestModel, language: String, models: [ModelManifestModel], locale: Locale) -> Self {
        var remembered = rememberedModels
        if let current = models.first(where: { $0.id == modelID }), Self.supports(current, language: self.language, locale: locale) {
            remembered[self.language] = current.id
        }
        remembered[language] = model.id
        return Self(language: language, modelID: model.id, rememberedModels: remembered)
    }
}
