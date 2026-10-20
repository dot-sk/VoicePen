import Foundation

nonisolated enum ModelDownloadEvent: Equatable, Sendable {
    case downloadingArtifact(name: String, progress: Double?)
    case extractingArtifact(name: String)
    case validating
    case completed
}

nonisolated protocol ModelDownloadClient: AnyObject, Sendable {
    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL
}
