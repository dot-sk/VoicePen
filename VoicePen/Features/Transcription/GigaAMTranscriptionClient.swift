import Foundation

nonisolated enum GigaAMError: LocalizedError, Equatable, Sendable {
    case unsupportedOptions
    case incompatibleModel
    case nativeStatus(Int32)
    case metalUnavailable
    case packageUnavailable
    case invalidAudio
    case resourceExhausted
    case inputTooLong
    case incompleteOutput

    var errorDescription: String? {
        switch self {
        case .unsupportedOptions: "GigaAM supports automatic language, greedy CTC and optional Meeting timing."
        case .incompatibleModel: "GigaAM model metadata does not match the packaged runtime."
        case let .nativeStatus(status): "GigaAM failed with native status \(status)."
        case .metalUnavailable: "GigaAM requires its packaged Metal encoder."
        case .packageUnavailable: "The pinned GigaAM runtime package is unavailable."
        case .invalidAudio: "GigaAM requires finite 16 kHz mono audio."
        case .resourceExhausted: "GigaAM could not allocate enough memory for this recording."
        case .inputTooLong: "GigaAM cannot process the complete recording with this runtime."
        case .incompleteOutput: "GigaAM could not produce a complete transcript."
        }
    }
}

nonisolated final class NativeAbortToken: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false

    var isCanceled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceled
    }

    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
    }
}

nonisolated struct GigaAMLoadedContext: @unchecked Sendable {
    let id = UUID()
    let transcribe: @Sendable ([Float], NativeAbortToken, Bool) throws -> TranscriptionClientResult
}

nonisolated private final class GigaAMContextLease: @unchecked Sendable {
    let context: GigaAMLoadedContext
    private let release: @Sendable (GigaAMLoadedContext) -> Void
    init(context: GigaAMLoadedContext, release: @escaping @Sendable (GigaAMLoadedContext) -> Void) {
        self.context = context
        self.release = release
    }
    deinit { release(context) }
}

actor GigaAMTranscriptionClient: WhisperCppTranscribing {
    enum LoadEvent: Sendable { case started, joined, completed, failed, waiterCanceled }
    typealias ContextLoader = @Sendable (String, ModelManifestModel) throws -> GigaAMLoadedContext
    private struct Load {
        let generation: UUID
        var waiters: [UUID: CheckedContinuation<GigaAMLoadedContext, Error>]
    }

    private let paths: AppPaths
    private let contextLoader: ContextLoader
    private let readSamples: @Sendable (URL) throws -> [Float]
    private let gate: NativeExecutionGate
    nonisolated let diagnosticsStore: GigaAMDiagnosticsStore
    private let loadEvent: @Sendable (LoadEvent) -> Void
    private var contexts: [String: GigaAMLoadedContext] = [:]
    private var loads: [String: Load] = [:]
    private var owners: [String: Int] = [:]
    private var inactive = Set<String>()

    init(
        paths: AppPaths, gate: NativeExecutionGate = .shared,
        diagnosticsStore: GigaAMDiagnosticsStore = GigaAMDiagnosticsStore(),
        contextLoader: @escaping ContextLoader = { try GigaAMNativeContext.load(path: $0, model: $1) },
        loadEvent: @escaping @Sendable (LoadEvent) -> Void = { _ in },
        readSamples: @escaping @Sendable (URL) throws -> [Float] = {
            try AVFoundationMeetingAudioFileIO().readMonoSamples(from: $0, targetSampleRate: 16_000)
        }
    ) {
        self.paths = paths
        self.diagnosticsStore = diagnosticsStore
        self.gate = gate
        self.contextLoader = contextLoader
        self.readSamples = readSamples
        self.loadEvent = loadEvent
    }

    func prepareTranscription(model: ModelManifestModel, decodingProfile: LocalDecodingProfile) async throws -> PreparedTranscription {
        guard model.backendKind == .gigaAM, !model.supportsTimestamps else { throw GigaAMError.incompatibleModel }
        guard decodingProfile == .standard else { throw GigaAMError.unsupportedOptions }
        let key = identity(model)
        inactive.remove(key)
        let context = try await loadContext(model: model, key: key)
        try Task.checkCancellation()
        owners[key, default: 0] += 1
        let lease = GigaAMContextLease(context: context) { [weak self] releasedContext in
            Task { await self?.releaseOwner(key, context: releasedContext) }
        }
        let gate = gate
        let readSamples = readSamples
        let diagnosticsStore = diagnosticsStore
        // The lease keeps model memory alive until native execution has really returned.
        return PreparedTranscription(capabilities: .gigaAM) { [weak self] request in
            try Self.validate(request)
            let token = NativeAbortToken()
            return try await withTaskCancellationHandler {
                let ticket = try await gate.acquire()
                do {
                    try Task.checkCancellation()
                    let result = try await Task.detached(priority: .utility) {
                        if token.isCanceled { throw CancellationError() }
                        let samples = try readSamples(request.audioURL)
                        guard !samples.isEmpty, samples.count <= Int(Int32.max), samples.allSatisfy(\.isFinite) else { throw GigaAMError.invalidAudio }
                        return try lease.context.transcribe(samples, token, request.options.contains(.timestamps))
                    }.value
                    await gate.release(ticket)
                    try Task.checkCancellation()
                    if let diagnostics = result.executionDiagnostics { diagnosticsStore.update(modelID: model.id, diagnostics: diagnostics) }
                    return result
                } catch {
                    await gate.release(ticket)
                    if let nativeError = error as? GigaAMError {
                        switch nativeError {
                        case .metalUnavailable, .resourceExhausted, .nativeStatus:
                            await self?.discardContext(key, contextID: lease.context.id)
                        default: break
                        }
                    }
                    throw error
                }
            } onCancel: {
                token.cancel()
            }
        }
    }

    func transcribe(_ request: TranscriptionRequest, model: ModelManifestModel, decodingProfile: LocalDecodingProfile) async throws -> TranscriptionClientResult {
        try Self.validate(request)
        let prepared = try await prepareTranscription(model: model, decodingProfile: decodingProfile)
        return try await prepared.transcribe(request)
    }

    func warmUp(model: ModelManifestModel, language: String, decodingProfile: LocalDecodingProfile) async throws {
        guard language == "auto", decodingProfile == .standard else { throw GigaAMError.unsupportedOptions }
        _ = try await prepareTranscription(model: model, decodingProfile: decodingProfile)
    }

    func releaseResources(except modelID: String?) async {
        for key in Set(contexts.keys).union(loads.keys) where !key.hasPrefix("\(modelID ?? "")|") || modelID == nil {
            inactive.insert(key)
            contexts[key] = nil
        }
    }

    func releaseResourcesForDeletion(modelID: String) async -> Bool {
        let keys = Set(contexts.keys).union(loads.keys).union(owners.keys).filter { $0.hasPrefix("\(modelID)|") }
        guard keys.allSatisfy({ loads[$0] == nil && owners[$0, default: 0] == 0 }) else { return false }
        keys.forEach {
            contexts[$0] = nil
            inactive.insert($0)
        }
        return true
    }

    nonisolated private static func validate(_ request: TranscriptionRequest) throws {
        guard request.language == "auto", request.glossaryPrompt.isEmpty,
            request.options.subtracting([.timestamps]).isEmpty
        else { throw GigaAMError.unsupportedOptions }
    }

    private func identity(_ model: ModelManifestModel) -> String {
        "\(model.id)|\(model.version)|\(model.sha256 ?? "")|\(model.runtimePackageID ?? "")"
    }

    private func loadContext(model: ModelManifestModel, key: String) async throws -> GigaAMLoadedContext {
        try Task.checkCancellation()
        if let context = contexts[key] { return context }
        if loads[key] == nil {
            guard let modelURL = paths.existingModelFile(for: model.id, fileName: model.localArtifactFileName) else {
                throw TranscriptionError.modelMissing(expectedPaths: model.expectedArtifactURLs(paths: paths).map(\.path))
            }
            guard model.isInstalled(paths: paths) else { throw GigaAMError.incompatibleModel }
            let generation = UUID()
            loads[key] = Load(generation: generation, waiters: [:])
            loadEvent(.started)
            let loader = contextLoader
            let gate = gate
            AppLogger.info("GigaAM load started: model=\(model.id), package=\(model.runtimePackageID ?? "unknown")")
            Task { [self] in
                let result: Result<GigaAMLoadedContext, Error>
                do {
                    let ticket = try await gate.acquire()
                    let nativeResult = await Task.detached(priority: .utility) { try loader(modelURL.path, model) }.result
                    await gate.release(ticket)
                    result = nativeResult
                } catch { result = .failure(error) }
                finishLoad(key, generation: generation, result: result)
            }
        } else {
            AppLogger.info("GigaAM load joined: model=\(model.id)")
            loadEvent(.joined)
        }
        let waiter = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { loads[key]?.waiters[waiter] = $0 }
        } onCancel: {
            Task { await self.cancelWaiter(key, waiter: waiter) }
        }
    }

    private func finishLoad(_ key: String, generation: UUID, result: Result<GigaAMLoadedContext, Error>) {
        guard let load = loads[key], load.generation == generation else { return }
        loads[key] = nil
        if case let .success(context) = result, !inactive.contains(key) { contexts[key] = context }
        load.waiters.values.forEach { $0.resume(with: result) }
        switch result {
        case .success: loadEvent(.completed)
        case .failure: loadEvent(.failed)
        }
        AppLogger.info("GigaAM load finished: identity=\(key), succeeded=\((try? result.get()) != nil)")
    }

    private func cancelWaiter(_ key: String, waiter: UUID) {
        loads[key]?.waiters.removeValue(forKey: waiter)?.resume(throwing: CancellationError())
        loadEvent(.waiterCanceled)
    }

    private func releaseOwner(_ key: String, context: GigaAMLoadedContext) {
        owners[key, default: 0] -= 1
        if owners[key] == 0 { owners[key] = nil }
        if inactive.contains(key) { contexts[key] = nil }
        withExtendedLifetime(context) {}
    }

    private func discardContext(_ key: String, contextID: UUID) {
        guard contexts[key]?.id == contextID else { return }
        contexts[key] = nil
    }
}
