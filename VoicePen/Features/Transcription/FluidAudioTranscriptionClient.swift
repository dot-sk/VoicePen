import FluidAudio
import Foundation

actor FluidAudioTranscriptionClient {
    private let paths: AppPaths
    private var loadedModelId: String?
    private var asrManager: AsrManager?

    init(paths: AppPaths) {
        self.paths = paths
    }

    func transcribe(audioURL: URL, model: ModelManifestModel, language: String) async throws -> String {
        let manager = try await loadManagerIfNeeded(for: model)
        let decoderLayerCount = await manager.decoderLayerCount
        var decoderState = try TdtDecoderState(decoderLayers: decoderLayerCount)
        let result = try await manager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: fluidLanguage(for: language)
        )

        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyResult }
        return text
    }

    func warmUp(model: ModelManifestModel) async throws {
        _ = try await loadManagerIfNeeded(for: model)
    }

    private func loadManagerIfNeeded(for model: ModelManifestModel) async throws -> AsrManager {
        if loadedModelId == model.id, let asrManager {
            return asrManager
        }

        guard let modelDirectory = paths.existingModelDirectory(for: model.id) else {
            let expectedPaths = paths.expectedModelDirectories(for: model.id).map(\.path)
            AppLogger.error("Missing FluidAudio model. Expected paths: \(expectedPaths.joined(separator: ", "))")
            throw TranscriptionError.modelMissing(expectedPaths: expectedPaths)
        }

        do {
            let version = try parakeetVersion(for: model)
            let models = try await AsrModels.load(
                from: modelDirectory,
                version: version
            )
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            loadedModelId = model.id
            asrManager = manager
            return manager
        } catch let error as TranscriptionError {
            throw error
        } catch {
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    private func parakeetVersion(for model: ModelManifestModel) throws -> AsrModelVersion {
        switch model.id {
        case "parakeet-tdt-0.6b-v3":
            return .v3
        case "parakeet-tdt-0.6b-v2":
            return .v2
        default:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }

    private func fluidLanguage(for language: String) -> Language? {
        guard language != "auto" else { return nil }
        return Language(rawValue: language)
    }
}
