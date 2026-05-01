import Foundation
import FluidAudio

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

        let version = try parakeetVersion(for: model)
        let targetDirectory = paths.userModelDirectory(for: model.id)

        if AsrModels.modelsExist(at: targetDirectory, version: version) {
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

    private func parakeetVersion(for model: ModelManifestModel) throws -> AsrModelVersion {
        switch model.id {
        case "parakeet-tdt-0.6b-v3":
            return .v3
        case "parakeet-tdt-0.6b-v2":
            return .v2
        default:
            throw ModelDownloadError.unsupportedBackend("fluidAudio:\(model.id)")
        }
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
                let downloadedURL = try await AsrModels.download(
                    to: targetDirectory,
                    version: version
                ) { downloadProgress in
                    events(.downloadingArtifact(
                        name: model.displayName,
                        progress: downloadProgress.fractionCompleted
                    ))
                }

                events(.validating)
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
}
