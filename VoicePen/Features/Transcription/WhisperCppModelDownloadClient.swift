import Foundation

final class WhisperCppModelDownloadClient: ModelDownloadClient {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let assetDownloader: ModelAssetDownloading
    private let archiveInstaller: ModelArchiveInstalling

    init(
        paths: AppPaths,
        fileManager: FileManager = .default,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = { nil },
        assetDownloader: ModelAssetDownloading? = nil,
        archiveInstaller: ModelArchiveInstalling = ModelArchiveInstaller()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.assetDownloader =
            assetDownloader
            ?? VerifiedModelAssetDownloader(
                fileManager: fileManager,
                proxyProvider: proxyProvider
            )
        self.archiveInstaller = archiveInstaller
    }

    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        try paths.createRequiredDirectories()

        let targetDirectory = paths.userModelDirectory(for: model.id)
        let targetFile = paths.userModelFile(for: model.id, fileName: model.localArtifactFileName)
        let artifacts = model.requiredCompanionArtifacts
        let totalUnits = Double(1 + artifacts.count)
        var completedUnits = 0.0

        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        if isArtifactDownloadComplete(
            targetFile,
            marker: artifactCompletionMarker(in: targetDirectory, id: "model")
        ) {
            completedUnits += 1
            events(.downloadingArtifact(name: model.localArtifactFileName, progress: completedUnits / totalUnits))
        } else {
            guard let remoteFile = model.remoteFile else {
                throw ModelDownloadError.missingDownloadURL(model.id)
            }

            try await assetDownloader.download(
                remoteFile,
                to: targetFile,
                label: model.id,
                progress: scaledProgress(
                    events,
                    name: model.localArtifactFileName,
                    completedUnits: completedUnits,
                    totalUnits: totalUnits
                )
            )
            try markArtifactDownloadComplete(in: targetDirectory, id: "model")
            completedUnits += 1
            events(.downloadingArtifact(name: model.localArtifactFileName, progress: completedUnits / totalUnits))
        }

        for artifact in artifacts {
            let targetArtifactURL = paths.userModelArtifact(for: model.id, localPath: artifact.localPath)
            if isArtifactDownloadComplete(
                targetArtifactURL,
                marker: artifactCompletionMarker(in: targetDirectory, id: artifact.id)
            ) {
                completedUnits += 1
                events(.downloadingArtifact(name: artifact.displayName, progress: completedUnits / totalUnits))
                continue
            }

            try await downloadArtifact(
                artifact,
                model: model,
                targetDirectory: targetDirectory,
                events: events,
                progress: scaledProgress(
                    events,
                    name: artifact.displayName,
                    completedUnits: completedUnits,
                    totalUnits: totalUnits
                )
            )
            completedUnits += 1
            events(.downloadingArtifact(name: artifact.displayName, progress: completedUnits / totalUnits))
        }

        events(.validating)
        try validateInstalledModel(model)
        try markModelDownloadComplete(for: model)
        events(.completed)
        return targetDirectory
    }

    private func scaledProgress(
        _ events: @escaping @Sendable (ModelDownloadEvent) -> Void,
        name: String,
        completedUnits: Double,
        totalUnits: Double
    ) -> @Sendable (Double?) -> Void {
        { artifactProgress in
            guard let artifactProgress else {
                events(.downloadingArtifact(name: name, progress: nil))
                return
            }

            events(
                .downloadingArtifact(
                    name: name,
                    progress: (completedUnits + artifactProgress) / totalUnits
                ))
        }
    }

    private func downloadArtifact(
        _ artifact: ModelManifestArtifact,
        model: ModelManifestModel,
        targetDirectory: URL,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        guard let remoteFile = artifact.remoteFile else {
            throw ModelDownloadError.missingDownloadURL("\(model.id)/\(artifact.id)")
        }

        let downloadedFileURL = targetDirectory.appendingPathComponent(artifact.fileName)
        try await assetDownloader.download(
            remoteFile,
            to: downloadedFileURL,
            label: "\(model.id)/\(artifact.id)",
            progress: progress
        )

        let targetArtifactURL = paths.userModelArtifact(for: model.id, localPath: artifact.localPath)
        switch artifact.archiveKind {
        case .none:
            if downloadedFileURL != targetArtifactURL {
                try installFile(at: downloadedFileURL, to: targetArtifactURL)
            }
        case .zip:
            events(.extractingArtifact(name: artifact.displayName))
            try await archiveInstaller.installZip(
                at: downloadedFileURL,
                archiveRoot: artifact.resolvedArchiveRoot,
                to: targetArtifactURL,
                requiredRelativePaths: artifact.resolvedRequiredPaths
            )
            try? fileManager.removeItem(at: downloadedFileURL)
        }

        try markArtifactDownloadComplete(in: targetDirectory, id: artifact.id)
    }

    private func installFile(at sourceURL: URL, to targetURL: URL) throws {
        try fileManager.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: targetURL.path) {
            _ = try fileManager.replaceItemAt(targetURL, withItemAt: sourceURL)
        } else {
            try fileManager.moveItem(at: sourceURL, to: targetURL)
        }
    }

    private func validateInstalledModel(_ model: ModelManifestModel) throws {
        let targetDirectory = paths.userModelDirectory(for: model.id)
        var missingPaths: [String] = []

        let modelURL = paths.userModelFile(for: model.id, fileName: model.localArtifactFileName)
        if !isArtifactDownloadComplete(
            modelURL,
            marker: artifactCompletionMarker(in: targetDirectory, id: "model")
        ) {
            missingPaths.append(modelURL.path)
        }

        for artifact in model.requiredCompanionArtifacts {
            let artifactURL = paths.userModelArtifact(for: model.id, localPath: artifact.localPath)
            if !isArtifactDownloadComplete(
                artifactURL,
                marker: artifactCompletionMarker(in: targetDirectory, id: artifact.id)
            ) {
                missingPaths.append(artifactURL.path)
            }
        }

        if !missingPaths.isEmpty {
            throw TranscriptionError.modelMissing(expectedPaths: missingPaths)
        }
    }

    private func artifactCompletionMarker(in targetDirectory: URL, id: String) -> URL {
        targetDirectory
            .appendingPathComponent(".voicepen-artifacts", isDirectory: true)
            .appendingPathComponent("\(id).complete")
    }

    private func isArtifactDownloadComplete(_ artifactURL: URL, marker: URL) -> Bool {
        ModelArtifactPresence.exists(at: artifactURL, fileManager: fileManager)
            && ModelArtifactPresence.exists(at: marker, fileManager: fileManager)
    }

    private func markArtifactDownloadComplete(in targetDirectory: URL, id: String) throws {
        let markerURL = artifactCompletionMarker(in: targetDirectory, id: id)
        try fileManager.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("complete".utf8).write(to: markerURL, options: .atomic)
    }

    private func markModelDownloadComplete(for model: ModelManifestModel) throws {
        let markerURL = paths.userModelCompletionMarker(for: model.id)
        try fileManager.createDirectory(
            at: markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("complete".utf8).write(to: markerURL, options: .atomic)
    }
}
