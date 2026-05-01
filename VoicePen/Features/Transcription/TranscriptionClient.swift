import Foundation

protocol TranscriptionClient: AnyObject {
    func transcribe(audioURL: URL, glossaryPrompt: String, language: String) async throws -> String
}
