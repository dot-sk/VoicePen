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
        warmedModelId = modelId
    }
}

actor WhisperCppTranscriptionClient {
    private let paths: AppPaths
    private var runtimeState = WhisperCppRuntimeState()
    private var context: WhisperCppContext?

    init(paths: AppPaths) {
        self.paths = paths
    }

    func transcribe(
        audioURL: URL,
        model: ModelManifestModel,
        glossaryPrompt: String,
        language: String
    ) async throws -> String {
        let context = try await loadContextIfNeeded(for: model)
        do {
            let text = try await context.transcribe(
                audioURL: audioURL,
                prompt: glossaryPrompt,
                language: language
            )
            runtimeState.markWarmed(modelId: model.id)
            return text
        } catch TranscriptionError.emptyResult {
            runtimeState.markWarmed(modelId: model.id)
            throw TranscriptionError.emptyResult
        }
    }

    func warmUp(model: ModelManifestModel, language: String) async throws {
        guard runtimeState.shouldWarmUp(modelId: model.id) else {
            return
        }

        let context = try await loadContextIfNeeded(for: model)
        try await context.warmUp(language: language)
        runtimeState.markWarmed(modelId: model.id)
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

    private func loadContextIfNeeded(for model: ModelManifestModel) async throws -> WhisperCppContext {
        if runtimeState.loadedModelId == model.id, let context {
            return context
        }

        try validateAcceleration(for: model)

        let missingArtifactPaths = model.missingArtifactURLs(paths: paths).map(\.path)
        guard missingArtifactPaths.isEmpty else {
            throw TranscriptionError.modelMissing(expectedPaths: missingArtifactPaths)
        }

        guard let modelURL = paths.existingModelFile(
            for: model.id,
            fileName: model.localArtifactFileName
        ) else {
            throw TranscriptionError.modelMissing(expectedPaths: model.expectedArtifactURLs(paths: paths).map(\.path))
        }

        let context = try WhisperCppContext(modelPath: modelURL.path)
        runtimeState.markLoaded(modelId: model.id)
        self.context = context
        return context
    }

    private func validateAcceleration(for model: ModelManifestModel) throws {
        let status = ModelAccelerationStatus.inspect(model: model, paths: paths)
        guard status.isCoreMLReady else {
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
