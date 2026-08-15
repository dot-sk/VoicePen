import CryptoKit
import Foundation

nonisolated struct ModelAssetRemoteFile: Codable, Equatable, Sendable {
    let downloadURL: String
    let byteSize: Int64
    let sha256: String

    var url: URL? {
        URL(string: downloadURL)
    }
}

nonisolated enum ModelAssetValidationError: LocalizedError, Equatable {
    case invalidDescriptor(String)
    case unexpectedByteSize(expected: Int64, actual: Int64)
    case sha256Mismatch(expected: String, actual: String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidDescriptor(message):
            "Invalid model asset descriptor: \(message)"
        case let .unexpectedByteSize(expected, actual):
            "Downloaded model asset has \(actual) bytes; expected \(expected)."
        case let .sha256Mismatch(expected, actual):
            "Downloaded model asset SHA-256 is \(actual); expected \(expected)."
        case let .httpStatus(statusCode):
            "Model asset server returned HTTP \(statusCode)."
        }
    }
}

nonisolated enum ModelDownloadSessionConfiguration {
    static func make(proxy: ModelDownloadProxyConfiguration?) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false
        if let proxy {
            configuration.connectionProxyDictionary = proxy.connectionProxyDictionary
        }
        return configuration
    }
}

nonisolated protocol ModelAssetDownloading: Sendable {
    func download(
        _ asset: ModelAssetRemoteFile,
        to destinationURL: URL,
        label: String,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws
}

nonisolated protocol ModelArchiveInstalling: Sendable {
    func installZip(
        at zipURL: URL,
        archiveRoot: String,
        to targetURL: URL,
        requiredRelativePaths: [String]
    ) async throws
}

nonisolated final class VerifiedModelAssetDownloader: ModelAssetDownloading, @unchecked Sendable {
    typealias ConfigurationProvider = @Sendable (ModelDownloadProxyConfiguration?) -> URLSessionConfiguration
    typealias RetryDelay = @Sendable (Int) async throws -> Void

    private let fileManager: FileManager
    private let proxyProvider: @Sendable () -> ModelDownloadProxyConfiguration?
    private let configurationProvider: ConfigurationProvider
    private let retryDelay: RetryDelay
    private let maximumAttempts: Int

    init(
        fileManager: FileManager = .default,
        proxyProvider: @escaping @Sendable () -> ModelDownloadProxyConfiguration? = { nil },
        configurationProvider: @escaping ConfigurationProvider = { proxy in
            ModelDownloadSessionConfiguration.make(proxy: proxy)
        },
        maximumAttempts: Int = 4,
        retryDelay: @escaping RetryDelay = { attempt in
            let seconds = 1 << max(0, attempt - 1)
            try await Task.sleep(for: .seconds(Double(seconds)))
        }
    ) {
        self.fileManager = fileManager
        self.proxyProvider = proxyProvider
        self.configurationProvider = configurationProvider
        self.maximumAttempts = max(1, maximumAttempts)
        self.retryDelay = retryDelay
    }

    func download(
        _ asset: ModelAssetRemoteFile,
        to destinationURL: URL,
        label: String,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        try validateDescriptor(asset)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            do {
                try verify(asset, at: destinationURL)
                progress(1)
                return
            } catch {
                try fileManager.removeItem(at: destinationURL)
            }
        }

        let partialURL = destinationURL.appendingPathExtension("partial")
        if fileSize(at: partialURL) > asset.byteSize {
            try fileManager.removeItem(at: partialURL)
        }
        if fileSize(at: partialURL) == asset.byteSize {
            do {
                try verify(asset, at: partialURL)
                try installDownloadedFile(at: partialURL, to: destinationURL)
                progress(1)
                return
            } catch {
                try fileManager.removeItem(at: partialURL)
            }
        }

        var lastError: Error?
        for attempt in 1...maximumAttempts {
            do {
                try Task.checkCancellation()
                AppLogger.info("Downloading model asset \(label), attempt \(attempt)")
                try await transfer(
                    asset,
                    to: partialURL,
                    progress: progress
                )
                try verify(asset, at: partialURL)
                try installDownloadedFile(at: partialURL, to: destinationURL)
                progress(1)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if error.isCancellationError {
                    throw CancellationError()
                }

                if let validationError = error as? ModelAssetValidationError,
                    !validationError.isRetryableModelDownloadError
                {
                    if case .httpStatus = validationError {
                        throw validationError
                    }
                    try? fileManager.removeItem(at: partialURL)
                    throw validationError
                }

                lastError = error
                guard attempt < maximumAttempts, error.isRetryableModelDownloadError else {
                    break
                }

                AppLogger.info("Retrying model asset \(label) after download error: \(error.localizedDescription)")
                progress(nil)
                try await retryDelay(attempt)
            }
        }

        throw ModelDownloadError.downloadFailed(
            modelId: label,
            message: lastError?.localizedDescription ?? "Unknown download error"
        )
    }

    func verify(_ asset: ModelAssetRemoteFile, at fileURL: URL) throws {
        let actualSize = fileSize(at: fileURL)
        guard actualSize == asset.byteSize else {
            throw ModelAssetValidationError.unexpectedByteSize(
                expected: asset.byteSize,
                actual: actualSize
            )
        }

        let actualDigest = try sha256(of: fileURL)
        let expectedDigest = asset.sha256.lowercased()
        guard actualDigest == expectedDigest else {
            throw ModelAssetValidationError.sha256Mismatch(
                expected: expectedDigest,
                actual: actualDigest
            )
        }
    }

    private func validateDescriptor(_ asset: ModelAssetRemoteFile) throws {
        guard let url = asset.url, url.scheme == "https", url.host != nil else {
            throw ModelAssetValidationError.invalidDescriptor("downloadURL must be an absolute HTTPS URL")
        }
        guard asset.byteSize > 0 else {
            throw ModelAssetValidationError.invalidDescriptor("byteSize must be positive")
        }
        let digest = asset.sha256.lowercased()
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else {
            throw ModelAssetValidationError.invalidDescriptor("sha256 must contain 64 hexadecimal characters")
        }
    }

    private func transfer(
        _ asset: ModelAssetRemoteFile,
        to partialURL: URL,
        progress: @escaping @Sendable (Double?) -> Void
    ) async throws {
        guard let sourceURL = asset.url else {
            throw ModelAssetValidationError.invalidDescriptor("downloadURL is invalid")
        }

        let existingByteCount = max(0, fileSize(at: partialURL))
        var request = URLRequest(url: sourceURL)
        if existingByteCount > 0 {
            request.setValue("bytes=\(existingByteCount)-", forHTTPHeaderField: "Range")
        }

        let operation = StreamingModelAssetDownload(
            partialURL: partialURL,
            existingByteCount: existingByteCount,
            expectedByteCount: asset.byteSize,
            progress: progress
        )
        let configuration = configurationProvider(proxyProvider())
        try await operation.run(configuration: configuration, request: request)
    }

    private func installDownloadedFile(at partialURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: partialURL)
        } else {
            try fileManager.moveItem(at: partialURL, to: destinationURL)
        }
    }

    private func fileSize(at fileURL: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
            let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated final class ModelArchiveInstaller: ModelArchiveInstalling, @unchecked Sendable {
    typealias Extractor = @Sendable (URL, URL) async throws -> Void

    private let fileManager: FileManager
    private let extractor: Extractor

    init(
        fileManager: FileManager = .default,
        extractor: @escaping Extractor = { zipURL, targetDirectory in
            try await ModelArchiveInstaller.extractWithDitto(zipURL, targetDirectory)
        }
    ) {
        self.fileManager = fileManager
        self.extractor = extractor
    }

    func installZip(
        at zipURL: URL,
        archiveRoot: String,
        to targetURL: URL,
        requiredRelativePaths: [String]
    ) async throws {
        let parentDirectory = targetURL.deletingLastPathComponent()
        let stagingDirectory = parentDirectory.appendingPathComponent(
            ".voicepen-model-staging-\(UUID().uuidString)",
            isDirectory: true
        )
        let backupName = ".voicepen-model-backup-\(UUID().uuidString)"
        let backupURL = parentDirectory.appendingPathComponent(backupName, isDirectory: true)

        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: stagingDirectory)
            try? fileManager.removeItem(at: backupURL)
        }

        do {
            try await extractor(zipURL, stagingDirectory)
            let extractedRoot = stagingDirectory.appendingPathComponent(archiveRoot, isDirectory: true)
            for requiredPath in requiredRelativePaths {
                let requiredURL = extractedRoot.appendingPathComponent(requiredPath)
                guard ModelArtifactPresence.exists(at: requiredURL, fileManager: fileManager) else {
                    throw ModelDownloadError.archiveExtractionFailed(
                        modelId: targetURL.lastPathComponent,
                        artifactId: zipURL.lastPathComponent,
                        message: "Expected \(requiredPath) in the verified archive."
                    )
                }
            }

            if fileManager.fileExists(atPath: targetURL.path) {
                _ = try fileManager.replaceItemAt(
                    targetURL,
                    withItemAt: extractedRoot,
                    backupItemName: backupName
                )
            } else {
                try fileManager.moveItem(at: extractedRoot, to: targetURL)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ModelDownloadError {
            throw error
        } catch {
            throw ModelDownloadError.archiveExtractionFailed(
                modelId: targetURL.lastPathComponent,
                artifactId: zipURL.lastPathComponent,
                message: error.localizedDescription
            )
        }
    }

    private static func extractWithDitto(_ zipURL: URL, _ targetDirectory: URL) async throws {
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
                    let message = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    state.complete(
                        .failure(
                            ModelDownloadError.downloadFailed(
                                modelId: zipURL.lastPathComponent,
                                message: message?.isEmpty == false
                                    ? message!
                                    : "ditto exited with status \(process.terminationStatus)"
                            )))
                }

                do {
                    guard state.set(continuation: continuation, process: process) else {
                        return
                    }
                    try process.run()
                } catch {
                    state.complete(.failure(error))
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}

nonisolated private final class StreamingModelAssetDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let partialURL: URL
    private let existingByteCount: Int64
    private let expectedByteCount: Int64
    private let progress: @Sendable (Double?) -> Void

    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var receivedByteCount: Int64 = 0
    private var responseError: Error?
    private var cancellationRequested = false
    private var didComplete = false

    init(
        partialURL: URL,
        existingByteCount: Int64,
        expectedByteCount: Int64,
        progress: @escaping @Sendable (Double?) -> Void
    ) {
        self.partialURL = partialURL
        self.existingByteCount = existingByteCount
        self.expectedByteCount = expectedByteCount
        self.progress = progress
    }

    func run(configuration: URLSessionConfiguration, request: URLRequest) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let delegateQueue = OperationQueue()
                delegateQueue.maxConcurrentOperationCount = 1
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: delegateQueue
                )
                let task = session.dataTask(with: request)

                lock.lock()
                self.continuation = continuation
                self.session = session
                self.task = task
                let shouldCancel = cancellationRequested
                lock.unlock()

                if shouldCancel {
                    task.cancel()
                } else {
                    task.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            responseError = ModelAssetValidationError.invalidDescriptor("server response was not HTTP")
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            responseError = ModelAssetValidationError.httpStatus(response.statusCode)
            completionHandler(.cancel)
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: partialURL.path) {
                FileManager.default.createFile(atPath: partialURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: partialURL)
            if response.statusCode == 206, existingByteCount > 0 {
                try handle.seekToEnd()
                receivedByteCount = existingByteCount
            } else {
                try handle.truncate(atOffset: 0)
                receivedByteCount = 0
            }
            fileHandle = handle
            reportProgress()
            completionHandler(.allow)
        } catch {
            responseError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard let fileHandle else {
                throw CocoaError(.fileWriteUnknown)
            }
            try fileHandle.write(contentsOf: data)
            receivedByteCount += Int64(data.count)
            reportProgress()
        } catch {
            responseError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? fileHandle?.close()
        fileHandle = nil

        lock.lock()
        let wasCancelled = cancellationRequested
        lock.unlock()

        if wasCancelled {
            complete(.failure(CancellationError()))
        } else if let responseError {
            complete(.failure(responseError))
        } else if let error {
            complete(.failure(error))
        } else {
            complete(.success(()))
        }
    }

    private func reportProgress() {
        guard expectedByteCount > 0 else {
            progress(nil)
            return
        }
        progress(min(1, Double(receivedByteCount) / Double(expectedByteCount)))
    }

    private func cancel() {
        lock.lock()
        cancellationRequested = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    private func complete(_ result: Result<Void, Error>) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        let continuation = continuation
        self.continuation = nil
        let session = session
        self.session = nil
        task = nil
        lock.unlock()

        session?.finishTasksAndInvalidate()
        continuation?.resume(with: result)
    }
}

nonisolated private final class CancellableProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var process: Process?
    private var didComplete = false

    func set(continuation: CheckedContinuation<Void, Error>, process: Process) -> Bool {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        self.process = process
        lock.unlock()
        return true
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
        if let validationError = self as? ModelAssetValidationError,
            case let .httpStatus(statusCode) = validationError
        {
            return [408, 429, 500, 502, 503, 504].contains(statusCode)
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
