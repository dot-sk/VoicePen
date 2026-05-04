import Foundation

nonisolated protocol LLMClient: Sendable {
    func completeJSON(_ request: LLMStructuredRequest) async -> Result<String, LLMClientError>
}

nonisolated struct LLMStructuredRequest: Equatable, Sendable {
    var prompt: String
    var schema: LLMJSONSchema

    init(prompt: String, schema: LLMJSONSchema) {
        self.prompt = prompt
        self.schema = schema
    }
}

nonisolated struct LLMJSONSchema: Equatable, Sendable {
    var name: String
    var schema: JSONValue
    var strict: Bool

    init(name: String, schema: JSONValue, strict: Bool = true) {
        self.name = name
        self.schema = schema
        self.strict = strict
    }
}

nonisolated indirect enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([JSONValue].self))
        }
    }
}

nonisolated enum LLMClientError: Error, Equatable, LocalizedError, Sendable {
    case configuration(String)
    case providerUnavailable(String)
    case provider(statusCode: Int, message: String)
    case schemaUnsupported(String)
    case timeout(String)
    case invalidResponse(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case let .configuration(message),
             let .providerUnavailable(message),
             let .schemaUnsupported(message),
             let .timeout(message),
             let .invalidResponse(message),
             let .transport(message):
            return message
        case let .provider(statusCode, message):
            return "Provider returned HTTP \(statusCode): \(message)"
        }
    }

    func redacted(apiKey: String) -> LLMClientError {
        guard !apiKey.isEmpty else { return self }

        switch self {
        case let .configuration(message):
            return .configuration(AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        case let .providerUnavailable(message):
            return .providerUnavailable(AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        case let .provider(statusCode, message):
            return .provider(statusCode: statusCode, message: AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        case let .schemaUnsupported(message):
            return .schemaUnsupported(AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        case let .timeout(message):
            return .timeout(AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        case let .invalidResponse(message):
            return .invalidResponse(AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        case let .transport(message):
            return .transport(AppLogger.sanitizedForLogging(message, secrets: [apiKey]))
        }
    }
}

nonisolated struct LLMHTTPResponse: Sendable {
    var data: Data
    var statusCode: Int

    init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

nonisolated protocol LLMHTTPTransport: Sendable {
    func perform(_ request: URLRequest, timeoutSeconds: Double) async throws -> LLMHTTPResponse
}

nonisolated final class LiveLLMHTTPTransport: LLMHTTPTransport, @unchecked Sendable {
    func perform(_ request: URLRequest, timeoutSeconds: Double) async throws -> LLMHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMTransportError.invalidHTTPResponse
        }

        return LLMHTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }
}

private enum LLMTransportError: Error {
    case invalidHTTPResponse
}

nonisolated enum LLMRouter {
    static func makeClient(config: LLMConfig, transport: LLMHTTPTransport = LiveLLMHTTPTransport()) -> Result<LLMClient, LLMClientError> {
        switch config.provider {
        case .ollama:
            return .success(OllamaLLMClient(config: config.ollama, transport: transport))
        case .openrouter:
            guard !config.openrouter.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.configuration("OpenRouter API key is required when llm.provider is openrouter."))
            }
            return .success(OpenRouterLLMClient(config: config.openrouter, transport: transport))
        }
    }
}
