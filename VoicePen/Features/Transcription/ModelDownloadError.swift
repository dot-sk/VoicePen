import Foundation

enum ModelDownloadError: LocalizedError, Equatable {
    case unsupportedBackend(String)
    case missingDownloadURL(String)
    case downloadFailed(modelId: String, message: String)
    case archiveExtractionFailed(modelId: String, artifactId: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedBackend(backend):
            "VoicePen does not know how to download models for backend: \(backend)."
        case let .missingDownloadURL(modelId):
            "VoicePen does not have a direct download URL for \(modelId)."
        case let .downloadFailed(modelId, message):
            "VoicePen could not download \(modelId): \(message)"
        case let .archiveExtractionFailed(modelId, artifactId, message):
            "VoicePen could not unpack \(artifactId) for \(modelId): \(message)"
        }
    }
}
