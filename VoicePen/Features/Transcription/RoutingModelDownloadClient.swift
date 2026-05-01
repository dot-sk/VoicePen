import Foundation

final class RoutingModelDownloadClient: ModelDownloadClient {
    private let whisperCppDownloader: ModelDownloadClient
    private let fluidAudioDownloader: ModelDownloadClient

    init(
        whisperCppDownloader: ModelDownloadClient,
        fluidAudioDownloader: ModelDownloadClient
    ) {
        self.whisperCppDownloader = whisperCppDownloader
        self.fluidAudioDownloader = fluidAudioDownloader
    }

    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        switch model.backendKind {
        case .whisperCpp:
            return try await whisperCppDownloader.downloadModel(model, events: events)
        case .fluidAudio:
            return try await fluidAudioDownloader.downloadModel(model, events: events)
        case .unsupported:
            throw ModelDownloadError.unsupportedBackend(model.backend)
        }
    }
}
