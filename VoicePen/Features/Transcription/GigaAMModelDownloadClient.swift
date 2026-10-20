import Foundation

final class GigaAMModelDownloadClient: ModelDownloadClient {
    private let paths: AppPaths
    private let downloader: ModelAssetDownloading

    init(
        paths: AppPaths, assetDownloader: ModelAssetDownloading? = nil,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = { ModelDownloadProxyConfiguration.fromEnvironment() }
    ) {
        self.paths = paths
        downloader = assetDownloader ?? VerifiedModelAssetDownloader(proxyProvider: proxyProvider)
    }

    func downloadModel(_ model: ModelManifestModel, events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws -> URL {
        guard model.backendKind == .gigaAM else { throw ModelDownloadError.unsupportedBackend(model.backend) }
        guard let asset = model.remoteFile else { throw ModelDownloadError.missingDownloadURL(model.id) }
        let marker = paths.userModelCompletionMarker(for: model.id)
        try? FileManager.default.removeItem(at: marker)
        let target = paths.userModelFile(for: model.id, fileName: model.localArtifactFileName)
        try await downloader.download(asset, to: target, label: model.id) {
            events(.downloadingArtifact(name: model.localArtifactFileName, progress: $0))
        }
        try Task.checkCancellation()
        events(.validating)
        try JSONEncoder().encode(GigaAMInstallationIdentity(model: model)).write(to: marker, options: .atomic)
        events(.completed)
        return paths.userModelDirectory(for: model.id)
    }
}

nonisolated struct GigaAMInstallationIdentity: Codable, Equatable {
    let modelID: String
    let version: String
    let sha256: String?
    let byteSize: Int64?
    let runtimePackageID: String?

    init(model: ModelManifestModel) {
        modelID = model.id
        version = model.version
        sha256 = model.sha256
        byteSize = model.byteSize
        runtimePackageID = model.runtimePackageID
    }

    func isInstalled(paths: AppPaths, model: ModelManifestModel) -> Bool {
        guard let data = try? Data(contentsOf: paths.userModelCompletionMarker(for: model.id)),
            let identity = try? JSONDecoder().decode(Self.self, from: data), identity == self,
            let attributes = try? FileManager.default.attributesOfItem(atPath: paths.userModelFile(for: model.id, fileName: model.localArtifactFileName).path),
            let size = attributes[.size] as? NSNumber
        else { return false }
        return size.int64Value > 0 && (byteSize == nil || size.int64Value == byteSize)
    }
}
