import Foundation

nonisolated struct AISettingsSummary: Equatable, Sendable {
    var parserEnabled: Bool
    var confidenceThreshold: Double
    var provider: LLMProvider
    var baseURL: String
    var model: String
    var hasOpenRouterAPIKey: Bool?

    init(config: UserConfig) {
        self.parserEnabled = config.developer.intentParser.enabled
        self.confidenceThreshold = config.developer.intentParser.confidenceThreshold
        self.provider = config.llm.provider

        switch config.llm.provider {
        case .ollama:
            self.baseURL = config.llm.ollama.baseURL
            self.model = config.llm.ollama.model
            self.hasOpenRouterAPIKey = nil
        case .openrouter:
            self.baseURL = config.llm.openrouter.baseURL
            self.model = config.llm.openrouter.model
            self.hasOpenRouterAPIKey =
                !config.llm.openrouter.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
