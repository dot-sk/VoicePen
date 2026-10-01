import CoreML
import Foundation

nonisolated struct WhisperCppRuntimeState: Equatable {
    private(set) var loadedModelId: String?
    private(set) var warmedModelId: String?

    var isLoaded: Bool {
        loadedModelId != nil
    }

    func shouldWarmUp(modelId: String) -> Bool {
        warmedModelId != modelId
    }

    mutating func markLoaded(modelId: String) {
        guard loadedModelId != modelId else { return }
        loadedModelId = modelId
        warmedModelId = nil
    }

    mutating func markWarmed(modelId: String) {
        guard loadedModelId == modelId else { return }
        warmedModelId = modelId
    }
}

nonisolated struct WhisperCppLoadedContext: @unchecked Sendable {
    typealias TranscribeOperation =
        (TranscriptionRequest, String?) async throws -> TranscriptionClientResult
    typealias WarmUpOperation = (String) async throws -> Void
    typealias BenchmarkOperation =
        (URL, String, String) async throws -> [WhisperCppBenchmarkResult]

    private let transcribeOperation: TranscribeOperation
    private let warmUpOperation: WarmUpOperation
    private let benchmarkOperation: BenchmarkOperation

    init(
        transcribe: @escaping TranscribeOperation,
        warmUp: @escaping WarmUpOperation,
        benchmark: @escaping BenchmarkOperation
    ) {
        transcribeOperation = transcribe
        warmUpOperation = warmUp
        benchmarkOperation = benchmark
    }

    init(context: WhisperCppContext) {
        self.init(
            transcribe: { request, voiceActivityDetectionModelPath in
                try await context.transcribe(
                    request,
                    voiceActivityDetectionModelPath: voiceActivityDetectionModelPath
                )
            },
            warmUp: { language in
                try await context.warmUp(language: language)
            },
            benchmark: { audioURL, prompt, language in
                try await context.benchmark(
                    audioURL: audioURL,
                    prompt: prompt,
                    language: language
                )
            }
        )
    }

    func transcribe(
        _ request: TranscriptionRequest,
        voiceActivityDetectionModelPath: String?
    ) async throws -> TranscriptionClientResult {
        try await transcribeOperation(
            request,
            voiceActivityDetectionModelPath
        )
    }

    func warmUp(language: String) async throws {
        try await warmUpOperation(language)
    }

    func benchmark(
        audioURL: URL,
        prompt: String,
        language: String
    ) async throws -> [WhisperCppBenchmarkResult] {
        try await benchmarkOperation(audioURL, prompt, language)
    }
}

typealias WhisperCppContextLoader =
    @Sendable (_ modelPath: String) throws -> WhisperCppLoadedContext

nonisolated enum WhisperCppModelLoadEvent: Equatable, Sendable {
    case started(modelId: String, generation: UInt64)
    case joined(modelId: String, generation: UInt64)
    case waitingForOtherModel(requestedModelId: String, loadingModelId: String, generation: UInt64)
    case requesterCanceled(requestedModelId: String, loadingModelId: String, generation: UInt64)
    case completed(modelId: String, generation: UInt64)
    case failed(modelId: String, generation: UInt64, message: String)
}

nonisolated private enum WhisperCppModelLoadDiagnostics {
    static func log(_ event: WhisperCppModelLoadEvent) {
        switch event {
        case let .started(modelId, generation):
            AppLogger.info("Whisper model load started: model=\(modelId), generation=\(generation)")
        case let .joined(modelId, generation):
            AppLogger.info("Whisper model load joined: model=\(modelId), generation=\(generation)")
        case let .waitingForOtherModel(requestedModelId, loadingModelId, generation):
            AppLogger.info(
                "Whisper model load waiting: requested=\(requestedModelId), loading=\(loadingModelId), generation=\(generation)"
            )
        case let .requesterCanceled(requestedModelId, loadingModelId, generation):
            AppLogger.info(
                "Whisper model load requester canceled: requested=\(requestedModelId), loading=\(loadingModelId), generation=\(generation)"
            )
        case let .completed(modelId, generation):
            AppLogger.info("Whisper model load completed: model=\(modelId), generation=\(generation)")
        case let .failed(modelId, generation, message):
            AppLogger.error(
                "Whisper model load failed: model=\(modelId), generation=\(generation), error=\(message)"
            )
        }
    }
}

nonisolated private enum WhisperCppModelLoadWaitError: Error {
    case loadChanged
}

private struct WhisperCppActiveModelLoad {
    let modelId: String
    let generation: UInt64
    let task: Task<WhisperCppLoadedContext, Error>
    var waiters: [UUID: CheckedContinuation<WhisperCppLoadedContext, Error>] = [:]
}

actor WhisperCppTranscriptionClient {
    private let paths: AppPaths
    private let voiceActivityDetectionModelURLProvider: @Sendable () -> URL?
    private let contextLoader: WhisperCppContextLoader
    private let modelLoadEventHandler: @Sendable (WhisperCppModelLoadEvent) -> Void
    private var runtimeState = WhisperCppRuntimeState()
    private var context: WhisperCppLoadedContext?
    private var activeLoad: WhisperCppActiveModelLoad?
    private var loadGeneration: UInt64 = 0

    init(
        paths: AppPaths,
        voiceActivityDetectionModelURLProvider: @escaping @Sendable () -> URL? = {
            WhisperCppVoiceActivityDetection.bundledModelURL()
        },
        contextLoader: @escaping WhisperCppContextLoader = { modelPath in
            WhisperCppLoadedContext(context: try WhisperCppContext(modelPath: modelPath))
        },
        modelLoadEventHandler: @escaping @Sendable (WhisperCppModelLoadEvent) -> Void = {
            WhisperCppModelLoadDiagnostics.log($0)
        }
    ) {
        self.paths = paths
        self.voiceActivityDetectionModelURLProvider = voiceActivityDetectionModelURLProvider
        self.contextLoader = contextLoader
        self.modelLoadEventHandler = modelLoadEventHandler
    }

    func prepareTranscription(
        model: ModelManifestModel
    ) async throws -> PreparedTranscription {
        let context = try await loadContextIfNeeded(for: model)
        let voiceActivityDetectionModelURLProvider = voiceActivityDetectionModelURLProvider

        return PreparedTranscription { [self] request in
            let isVoiceActivityDetectionRequested = request.options.contains(.voiceActivityDetection)
            let voiceActivityDetectionModelPath = WhisperCppVoiceActivityDetection.existingModelPath(
                requested: isVoiceActivityDetectionRequested,
                modelURL: isVoiceActivityDetectionRequested
                    ? voiceActivityDetectionModelURLProvider()
                    : nil
            )
            do {
                let result = try await context.transcribe(
                    request,
                    voiceActivityDetectionModelPath: voiceActivityDetectionModelPath
                )
                markWarmedIfCurrent(modelId: model.id)
                return result
            } catch TranscriptionError.emptyResult {
                markWarmedIfCurrent(modelId: model.id)
                throw TranscriptionError.emptyResult
            }
        }
    }

    func transcribe(
        _ request: TranscriptionRequest,
        model: ModelManifestModel
    ) async throws -> TranscriptionClientResult {
        let prepared = try await prepareTranscription(
            model: model
        )
        return try await prepared.transcribe(request)
    }

    func warmUp(
        model: ModelManifestModel,
        language: String
    ) async throws {
        guard runtimeState.shouldWarmUp(modelId: model.id) else {
            return
        }

        let context = try await loadContextIfNeeded(for: model)
        try await context.warmUp(language: language)
        markWarmedIfCurrent(modelId: model.id)
    }

    func benchmark(
        audioURL: URL,
        model: ModelManifestModel,
        glossaryPrompt: String,
        language: String
    ) async throws -> [WhisperCppBenchmarkResult] {
        let context = try await loadContextIfNeeded(for: model)
        return try await context.benchmark(
            audioURL: audioURL,
            prompt: glossaryPrompt,
            language: language
        )
    }

    private func loadContextIfNeeded(for model: ModelManifestModel) async throws -> WhisperCppLoadedContext {
        while true {
            if let activeLoad {
                if activeLoad.modelId == model.id {
                    modelLoadEventHandler(
                        .joined(modelId: model.id, generation: activeLoad.generation)
                    )
                } else {
                    modelLoadEventHandler(
                        .waitingForOtherModel(
                            requestedModelId: model.id,
                            loadingModelId: activeLoad.modelId,
                            generation: activeLoad.generation
                        )
                    )
                }

                do {
                    let loadedContext = try await waitForActiveLoad(
                        requestedModelId: model.id,
                        loadingModelId: activeLoad.modelId,
                        generation: activeLoad.generation
                    )
                    if activeLoad.modelId == model.id {
                        return loadedContext
                    }
                    try Task.checkCancellation()
                    continue
                } catch is CancellationError {
                    throw CancellationError()
                } catch WhisperCppModelLoadWaitError.loadChanged {
                    continue
                } catch {
                    if activeLoad.modelId == model.id {
                        throw error
                    }
                    try Task.checkCancellation()
                    continue
                }
            }

            if runtimeState.loadedModelId == model.id, let context {
                return context
            }

            let modelPath = try validatedModelPath(for: model)
            let generation = nextLoadGeneration()
            let contextLoader = contextLoader
            let loadTask = Task.detached(priority: .utility) {
                try contextLoader(modelPath)
            }
            activeLoad = WhisperCppActiveModelLoad(
                modelId: model.id,
                generation: generation,
                task: loadTask
            )
            modelLoadEventHandler(.started(modelId: model.id, generation: generation))

            Task { [weak self] in
                let result = await loadTask.result
                await self?.finishModelLoad(
                    modelId: model.id,
                    generation: generation,
                    result: result
                )
            }

            return try await waitForActiveLoad(
                requestedModelId: model.id,
                loadingModelId: model.id,
                generation: generation
            )
        }
    }

    private func waitForActiveLoad(
        requestedModelId: String,
        loadingModelId: String,
        generation: UInt64
    ) async throws -> WhisperCppLoadedContext {
        let waiterId = UUID()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard var activeLoad,
                    activeLoad.modelId == loadingModelId,
                    activeLoad.generation == generation
                else {
                    continuation.resume(throwing: WhisperCppModelLoadWaitError.loadChanged)
                    return
                }

                activeLoad.waiters[waiterId] = continuation
                self.activeLoad = activeLoad
            }
        } onCancel: {
            Task {
                await self.cancelLoadWaiter(
                    id: waiterId,
                    requestedModelId: requestedModelId,
                    loadingModelId: loadingModelId,
                    generation: generation
                )
            }
        }
    }

    private func cancelLoadWaiter(
        id: UUID,
        requestedModelId: String,
        loadingModelId: String,
        generation: UInt64
    ) {
        guard var activeLoad,
            activeLoad.modelId == loadingModelId,
            activeLoad.generation == generation,
            let continuation = activeLoad.waiters.removeValue(forKey: id)
        else {
            return
        }

        self.activeLoad = activeLoad
        modelLoadEventHandler(
            .requesterCanceled(
                requestedModelId: requestedModelId,
                loadingModelId: loadingModelId,
                generation: generation
            )
        )
        continuation.resume(throwing: CancellationError())
    }

    private func finishModelLoad(
        modelId: String,
        generation: UInt64,
        result: Result<WhisperCppLoadedContext, Error>
    ) {
        guard let activeLoad,
            activeLoad.modelId == modelId,
            activeLoad.generation == generation
        else {
            return
        }

        self.activeLoad = nil
        switch result {
        case let .success(loadedContext):
            context = loadedContext
            runtimeState.markLoaded(modelId: modelId)
            modelLoadEventHandler(.completed(modelId: modelId, generation: generation))
            activeLoad.waiters.values.forEach { $0.resume(returning: loadedContext) }
        case let .failure(error):
            modelLoadEventHandler(
                .failed(
                    modelId: modelId,
                    generation: generation,
                    message: error.localizedDescription
                )
            )
            activeLoad.waiters.values.forEach { $0.resume(throwing: error) }
        }
    }

    private func markWarmedIfCurrent(modelId: String) {
        runtimeState.markWarmed(modelId: modelId)
    }

    private func nextLoadGeneration() -> UInt64 {
        loadGeneration &+= 1
        return loadGeneration
    }

    private func validatedModelPath(for model: ModelManifestModel) throws -> String {
        try validateAcceleration(for: model)

        let missingArtifactPaths = model.missingArtifactURLs(paths: paths).map(\.path)
        guard missingArtifactPaths.isEmpty else {
            throw TranscriptionError.modelMissing(expectedPaths: missingArtifactPaths)
        }

        guard
            let modelURL = paths.existingModelFile(
                for: model.id,
                fileName: model.localArtifactFileName
            )
        else {
            throw TranscriptionError.modelMissing(expectedPaths: model.expectedArtifactURLs(paths: paths).map(\.path))
        }
        return modelURL.path
    }

    private func validateAcceleration(for model: ModelManifestModel) throws {
        let status = ModelAccelerationStatus.inspect(model: model, paths: paths)
        let requiresCoreMLEncoder = model.requiredCompanionArtifacts.contains { $0.id == "coreml-encoder" }
        guard !requiresCoreMLEncoder || status.isCoreMLReady else {
            let expectedPaths = model.requiredCompanionArtifacts
                .filter { $0.id == "coreml-encoder" }
                .map { paths.userModelArtifact(for: model.id, localPath: $0.localPath).path }
                .joined(separator: "\n")
            throw TranscriptionError.accelerationUnavailable(
                modelId: model.id,
                message: "Core ML encoder is required and was not found.\n\(expectedPaths)"
            )
        }

        for artifact in model.requiredCompanionArtifacts where artifact.id == "coreml-encoder" {
            guard let url = paths.existingModelArtifact(for: model.id, localPath: artifact.localPath) else {
                throw TranscriptionError.accelerationUnavailable(
                    modelId: model.id,
                    message: "Core ML encoder is missing at \(artifact.localPath)."
                )
            }

            do {
                _ = try MLModel(contentsOf: url)
            } catch {
                throw TranscriptionError.accelerationUnavailable(
                    modelId: model.id,
                    message: "Core ML encoder exists but could not be loaded: \(error.localizedDescription)"
                )
            }
        }
    }
}
