import FluidAudio
import Foundation

final class FluidAudioModelDownloadClient: ModelDownloadClient {
    private let paths: AppPaths
    private let maximumAttempts = 4

    init(paths: AppPaths) {
        self.paths = paths
    }

    func downloadModel(
        _ model: ModelManifestModel,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        try paths.createRequiredDirectories()

        guard let version = FluidAudioModelInstallation.parakeetVersion(for: model) else {
            throw ModelDownloadError.unsupportedBackend("fluidAudio:\(model.id)")
        }
        let targetDirectory = paths.userModelDirectory(for: model.id)

        if FluidAudioModelInstallation.isInstalled(model: model, paths: paths) {
            events(.completed)
            return targetDirectory
        }

        return try await downloadWithRetry(
            model: model,
            version: version,
            targetDirectory: targetDirectory,
            events: events
        )
    }

    private func downloadWithRetry(
        model: ModelManifestModel,
        version: AsrModelVersion,
        targetDirectory: URL,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) async throws -> URL {
        var lastError: Error?

        for attempt in 1...maximumAttempts {
            do {
                let progressRelay = FluidAudioDownloadProgressRelay(
                    modelName: model.displayName,
                    events: events
                )
                let downloadedURL = try await AsrModels.download(
                    to: targetDirectory,
                    version: version
                ) { downloadProgress in
                    progressRelay.handle(downloadProgress)
                }

                events(.validating)
                guard AsrModels.modelsExist(at: targetDirectory, version: version) else {
                    throw TranscriptionError.modelMissing(expectedPaths: [targetDirectory.path])
                }
                try markModelDownloadComplete(for: model)
                events(.completed)
                return downloadedURL
            } catch {
                lastError = error
                guard attempt < maximumAttempts, error.isRetryableModelDownloadError else {
                    break
                }

                events(.downloadingArtifact(name: model.displayName, progress: nil))
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
            }
        }

        throw ModelDownloadError.downloadFailed(
            modelId: model.id,
            message: lastError?.localizedDescription ?? "Unknown download error"
        )
    }

    private func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let seconds = 1 << max(0, attempt - 1)
        return UInt64(seconds) * 1_000_000_000
    }

    private func markModelDownloadComplete(for model: ModelManifestModel) throws {
        let markerURL = paths.userModelCompletionMarker(for: model.id)
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: markerURL, options: .atomic)
    }
}

nonisolated final class FluidAudioDownloadProgressRelay: @unchecked Sendable {
    private let modelName: String
    private let events: @Sendable (ModelDownloadEvent) -> Void
    private let lock = NSLock()
    private var lastDownloadProgress = 0.0

    init(
        modelName: String,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void
    ) {
        self.modelName = modelName
        self.events = events
    }

    func handle(_ progress: DownloadUtils.DownloadProgress) {
        switch progress.phase {
        case .listing:
            emitDownloadProgress(nil)
        case let .downloading(_, totalFiles):
            guard totalFiles > 0 else { return }
            emitDownloadProgress(progress.fractionCompleted)
        case .compiling:
            events(.validating)
        }
    }

    private func emitDownloadProgress(_ progress: Double?) {
        guard let progress else {
            events(.downloadingArtifact(name: modelName, progress: nil))
            return
        }

        let normalizedProgress = min(max(progress, 0), 1)
        lock.lock()
        guard normalizedProgress >= lastDownloadProgress else {
            lock.unlock()
            return
        }
        lastDownloadProgress = normalizedProgress
        lock.unlock()

        events(.downloadingArtifact(name: modelName, progress: normalizedProgress))
    }
}
