import Foundation

nonisolated enum MeetingRecordingStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case completed
    case partial
    case failed

    var title: String {
        switch self {
        case .completed:
            return "Completed"
        case .partial:
            return "Partial"
        case .failed:
            return "Failed"
        }
    }
}

nonisolated struct MeetingSourceFlags: Codable, Equatable, Sendable {
    var microphoneCaptured: Bool
    var systemAudioCaptured: Bool
    var partial: Bool

    init(
        microphoneCaptured: Bool = false,
        systemAudioCaptured: Bool = false,
        partial: Bool = false
    ) {
        self.microphoneCaptured = microphoneCaptured
        self.systemAudioCaptured = systemAudioCaptured
        self.partial = partial
    }
}

nonisolated struct MeetingPipelineTimings: Codable, Equatable, Sendable {
    var recording: TimeInterval?
    var preprocessing: TimeInterval?
    var transcription: TimeInterval?

    init(
        recording: TimeInterval? = nil,
        preprocessing: TimeInterval? = nil,
        transcription: TimeInterval? = nil
    ) {
        self.recording = recording
        self.preprocessing = preprocessing
        self.transcription = transcription
    }
}

nonisolated struct MeetingHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval
    var transcriptText: String
    var status: MeetingRecordingStatus
    var sourceFlags: MeetingSourceFlags
    var errorMessage: String?
    var timings: MeetingPipelineTimings?
    var modelMetadata: VoiceTranscriptionModelMetadata?
    var recognizedWordCount: Int?
    var isTextPayloadEvicted: Bool = false

    var previewText: String {
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, isTextPayloadEvicted {
            return "Transcript removed from local cache"
        }

        guard !trimmed.isEmpty else {
            return errorMessage ?? status.title
        }
        return trimmed
    }

    var usageWordCount: Int {
        recognizedWordCount ?? VoiceHistoryEntry.wordCount(in: transcriptText)
    }
}

nonisolated enum MeetingSourceKind: String, Codable, Equatable, Sendable {
    case microphone
    case systemAudio
}

nonisolated enum MeetingSourceHealth: String, Codable, Equatable, Sendable {
    case unavailable
    case capturing
    case paused
    case failed

    var title: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .capturing:
            return "Capturing"
        case .paused:
            return "Paused"
        case .failed:
            return "Failed"
        }
    }
}

nonisolated struct MeetingSourceStatus: Codable, Equatable, Sendable {
    var microphone: MeetingSourceHealth
    var systemAudio: MeetingSourceHealth
    var microphoneLevel: Double?
    var systemAudioLevel: Double?

    static let idle = MeetingSourceStatus(
        microphone: .unavailable,
        systemAudio: .unavailable,
        microphoneLevel: nil,
        systemAudioLevel: nil
    )

    var hasFailedSource: Bool {
        microphone == .failed || systemAudio == .failed
    }
}

nonisolated struct MeetingAudioChunk: Codable, Equatable, Sendable {
    var url: URL
    var source: MeetingSourceKind
    var startOffset: TimeInterval
    var duration: TimeInterval
}

nonisolated struct MeetingRecordingResult: Equatable, Sendable {
    var startedAt: Date
    var endedAt: Date
    var chunks: [MeetingAudioChunk]
    var sourceFlags: MeetingSourceFlags
    var errorMessage: String?

    var duration: TimeInterval {
        chunks.reduce(0) { $0 + max(0, $1.duration) }
    }

    var temporaryAudioURLs: [URL] {
        Array(Set(chunks.map(\.url))).sorted { $0.path < $1.path }
    }
}

enum MeetingRecordingError: LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case noCapturedAudio
    case durationLimitExceeded
    case systemAudioPermissionDenied
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A meeting recording is already running."
        case .notRecording:
            return "No meeting recording is running."
        case .noCapturedAudio:
            return "No meeting audio was captured."
        case .durationLimitExceeded:
            return "Meeting recording reached the 120 minute limit."
        case .systemAudioPermissionDenied:
            return "System Audio permission is required to capture meeting audio."
        case let .captureFailed(message):
            return "Meeting audio capture failed: \(message)"
        }
    }
}
