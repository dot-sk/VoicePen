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

nonisolated struct TranscriptionOptions: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let timestamps = Self(rawValue: 1 << 0)
    static let voiceActivityDetection = Self(rawValue: 1 << 1)
}

nonisolated struct TranscriptionRequest: Equatable, Sendable {
    let audioURL: URL
    let glossaryPrompt: String
    let language: String
    let options: TranscriptionOptions

    init(
        audioURL: URL,
        glossaryPrompt: String,
        language: String,
        options: TranscriptionOptions = []
    ) {
        self.audioURL = audioURL
        self.glossaryPrompt = glossaryPrompt
        self.language = language
        self.options = options
    }
}

protocol TranscriptionClient: AnyObject {
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionClientResult
}
