import Alamofire
import Foundation

final class WhisperCppModelDownloadClient: ModelDownloadClient {
    private let paths: AppPaths
    private let fileManager: FileManager
    private let proxyProvider: @Sendable () -> ModelDownloadProxyConfiguration?
    private let maximumAttempts = 4

    init(
        paths: AppPaths,
        fileManager: FileManager = .default,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = { nil }
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.proxyProvider = proxyProvider
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

        if isArtifactDownloadComplete(targetFile, marker: artifactCompletionMarker(in: targetDirectory, id: "model")) {
            completedUnits += 1
            events(.downloadingArtifact(name: model.localArtifactFileName, progress: completedUnits / totalUnits))
        } else {
            guard let downloadURLString = model.downloadURL,
                let downloadURL = URL(string: downloadURLString)
            else {
                throw ModelDownloadError.missingDownloadURL(model.id)
            }

            try await downloadWithRetry(
                from: downloadURL,
                to: targetFile,
                modelId: model.id,
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
            if isArtifactDownloadComplete(targetArtifactURL, marker: artifactCompletionMarker(in: targetDirectory, id: artifact.id)) {
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

            events(.downloadingArtifact(name: name, progress: (completedUnits + artifactProgress) / totalUnits))
        }
    }

    private func downloadArtifact(
        _ artifact: ModelManifestArtifact,
        model: ModelManifestModel,
        targetDirectory: URL,
        events: @escaping @Sendable (ModelDownloadEvent) -> Void,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        guard let downloadURL = URL(string: artifact.downloadURL) else {
            throw ModelDownloadError.missingDownloadURL("\(model.id)/\(artifact.id)")
        }

        let downloadedFileURL = targetDirectory.appendingPathComponent(artifact.fileName)
        try await downloadWithRetry(
            from: downloadURL,
            to: downloadedFileURL,
            modelId: model.id,
            progress: progress
        )

        switch artifact.archiveKind {
        case .none:
            let targetArtifactURL = paths.userModelArtifact(for: model.id, localPath: artifact.localPath)
            if downloadedFileURL != targetArtifactURL {
                if fileManager.fileExists(atPath: targetArtifactURL.path) {
                    try fileManager.removeItem(at: targetArtifactURL)
                }
                try fileManager.createDirectory(at: targetArtifactURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: downloadedFileURL, to: targetArtifactURL)
            }
            try markArtifactDownloadComplete(in: targetDirectory, id: artifact.id)
        case .zip:
            events(.extractingArtifact(name: artifact.displayName))
            try await extractZipArtifact(
                downloadedFileURL,
                artifact: artifact,
                model: model,
                targetDirectory: targetDirectory
            )
            try markArtifactDownloadComplete(in: targetDirectory, id: artifact.id)
        }
    }

    private func validateInstalledModel(_ model: ModelManifestModel) throws {
        let targetDirectory = paths.userModelDirectory(for: model.id)
        var missingPaths: [String] = []

        let modelURL = paths.userModelFile(for: model.id, fileName: model.localArtifactFileName)
        if !isArtifactDownloadComplete(modelURL, marker: artifactCompletionMarker(in: targetDirectory, id: "model")) {
            missingPaths.append(modelURL.path)
        }

        for artifact in model.requiredCompanionArtifacts {
            let artifactURL = paths.userModelArtifact(for: model.id, localPath: artifact.localPath)
            if !isArtifactDownloadComplete(artifactURL, marker: artifactCompletionMarker(in: targetDirectory, id: artifact.id)) {
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
        try fileManager.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: markerURL, options: .atomic)
    }

    private func markModelDownloadComplete(for model: ModelManifestModel) throws {
        let markerURL = paths.userModelCompletionMarker(for: model.id)
        try fileManager.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("complete".utf8).write(to: markerURL, options: .atomic)
    }

    private func extractZipArtifact(
        _ zipURL: URL,
        artifact: ModelManifestArtifact,
        model: ModelManifestModel,
        targetDirectory: URL
    ) async throws {
        let targetArtifactURL = paths.userModelArtifact(for: model.id, localPath: artifact.localPath)

        do {
            if fileManager.fileExists(atPath: targetArtifactURL.path) {
                try fileManager.removeItem(at: targetArtifactURL)
            }

            try await runDittoExtract(zipURL: zipURL, targetDirectory: targetDirectory)
            try? fileManager.removeItem(at: zipURL)

            guard ModelArtifactPresence.exists(at: targetArtifactURL, fileManager: fileManager) else {
                throw ModelDownloadError.archiveExtractionFailed(
                    modelId: model.id,
                    artifactId: artifact.id,
                    message: "Expected \(targetArtifactURL.path) after extracting \(artifact.fileName)."
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ModelDownloadError {
            throw error
        } catch {
            throw ModelDownloadError.archiveExtractionFailed(
                modelId: model.id,
                artifactId: artifact.id,
                message: error.localizedDescription
            )
        }
    }

    private func runDittoExtract(zipURL: URL, targetDirectory: URL) async throws {
        let state = CancellableProcessState()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                process.arguments = ["-x", "-k", zipURL.path, targetDirectory.path]

                let errorPipe = Pipe()
                process.standardError = errorPipe
                process.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        state.complete(.success(()))
                        return
                    }

                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    state.complete(
                        .failure(
                            ModelDownloadError.downloadFailed(
                                modelId: zipURL.lastPathComponent,
                                message: message?.isEmpty == false ? message! : "ditto exited with status \(process.terminationStatus)"
                            )))
                }

                do {
                    state.set(continuation: continuation, process: process)
                    try process.run()
                } catch {
                    state.complete(.failure(error))
                }
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func downloadWithRetry(
        from sourceURL: URL,
        to destinationURL: URL,
        modelId: String,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        var lastError: Error?

        for attempt in 1...maximumAttempts {
            do {
                try Task.checkCancellation()
                AppLogger.info("Downloading \(sourceURL.lastPathComponent), attempt \(attempt)")
                try await downloadFile(from: sourceURL, to: destinationURL, progress: progress)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if error.isCancellationError {
                    throw CancellationError()
                }

                lastError = error
                guard attempt < maximumAttempts, error.isRetryableModelDownloadError else {
                    break
                }

                AppLogger.info("Retrying \(sourceURL.lastPathComponent) after download error: \(error.localizedDescription)")
                progress(nil)
                try await Task.sleep(nanoseconds: retryDelayNanoseconds(forAttempt: attempt))
            }
        }

        throw ModelDownloadError.downloadFailed(
            modelId: modelId,
            message: lastError?.localizedDescription ?? "Unknown download error"
        )
    }

    private func downloadFile(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        let configuration = URLSessionConfiguration.af.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false
        if let proxy = proxyProvider() {
            configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        }
        let session = Session(configuration: configuration)
        let state = CancellableDownloadState()
        let destination: DownloadRequest.Destination = { _, _ in
            (destinationURL, [.removePreviousFile, .createIntermediateDirectories])
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let request =
                    session
                    .download(sourceURL, to: destination)
                    .validate()
                    .downloadProgress { downloadProgress in
                        let fraction = downloadProgress.fractionCompleted
                        progress(fraction.isFinite ? fraction : nil)
                    }
                    .response { response in
                        session.cancelAllRequests()

                        if let error = response.error {
                            if error.isCancellationError {
                                state.complete(.failure(CancellationError()))
                            } else {
                                state.complete(.failure(error))
                            }
                            return
                        }

                        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
                            state.complete(
                                .failure(
                                    ModelDownloadError.downloadFailed(
                                        modelId: sourceURL.lastPathComponent,
                                        message: "The downloaded file was missing after Alamofire completed the request."
                                    )))
                            return
                        }

                        state.complete(.success(()))
                    }

                state.set(continuation: continuation, request: request)
                request.resume()
            }
        } onCancel: {
            state.cancel()
        }
    }

    private func retryDelayNanoseconds(forAttempt attempt: Int) -> UInt64 {
        let seconds = 1 << max(0, attempt - 1)
        return UInt64(seconds) * 1_000_000_000
    }
}

nonisolated private final class CancellableDownloadState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var request: DownloadRequest?
    private var didComplete = false

    func set(
        continuation: CheckedContinuation<Void, Error>,
        request: DownloadRequest
    ) {
        lock.lock()
        self.continuation = continuation
        self.request = request
        let shouldCancel = didComplete
        lock.unlock()

        if shouldCancel {
            request.cancel()
        }
    }

    func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }

        didComplete = true
        let continuation = continuation
        self.continuation = nil
        request = nil
        lock.unlock()

        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }

        didComplete = true
        let continuation = continuation
        self.continuation = nil
        let request = request
        self.request = nil
        lock.unlock()

        request?.cancel()
        continuation?.resume(throwing: CancellationError())
    }
}

nonisolated private final class CancellableProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var process: Process?
    private var didComplete = false

    func set(continuation: CheckedContinuation<Void, Error>, process: Process) {
        lock.lock()
        self.continuation = continuation
        self.process = process
        let shouldCancel = didComplete
        lock.unlock()

        if shouldCancel {
            process.terminate()
        }
    }

    func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }

        didComplete = true
        let continuation = continuation
        self.continuation = nil
        process = nil
        lock.unlock()

        continuation?.resume(with: result)
    }

    func cancel() {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }

        didComplete = true
        let continuation = continuation
        self.continuation = nil
        let process = process
        self.process = nil
        lock.unlock()

        process?.terminate()
        continuation?.resume(throwing: CancellationError())
    }
}

extension Error {
    nonisolated var isCancellationError: Bool {
        if self is CancellationError {
            return true
        }

        if let afError = asAFError, afError.isExplicitlyCancelledError {
            return true
        }

        let error = self as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            return true
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return (underlyingError as Error).isCancellationError
        }

        return false
    }

    nonisolated var isRetryableModelDownloadError: Bool {
        if let afError = asAFError {
            if let underlyingError = afError.underlyingError {
                return underlyingError.isRetryableModelDownloadError
            }

            if case let .responseValidationFailed(reason) = afError,
                case let .unacceptableStatusCode(code) = reason
            {
                return [408, 429, 500, 502, 503, 504].contains(code)
            }

            return false
        }

        let error = self as NSError
        if error.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorInternationalRoamingOff,
                NSURLErrorCallIsActive,
                NSURLErrorDataNotAllowed
            ].contains(error.code)
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            return (underlyingError as Error).isRetryableModelDownloadError
        }

        return false
    }
}
