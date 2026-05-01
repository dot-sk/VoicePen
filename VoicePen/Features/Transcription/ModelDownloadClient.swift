import Foundation

enum ModelDownloadEvent: Equatable {
    case downloadingArtifact(name: String, progress: Double?)
    case extractingArtifact(name: String)
    case validating
    case completed
}

protocol ModelDownloadClient: AnyObject {
    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL
}
