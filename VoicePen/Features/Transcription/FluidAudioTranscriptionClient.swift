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

        guard let modelDirectory = FluidAudioModelInstallation.installedDirectory(model: model, paths: paths) else {
            let expectedPaths = paths.expectedModelDirectories(for: model.id).map(\.path)
            AppLogger.error("Missing FluidAudio model. Expected paths: \(expectedPaths.joined(separator: ", "))")
            throw TranscriptionError.modelMissing(expectedPaths: expectedPaths)
        }

        do {
            guard let version = FluidAudioModelInstallation.parakeetVersion(for: model) else {
                throw TranscriptionError.unsupportedModel(model.id)
            }
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

    private func fluidLanguage(for language: String) -> Language? {
        guard language != "auto" else { return nil }
        return Language(rawValue: language)
    }
}
