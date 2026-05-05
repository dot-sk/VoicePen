import Foundation

nonisolated struct TranscriptionClientResult: Equatable, Sendable {
    let text: String
    let modelMetadata: VoiceTranscriptionModelMetadata?

    init(
        text: String,
        modelMetadata: VoiceTranscriptionModelMetadata? = nil
    ) {
        self.text = text
        self.modelMetadata = modelMetadata
    }
}

protocol TranscriptionClient: AnyObject {
    func transcribe(audioURL: URL, glossaryPrompt: String, language: String) async throws -> TranscriptionClientResult
}
