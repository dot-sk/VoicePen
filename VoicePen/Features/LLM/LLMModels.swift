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
    static let defaultBaseURL = "http://localhost:11434"
    static let defaultModel = "gemma4:e2b"
    static let defaultTimeoutSeconds: Double = 15
    static let defaultThink = false

    var baseURL: String
    var model: String
    var timeoutSeconds: Double
    var think: Bool

    init(
        baseURL: String = Self.defaultBaseURL,
        model: String = Self.defaultModel,
        timeoutSeconds: Double = Self.defaultTimeoutSeconds,
        think: Bool = Self.defaultThink
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
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaultBaseURL
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        self.timeoutSeconds =
            try container.decodeDoubleOrIntIfPresent(forKey: .timeoutSeconds) ?? Self.defaultTimeoutSeconds
        self.think = try container.decodeIfPresent(Bool.self, forKey: .think) ?? Self.defaultThink
    }
}

nonisolated struct OpenRouterLLMConfig: Codable, Equatable, Sendable {
    static let defaultBaseURL = "https://openrouter.ai/api/v1"
    static let defaultModel = "google/gemini-2.5-flash-lite"
    static let defaultAPIKey = ""
    static let defaultTimeoutSeconds: Double = 20

    var baseURL: String
    var model: String
    var apiKey: String
    var timeoutSeconds: Double

    init(
        baseURL: String = Self.defaultBaseURL,
        model: String = Self.defaultModel,
        apiKey: String = Self.defaultAPIKey,
        timeoutSeconds: Double = Self.defaultTimeoutSeconds
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
        self.baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? Self.defaultBaseURL
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? Self.defaultModel
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? Self.defaultAPIKey
        self.timeoutSeconds =
            try container.decodeDoubleOrIntIfPresent(forKey: .timeoutSeconds) ?? Self.defaultTimeoutSeconds
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
