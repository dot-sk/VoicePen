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
        (TranscriptionRequest, LocalDecodingProfile, String?) async throws -> TranscriptionClientResult
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
            transcribe: { request, decodingProfile, voiceActivityDetectionModelPath in
                try await context.transcribe(
                    request,
                    decodingProfile: decodingProfile,
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
        decodingProfile: LocalDecodingProfile,
        voiceActivityDetectionModelPath: String?
    ) async throws -> TranscriptionClientResult {
        try await transcribeOperation(
            request,
            decodingProfile,
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
    let identity: String
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
    private var contextIdentity: String?
    private var activeLoad: WhisperCppActiveModelLoad?
    private var loadGeneration: UInt64 = 0
    private let executionGate = NativeExecutionGate.shared
    private var owners: [String: Int] = [:]
    private var inactiveModelIDs = Set<String>()

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
        model: ModelManifestModel,
        decodingProfile: LocalDecodingProfile
    ) async throws -> PreparedTranscription {
        inactiveModelIDs.remove(model.id)
        let context = try await loadContextIfNeeded(for: model)
        owners[model.id, default: 0] += 1
        let lease = NativeContextLease { [weak self] in Task { await self?.releaseOwner(model.id) } }
        let voiceActivityDetectionModelURLProvider = voiceActivityDetectionModelURLProvider
        let gate = executionGate

        return PreparedTranscription { [self] request in
            _ = lease
            let isVoiceActivityDetectionRequested = request.options.contains(.voiceActivityDetection)
            let voiceActivityDetectionModelPath = WhisperCppVoiceActivityDetection.existingModelPath(
                requested: isVoiceActivityDetectionRequested,
                modelURL: isVoiceActivityDetectionRequested
                    ? voiceActivityDetectionModelURLProvider()
                    : nil
            )
            do {
                let result = try await gate.run {
                    try await context.transcribe(request, decodingProfile: decodingProfile, voiceActivityDetectionModelPath: voiceActivityDetectionModelPath)
                }
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
        model: ModelManifestModel,
        decodingProfile: LocalDecodingProfile
    ) async throws -> TranscriptionClientResult {
        let prepared = try await prepareTranscription(
            model: model,
            decodingProfile: decodingProfile
        )
        return try await prepared.transcribe(request)
    }

    func warmUp(
        model: ModelManifestModel,
        language: String,
        decodingProfile _: LocalDecodingProfile
    ) async throws {
        let context = try await loadContextIfNeeded(for: model)
        guard runtimeState.shouldWarmUp(modelId: model.id) else {
            return
        }

        try await executionGate.run { try await context.warmUp(language: language) }
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
        let modelPath = try validatedModelPath(for: model)
        let canonicalURL = URL(fileURLWithPath: modelPath).resolvingSymlinksInPath()
        let attributes = try FileManager.default.attributesOfItem(atPath: canonicalURL.path)
        let identity = "\(model.id)|\(canonicalURL.path)|\(model.sha256 ?? "")|\(attributes[.size] ?? "")|\(attributes[.modificationDate] ?? "")"
        while true {
            if let activeLoad {
                if activeLoad.identity == identity {
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
                    if activeLoad.identity == identity {
                        return loadedContext
                    }
                    try Task.checkCancellation()
                    continue
                } catch is CancellationError {
                    throw CancellationError()
                } catch WhisperCppModelLoadWaitError.loadChanged {
                    continue
                } catch {
                    if activeLoad.identity == identity {
                        throw error
                    }
                    try Task.checkCancellation()
                    continue
                }
            }

            if contextIdentity == identity, let context {
                return context
            }

            let generation = nextLoadGeneration()
            let contextLoader = contextLoader
            let gate = executionGate
            let loadTask = Task.detached(priority: .utility) {
                try await gate.run { try contextLoader(modelPath) }
            }
            activeLoad = WhisperCppActiveModelLoad(
                modelId: model.id,
                identity: identity,
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
            if !inactiveModelIDs.contains(modelId) {
                if contextIdentity != activeLoad.identity { runtimeState = WhisperCppRuntimeState() }
                context = loadedContext
                contextIdentity = activeLoad.identity
                runtimeState.markLoaded(modelId: modelId)
            }
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

    func releaseResources(except modelID: String?) async {
        if let loadedID = runtimeState.loadedModelId, loadedID != modelID {
            inactiveModelIDs.insert(loadedID)
            context = nil
            contextIdentity = nil
            runtimeState = WhisperCppRuntimeState()
        }
        if let loadingID = activeLoad?.modelId, loadingID != modelID { inactiveModelIDs.insert(loadingID) }
    }

    func releaseResourcesForDeletion(modelID: String) async -> Bool {
        guard owners[modelID, default: 0] == 0, activeLoad?.modelId != modelID else { return false }
        if runtimeState.loadedModelId == modelID {
            context = nil
            contextIdentity = nil
            runtimeState = WhisperCppRuntimeState()
        }
        return true
    }

    private func releaseOwner(_ modelID: String) {
        owners[modelID, default: 0] -= 1
        if owners[modelID] == 0 { owners[modelID] = nil }
    }

    private func nextLoadGeneration() -> UInt64 {
        loadGeneration &+= 1
        return loadGeneration
    }

    private func validatedModelPath(for model: ModelManifestModel) throws -> String {
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

}
