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
    var modelMetadata: VoiceTranscriptionModelMetadata?
    var diagnosticNotes: [String] = []
    var recognizedWordCount: Int?
    var isTextPayloadEvicted: Bool = false

    var bestText: String {
        finalText.isEmpty ? rawText : finalText
    }

    var usageWordCount: Int {
        recognizedWordCount ?? Self.wordCount(in: bestText)
    }

    var storedTextWeightBytes: Int {
        rawText.utf8.count + finalText.utf8.count
    }

    var previewText: String {
        let text = bestText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, isTextPayloadEvicted {
            return "Text removed from local cache"
        }

        guard !text.isEmpty else {
            return errorMessage ?? status.title
        }
        return text
    }

    var modelMetadataForExport: VoiceTranscriptionModelMetadata {
        modelMetadata ?? .unknown
    }

    nonisolated static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
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
