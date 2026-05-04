import Foundation

nonisolated final class OpenRouterLLMClient: LLMClient, @unchecked Sendable {
    private let config: OpenRouterLLMConfig
    private let transport: LLMHTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(config: OpenRouterLLMConfig, transport: LLMHTTPTransport = LiveLLMHTTPTransport()) {
        self.config = config
        self.transport = transport
    }

    func completeJSON(_ request: LLMStructuredRequest) async -> Result<String, LLMClientError> {
        guard let url = URL(string: config.baseURL)?.appendingPathComponent("chat/completions") else {
            return .failure(redacted(.configuration("OpenRouter base URL is invalid.")))
        }

        do {
            let body = OpenRouterChatRequest(
                model: config.model,
                messages: [OpenRouterMessage(role: "user", content: request.prompt)],
                stream: false,
                temperature: 0,
                maxCompletionTokens: 256,
                responseFormat: OpenRouterResponseFormat(
                    type: "json_schema",
                    jsonSchema: OpenRouterSchema(
                        name: request.schema.name,
                        strict: request.schema.strict,
                        schema: request.schema.schema
                    )
                )
            )
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.httpBody = try encoder.encode(body)

            let response = try await transport.perform(urlRequest, timeoutSeconds: config.timeoutSeconds)
            guard (200..<300).contains(response.statusCode) else {
                let message = LLMProviderMessage.text(from: response)
                if response.statusCode == 400, message.lowercased().contains("json_schema") {
                    return .failure(redacted(.schemaUnsupported(message)))
                }
                return .failure(
                    redacted(.provider(statusCode: response.statusCode, message: message))
                )
            }

            let decoded = try decoder.decode(OpenRouterChatResponse.self, from: response.data)
            guard let content = decoded.choices.first?.message.content else {
                return .failure(.invalidResponse("OpenRouter response did not include message content."))
            }
            return .success(content)
        } catch let error as DecodingError {
            return .failure(
                redacted(.invalidResponse("OpenRouter response JSON could not be decoded: \(error.localizedDescription)"))
            )
        } catch let error as URLError where error.code == .timedOut {
            return .failure(redacted(.timeout("OpenRouter request timed out.")))
        } catch let error as URLError where error.isProviderUnavailable {
            return .failure(
                redacted(
                    .providerUnavailable(
                        "OpenRouter is not reachable at \(config.baseURL). Check network access or choose another LLM provider."
                    )
                )
            )
        } catch {
            return .failure(
                redacted(.transport("OpenRouter request failed: \(error.localizedDescription)"))
            )
        }
    }

    private func redacted(_ error: LLMClientError) -> LLMClientError {
        error.redacted(apiKey: config.apiKey)
    }
}

nonisolated private struct OpenRouterChatRequest: Encodable {
    var model: String
    var messages: [OpenRouterMessage]
    var stream: Bool
    var temperature: Double
    var maxCompletionTokens: Int
    var responseFormat: OpenRouterResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case temperature
        case maxCompletionTokens = "max_completion_tokens"
        case responseFormat = "response_format"
    }
}

nonisolated private struct OpenRouterMessage: Codable {
    var role: String
    var content: String
}

nonisolated private struct OpenRouterResponseFormat: Encodable {
    var type: String
    var jsonSchema: OpenRouterSchema

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }
}

nonisolated private struct OpenRouterSchema: Encodable {
    var name: String
    var strict: Bool
    var schema: JSONValue
}

nonisolated private struct OpenRouterChatResponse: Decodable {
    var choices: [OpenRouterChoice]
}

nonisolated private struct OpenRouterChoice: Decodable {
    var message: OpenRouterMessage
}
