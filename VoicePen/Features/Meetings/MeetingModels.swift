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
            return "Partial Transcript"
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

nonisolated struct MeetingRecoveryAudioManifest: Codable, Equatable, Sendable {
    var createdAt: Date
    var expiresAt: Date
    var duration: TimeInterval
    var sourceFlags: MeetingSourceFlags
    var chunks: [MeetingAudioChunk]

    func isExpired(at date: Date) -> Bool {
        date >= expiresAt
    }

    func hasAvailableAudio(fileManager: FileManager = .default) -> Bool {
        !chunks.isEmpty && chunks.allSatisfy { fileManager.fileExists(atPath: $0.url.path) }
    }

    func isAvailableForRetry(at date: Date = Date(), fileManager: FileManager = .default) -> Bool {
        !isExpired(at: date) && hasAvailableAudio(fileManager: fileManager)
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
    var recoveryAudio: MeetingRecoveryAudioManifest?
    var isTextPayloadEvicted: Bool = false

    init(
        id: UUID,
        createdAt: Date,
        duration: TimeInterval,
        transcriptText: String,
        status: MeetingRecordingStatus,
        sourceFlags: MeetingSourceFlags,
        errorMessage: String?,
        timings: MeetingPipelineTimings?,
        modelMetadata: VoiceTranscriptionModelMetadata?,
        recognizedWordCount: Int? = nil,
        recoveryAudio: MeetingRecoveryAudioManifest? = nil,
        isTextPayloadEvicted: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.transcriptText = transcriptText
        self.status = status
        self.sourceFlags = sourceFlags
        self.errorMessage = errorMessage
        self.timings = timings
        self.modelMetadata = modelMetadata
        self.recognizedWordCount = recognizedWordCount
        self.recoveryAudio = recoveryAudio
        self.isTextPayloadEvicted = isTextPayloadEvicted
    }

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
    case failed

    var title: String {
        switch self {
        case .unavailable:
            return "Unavailable"
        case .capturing:
            return "Capturing"
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
    var duration: TimeInterval
    var sourceFlags: MeetingSourceFlags
    var errorMessage: String?

    init(
        startedAt: Date,
        endedAt: Date,
        chunks: [MeetingAudioChunk],
        sourceFlags: MeetingSourceFlags,
        errorMessage: String?,
        duration: TimeInterval? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.chunks = chunks
        self.duration = max(0, duration ?? endedAt.timeIntervalSince(startedAt))
        self.sourceFlags = sourceFlags
        self.errorMessage = errorMessage
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
    case captureTimedOut
    case captureFailed(String)
    case recoveryAudioUnavailable
    case recoveryAudioExpired

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A meeting recording is already running."
        case .notRecording:
            return "No meeting recording is running."
        case .noCapturedAudio:
            return "No meeting audio was captured."
        case .durationLimitExceeded:
            let minutes = Int((VoicePenConfig.meetingMaximumRecordingDuration / 60).rounded())
            return "Meeting recording reached the \(minutes) minute limit."
        case .systemAudioPermissionDenied:
            return "System Audio permission is required to capture meeting audio."
        case .captureTimedOut:
            return "Meeting audio capture did not start in time."
        case let .captureFailed(message):
            return "Meeting audio capture failed: \(message)"
        case .recoveryAudioUnavailable:
            return "Meeting audio is no longer available for retry."
        case .recoveryAudioExpired:
            return "Meeting audio retry window has expired."
        }
    }
}
