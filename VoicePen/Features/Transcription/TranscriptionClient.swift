import Foundation

nonisolated struct TranscriptionSegment: Equatable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let words: [TranscriptionWord]

    init(text: String, startTime: TimeInterval, endTime: TimeInterval, words: [TranscriptionWord] = []) {
        self.text = text
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime, endTime)
        self.words = words
    }
}

nonisolated struct TranscriptionWord: Equatable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    init(text: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.text = text
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime, endTime)
    }
}

nonisolated struct TranscriptionClientResult: Equatable, Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let modelMetadata: VoiceTranscriptionModelMetadata?

    init(
        text: String,
        segments: [TranscriptionSegment] = [],
        modelMetadata: VoiceTranscriptionModelMetadata? = nil
    ) {
        self.text = text
        self.segments = segments
        self.modelMetadata = modelMetadata
    }
}

protocol TranscriptionClient: AnyObject {
    func transcribe(
        audioURL: URL,
        glossaryPrompt: String,
        language: String,
        includeTimestamps: Bool
    ) async throws -> TranscriptionClientResult
}

extension TranscriptionClient {
    func transcribe(audioURL: URL, glossaryPrompt: String, language: String) async throws -> TranscriptionClientResult {
        try await transcribe(
            audioURL: audioURL,
            glossaryPrompt: glossaryPrompt,
            language: language,
            includeTimestamps: false
        )
    }
}
