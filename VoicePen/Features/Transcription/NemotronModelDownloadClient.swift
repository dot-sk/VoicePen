import Foundation

nonisolated final class NemotronModelDownloadClient: ModelDownloadClient, @unchecked Sendable {
    private let paths: AppPaths
    private let downloader: WhisperCppModelDownloadClient

    init(paths: AppPaths, assetDownloader: ModelAssetDownloading? = nil) {
        self.paths = paths
        downloader = WhisperCppModelDownloadClient(
            paths: paths, proxyProvider: { ModelDownloadProxyConfiguration.fromEnvironment() }, assetDownloader: assetDownloader)
    }

    func downloadModel(_ model: ModelManifestModel, events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws -> URL {
        guard model.backendKind == .nemotron else { throw ModelDownloadError.unsupportedBackend(model.backend) }
        let directory = paths.userModelDirectory(for: model.id)
        let marker = paths.userModelCompletionMarker(for: model.id)
        try? FileManager.default.removeItem(at: marker)
        // Per-artifact markers do not encode the upstream revision, so reverify reused files
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(".voicepen-artifacts"))
        let result = try await downloader.downloadModel(model) { event in
            if event != .completed { events(event) }
        }
        try Task.checkCancellation()
        try JSONEncoder().encode(NemotronInstallationIdentity(model: model)).write(to: marker, options: .atomic)
        events(.completed)
        return result
    }
}

nonisolated struct NemotronInstallationIdentity: Codable, Equatable {
    struct File: Codable, Equatable {
        let path: String
        let asset: ModelAssetRemoteFile?
    }

    let modelID: String
    let version: String
    let runtimePackageID: String?
    let files: [File]

    init(model: ModelManifestModel) {
        modelID = model.id
        version = model.version
        runtimePackageID = model.runtimePackageID
        files =
            [File(path: model.localArtifactFileName, asset: model.remoteFile)]
            + model.requiredCompanionArtifacts.map { File(path: $0.localPath, asset: $0.remoteFile) }
    }

    func isInstalled(paths: AppPaths) -> Bool {
        guard let data = try? Data(contentsOf: paths.userModelCompletionMarker(for: modelID)),
            let installed = try? JSONDecoder().decode(Self.self, from: data), installed == self
        else { return false }
        return files.allSatisfy { file in
            guard let asset = file.asset,
                let attributes = try? FileManager.default.attributesOfItem(atPath: paths.userModelArtifact(for: modelID, localPath: file.path).path),
                let size = attributes[.size] as? NSNumber
            else { return false }
            return size.int64Value == asset.byteSize
        }
    }
}
