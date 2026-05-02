import Foundation

nonisolated struct VoiceHistoryEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var duration: TimeInterval?
    var rawText: String
    var finalText: String
    var status: VoiceHistoryStatus
    var errorMessage: String?
    var timings: VoicePipelineTimings?
    var modelMetadata: VoiceTranscriptionModelMetadata? = nil

    var bestText: String {
        finalText.isEmpty ? rawText : finalText
    }

    var previewText: String {
        let text = bestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return errorMessage ?? status.title
        }
        return text
    }

    var modelMetadataForExport: VoiceTranscriptionModelMetadata {
        modelMetadata ?? .unknown
    }
}

nonisolated enum VoiceHistoryStatus: String, CaseIterable, Codable, Equatable, Sendable {
    case insertAttempted
    case empty
    case failed

    var title: String {
        switch self {
        case .insertAttempted:
            return "Insert attempted"
        case .empty:
            return "Empty"
        case .failed:
            return "Failed"
        }
    }
}
