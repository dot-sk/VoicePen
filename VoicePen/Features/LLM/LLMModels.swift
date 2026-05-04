import Foundation

nonisolated enum LLMProvider: String, Codable, Equatable, Sendable {
    case ollama
    case openrouter
}

nonisolated struct LLMConfig: Codable, Equatable, Sendable {
    var provider: LLMProvider
    var ollama: OllamaLLMConfig
    var openrouter: OpenRouterLLMConfig

    init(
        provider: LLMProvider = .ollama,
        ollama: OllamaLLMConfig = OllamaLLMConfig(),
        openrouter: OpenRouterLLMConfig = OpenRouterLLMConfig()
    ) {
        self.provider = provider
        self.ollama = ollama
        self.openrouter = openrouter
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case ollama
        case openrouter
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.provider = try container.decodeIfPresent(LLMProvider.self, forKey: .provider) ?? .ollama
        self.ollama = try container.decodeIfPresent(OllamaLLMConfig.self, forKey: .ollama) ?? OllamaLLMConfig()
        self.openrouter =
            try container.decodeIfPresent(OpenRouterLLMConfig.self, forKey: .openrouter)
            ?? OpenRouterLLMConfig()
    }
}

nonisolated struct OllamaLLMConfig: Codable, Equatable, Sendable {
    var baseURL: String
    var model: String
    var timeoutSeconds: Double
    var think: Bool

    init(
        baseURL: String = "http://localhost:11434",
        model: String = "gemma4:e2b",
        timeoutSeconds: Double = 15,
        think: Bool = false
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeoutSeconds = timeoutSeconds
        self.think = think
    }

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case model
        case timeoutSeconds = "timeout_seconds"
        case think
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "http://localhost:11434"
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "gemma4:e2b"
        self.timeoutSeconds = try container.decodeDoubleOrIntIfPresent(forKey: .timeoutSeconds) ?? 15
        self.think = try container.decodeIfPresent(Bool.self, forKey: .think) ?? false
    }
}

nonisolated struct OpenRouterLLMConfig: Codable, Equatable, Sendable {
    var baseURL: String
    var model: String
    var apiKey: String
    var timeoutSeconds: Double

    init(
        baseURL: String = "https://openrouter.ai/api/v1",
        model: String = "google/gemini-2.5-flash-lite",
        apiKey: String = "",
        timeoutSeconds: Double = 20
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.timeoutSeconds = timeoutSeconds
    }

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case model
        case apiKey = "api_key"
        case timeoutSeconds = "timeout_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.baseURL =
            try container.decodeIfPresent(String.self, forKey: .baseURL) ?? "https://openrouter.ai/api/v1"
        self.model =
            try container.decodeIfPresent(String.self, forKey: .model) ?? "google/gemini-2.5-flash-lite"
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        self.timeoutSeconds = try container.decodeDoubleOrIntIfPresent(forKey: .timeoutSeconds) ?? 20
    }
}

nonisolated private extension KeyedDecodingContainer {
    func decodeDoubleOrIntIfPresent(forKey key: Key) throws -> Double? {
        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return doubleValue
        }
        if let intValue = try decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        return nil
    }
}
