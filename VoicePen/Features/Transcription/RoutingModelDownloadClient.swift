import Foundation

final class RoutingModelDownloadClient: ModelDownloadClient {
    private let whisperCppDownloader: ModelDownloadClient

    init(whisperCppDownloader: ModelDownloadClient) {
        self.whisperCppDownloader = whisperCppDownloader
    }

    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        switch model.backendKind {
        case .whisperCpp:
            return try await whisperCppDownloader.downloadModel(model, events: events)
        case .unsupported:
            throw ModelDownloadError.unsupportedBackend(model.backend)
        }
    }
}
