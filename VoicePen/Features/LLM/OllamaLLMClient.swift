import Foundation

nonisolated final class OllamaLLMClient: LLMClient, @unchecked Sendable {
    private let config: OllamaLLMConfig
    private let transport: LLMHTTPTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(config: OllamaLLMConfig, transport: LLMHTTPTransport = LiveLLMHTTPTransport()) {
        self.config = config
        self.transport = transport
    }

    func completeJSON(_ request: LLMStructuredRequest) async -> Result<String, LLMClientError> {
        guard let url = URL(string: config.baseURL)?.appendingPathComponent("api/chat") else {
            return .failure(.configuration("Ollama base URL is invalid."))
        }

        do {
            let body = OllamaChatRequest(
                model: config.model,
                messages: [OllamaMessage(role: "user", content: request.prompt)],
                stream: false,
                think: config.think,
                format: request.schema.schema
            )
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try encoder.encode(body)

            let response = try await transport.perform(urlRequest, timeoutSeconds: config.timeoutSeconds)
            guard (200..<300).contains(response.statusCode) else {
                return .failure(.provider(statusCode: response.statusCode, message: LLMProviderMessage.text(from: response)))
            }

            let decoded = try decoder.decode(OllamaChatResponse.self, from: response.data)
            return .success(decoded.message.content)
        } catch let error as DecodingError {
            return .failure(.invalidResponse("Ollama response JSON could not be decoded: \(error.localizedDescription)"))
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.timeout("Ollama request timed out."))
        } catch let error as URLError where error.isProviderUnavailable {
            return .failure(
                .providerUnavailable(
                    "Ollama is not reachable at \(config.baseURL). Start Ollama or choose another LLM provider."
                )
            )
        } catch {
            return .failure(.transport("Ollama request failed: \(error.localizedDescription)"))
        }
    }
}

nonisolated private struct OllamaChatRequest: Encodable {
    var model: String
    var messages: [OllamaMessage]
    var stream: Bool
    var think: Bool
    var format: JSONValue
}

nonisolated private struct OllamaMessage: Codable {
    var role: String
    var content: String
}

nonisolated private struct OllamaChatResponse: Decodable {
    var message: OllamaMessage
}

nonisolated enum LLMProviderMessage {
    static func text(from response: LLMHTTPResponse) -> String {
        String(data: response.data, encoding: .utf8) ?? "No response body."
    }
}

private extension URLError {
    var isProviderUnavailable: Bool {
        switch code {
        case .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }
}
