import Foundation

nonisolated struct NemotronModelFile: Sendable {
    let relativePath: String
    let asset: ModelAssetRemoteFile
}

nonisolated enum NemotronDiarizationModelFiles {
    static let revision = "25a90f97f254428d4b30374b76af9c74fdee8327"
    static let completionMarkerFileName = ".voicepen-nemotron-offline-complete"
    static let files: [NemotronModelFile] = [
        file(
            "learnable_sil_emb.bin", bytes: 2_048,
            sha: "d4417b3c0eabdf7c47032fac2b5b5a7ee83d819a6ddda8fd8eaf74e2b5cc4ac7"),
        file(
            "Nemotron3Diarizer_offline.mlmodelc/analytics/coremldata.bin", bytes: 243,
            sha: "491594df92282a4f2cef65e96d236e210a5c4627063e37e822ec858aaaad416d"),
        file(
            "Nemotron3Diarizer_offline.mlmodelc/coremldata.bin", bytes: 758,
            sha: "8b790c919c65744648c17290a26d3371e0e55db655310e7f8445080757b0bf08"),
        file(
            "Nemotron3Diarizer_offline.mlmodelc/model.mil", bytes: 505_274,
            sha: "ea5673d9e9ec785e7c8fb628acd82f9f86214c46b6584eaacdb6faddcb3f0277"),
        file(
            "Nemotron3Diarizer_offline.mlmodelc/weights/weight.bin", bytes: 198_654_080,
            sha: "bab76e5f190d0e4a4e174e7fcb1e9beea58c6b2be56e665e2cac8fba6d10f7f1")
    ]

    private static func file(_ path: String, bytes: Int64, sha: String) -> NemotronModelFile {
        let remotePath = path == "learnable_sil_emb.bin" ? path : "monolithic/v2/\(path)"
        return NemotronModelFile(
            relativePath: path,
            asset: ModelAssetRemoteFile(
                downloadURL: "https://huggingface.co/FluidInference/nemotron-3-diarization-coreml/resolve/\(revision)/\(remotePath)",
                byteSize: bytes, sha256: sha
            ))
    }

    static func completionMarkerURL(in directory: URL) -> URL {
        directory.appendingPathComponent(completionMarkerFileName)
    }

    static func stagingDirectory(for directory: URL) -> URL {
        directory.deletingLastPathComponent().appendingPathComponent(
            ".\(directory.lastPathComponent)-nemotron-\(revision)", isDirectory: true
        )
    }

    static func isInstalled(in directory: URL, files: [NemotronModelFile] = files) -> Bool {
        guard (try? String(contentsOf: completionMarkerURL(in: directory), encoding: .utf8)) == revision else {
            return false
        }
        return files.allSatisfy { file in
            let values = try? directory.appendingPathComponent(file.relativePath)
                .resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && Int64(values?.fileSize ?? -1) == file.asset.byteSize
        }
    }
}

nonisolated final class NemotronDiarizationModelDownloader: @unchecked Sendable {
    private let fileManager: FileManager
    private let assetDownloader: ModelAssetDownloading
    private let files: [NemotronModelFile]

    init(
        fileManager: FileManager = .default,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = {
            ModelDownloadProxyConfiguration.fromEnvironment()
        },
        assetDownloader: ModelAssetDownloading? = nil,
        files: [NemotronModelFile] = NemotronDiarizationModelFiles.files
    ) {
        self.fileManager = fileManager
        self.assetDownloader =
            assetDownloader
            ?? VerifiedModelAssetDownloader(
                fileManager: fileManager, proxyProvider: proxyProvider
            )
        self.files = files
    }

    func download(cacheDirectory: URL, events: @escaping @Sendable (ModelDownloadEvent) -> Void) async throws {
        let staging = NemotronDiarizationModelFiles.stagingDirectory(for: cacheDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let marker = NemotronDiarizationModelFiles.completionMarkerURL(in: staging)
        if fileManager.fileExists(atPath: marker.path) { try fileManager.removeItem(at: marker) }
        for file in files {
            try Task.checkCancellation()
            try await assetDownloader.download(
                file.asset, to: staging.appendingPathComponent(file.relativePath),
                label: "Nemotron offline",
                progress: { progress in
                    events(.downloadingArtifact(name: file.relativePath, progress: progress))
                })
        }
        events(.validating)
        let verifier = VerifiedModelAssetDownloader(fileManager: fileManager)
        for file in files {
            try Task.checkCancellation()
            try verifier.verify(file.asset, at: staging.appendingPathComponent(file.relativePath))
        }
        try Task.checkCancellation()
        try Data(NemotronDiarizationModelFiles.revision.utf8).write(to: marker, options: .atomic)
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            _ = try fileManager.replaceItemAt(cacheDirectory, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: cacheDirectory)
        }
        events(.completed)
    }
}
