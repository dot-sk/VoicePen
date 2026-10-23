import Foundation

final class RoutingModelDownloadClient: ModelDownloadClient {
    private let whisperCppDownloader: ModelDownloadClient
    private let gigaAMDownloader: ModelDownloadClient?
    private let nemotronDownloader: ModelDownloadClient?

    init(whisperCppDownloader: ModelDownloadClient, gigaAMDownloader: ModelDownloadClient? = nil, nemotronDownloader: ModelDownloadClient? = nil) {
        self.whisperCppDownloader = whisperCppDownloader
        self.gigaAMDownloader = gigaAMDownloader
        self.nemotronDownloader = nemotronDownloader
    }

    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        switch model.backendKind {
        case .whisperCpp:
            return try await whisperCppDownloader.downloadModel(model, events: events)
        case .gigaAM:
            guard let gigaAMDownloader else { throw ModelDownloadError.unsupportedBackend(model.backend) }
            return try await gigaAMDownloader.downloadModel(model, events: events)
        case .nemotron:
            guard let nemotronDownloader else { throw ModelDownloadError.unsupportedBackend(model.backend) }
            return try await nemotronDownloader.downloadModel(model, events: events)
        case .unsupported:
            throw ModelDownloadError.unsupportedBackend(model.backend)
        }
    }
}
