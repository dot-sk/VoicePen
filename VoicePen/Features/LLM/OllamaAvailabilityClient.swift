import Foundation

nonisolated enum OllamaAvailability: Equatable, Sendable {
    case available
    case unavailable(String)
}

nonisolated final class OllamaAvailabilityClient: @unchecked Sendable {
    private let transport: LLMHTTPTransport

    init(transport: LLMHTTPTransport = LiveLLMHTTPTransport()) {
        self.transport = transport
    }

    func check(baseURL: String, timeoutSeconds: Double = 2) async -> OllamaAvailability {
        guard let url = URL(string: baseURL)?.appendingPathComponent("api/version") else {
            return .unavailable("Ollama base URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let response = try await transport.perform(request, timeoutSeconds: timeoutSeconds)
            guard (200..<300).contains(response.statusCode) else {
                return .unavailable("Ollama returned HTTP \(response.statusCode).")
            }
            return .available
        } catch let error as URLError where error.isProviderUnavailable {
            return .unavailable("Ollama is not reachable.")
        } catch let error as URLError where error.code == .timedOut {
            return .unavailable("Ollama ping timed out.")
        } catch {
            return .unavailable("Ollama ping failed: \(error.localizedDescription)")
        }
    }
}
