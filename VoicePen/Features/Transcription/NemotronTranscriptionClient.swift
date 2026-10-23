import Foundation
import VoicePenDiarization

nonisolated struct NemotronLoadedContext: Sendable {
    let id = UUID()
    let transcribe: @Sendable (URL) async throws -> TranscriptionClientResult
}

nonisolated enum NemotronRecognitionError: LocalizedError {
    case unsupportedOptions
    case incompatibleModel

    var errorDescription: String? {
        switch self {
        case .unsupportedOptions: "Nemotron English supports fixed English greedy RNNT and final text only."
        case .incompatibleModel: "The Nemotron installation does not match the packaged English runtime."
        }
    }
}

actor NemotronTranscriptionClient: WhisperCppTranscribing {
    nonisolated static let runtimePackageID = "fluidaudio-0.17.7-nemotron-english-2240ms"
    enum LoadEvent: Sendable { case joined }
    typealias ContextLoader = @Sendable (URL) async throws -> NemotronLoadedContext
    private struct Load {
        var waiters: [UUID: CheckedContinuation<NemotronLoadedContext, Error>] = [:]
    }

    private let paths: AppPaths
    private let gate: NativeExecutionGate
    private let contextLoader: ContextLoader
    private let loadEvent: @Sendable (LoadEvent) -> Void
    private var contexts: [String: NemotronLoadedContext] = [:]
    private var loads: [String: Load] = [:]
    private var owners: [String: Int] = [:]
    private var inactive: Set<String> = []

    init(
        paths: AppPaths, gate: NativeExecutionGate = NativeExecutionGate(),
        contextLoader: @escaping ContextLoader = { directory in
            let native = NemotronFileContext(directory: directory)
            try await native.warmUp()
            return NemotronLoadedContext { audioURL in
                let result = try await native.transcribe(audioURL: audioURL)
                return TranscriptionClientResult(text: result.text)
            }
        },
        loadEvent: @escaping @Sendable (LoadEvent) -> Void = { _ in }
    ) {
        self.paths = paths
        self.gate = gate
        self.contextLoader = contextLoader
        self.loadEvent = loadEvent
    }

    func prepareTranscription(model: ModelManifestModel, decodingProfile: LocalDecodingProfile) async throws -> PreparedTranscription {
        guard model.backendKind == .nemotron, model.runtimePackageID == Self.runtimePackageID,
            model.supportedLanguageCodes == ["en"], !model.supportsTimestamps
        else { throw NemotronRecognitionError.incompatibleModel }
        guard decodingProfile == .standard else { throw NemotronRecognitionError.unsupportedOptions }
        let key = identity(model)
        inactive.remove(key)
        let context = try await loadContext(model: model, key: key)
        try Task.checkCancellation()
        owners[key, default: 0] += 1
        let lease = NativeContextLease { [weak self] in Task { await self?.releaseOwner(key) } }
        let gate = gate
        return PreparedTranscription(capabilities: .nemotron) { [weak self] request in
            do {
                let result = try await gate.run {
                    try Task.checkCancellation()
                    return try await context.transcribe(request.audioURL)
                }
                try Task.checkCancellation()
                return withExtendedLifetime(lease) { result }
            } catch {
                if !(error is CancellationError), !Task.isCancelled {
                    await self?.discardContext(key, id: context.id)
                }
                throw error
            }
        }
    }

    func transcribe(_ request: TranscriptionRequest, model: ModelManifestModel, decodingProfile: LocalDecodingProfile) async throws -> TranscriptionClientResult {
        guard ["en", "auto"].contains(request.language), request.glossaryPrompt.isEmpty, request.options.isEmpty else {
            throw NemotronRecognitionError.unsupportedOptions
        }
        let prepared = try await prepareTranscription(model: model, decodingProfile: decodingProfile)
        return try await prepared.transcribe(request)
    }

    func warmUp(model: ModelManifestModel, language: String, decodingProfile: LocalDecodingProfile) async throws {
        guard language == "en" || language == "auto" else { throw NemotronRecognitionError.unsupportedOptions }
        _ = try await prepareTranscription(model: model, decodingProfile: decodingProfile)
    }

    func releaseResources(except modelID: String?) async {
        for key in Set(contexts.keys).union(loads.keys) where modelID.map({ key.hasPrefix("\($0)|") }) != true {
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

    private func identity(_ model: ModelManifestModel) -> String {
        "\(model.id)|\(model.version)|\(model.runtimePackageID ?? "")|\(model.downloadURL ?? "")|\(model.sha256 ?? "")"
    }

    private func loadContext(model: ModelManifestModel, key: String) async throws -> NemotronLoadedContext {
        if let context = contexts[key] { return context }
        guard model.isInstalled(paths: paths) else {
            throw TranscriptionError.modelMissing(expectedPaths: model.expectedArtifactURLs(paths: paths).map(\.path))
        }
        if loads[key] == nil {
            loads[key] = Load()
            let directory = paths.userModelDirectory(for: model.id)
            let loader = contextLoader
            let gate = gate
            Task { [self] in
                let result: Result<NemotronLoadedContext, Error>
                do { result = .success(try await gate.run { try await loader(directory) }) } catch { result = .failure(error) }
                finishLoad(key, result: result)
            }
        } else {
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

    private func finishLoad(_ key: String, result: Result<NemotronLoadedContext, Error>) {
        guard let load = loads.removeValue(forKey: key) else { return }
        if case let .success(context) = result, !inactive.contains(key) { contexts[key] = context }
        load.waiters.values.forEach { $0.resume(with: result) }
    }

    private func cancelWaiter(_ key: String, waiter: UUID) {
        loads[key]?.waiters.removeValue(forKey: waiter)?.resume(throwing: CancellationError())
    }

    private func releaseOwner(_ key: String) {
        owners[key, default: 0] -= 1
        if owners[key] == 0 { owners[key] = nil }
        if inactive.contains(key) { contexts[key] = nil }
    }

    private func discardContext(_ key: String, id: UUID) {
        guard contexts[key]?.id == id else { return }
        contexts[key] = nil
    }
}
