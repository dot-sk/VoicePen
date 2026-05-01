import Foundation

final class RoutingTranscriptionClient: TranscriptionClient, ModelWarmupClient {
    private let modelProvider: () -> ModelManifestModel
    private let whisperCppClient: WhisperCppTranscriptionClient
    private let fluidAudioClient: FluidAudioTranscriptionClient

    init(
        modelProvider: @escaping () -> ModelManifestModel,
        whisperCppClient: WhisperCppTranscriptionClient,
        fluidAudioClient: FluidAudioTranscriptionClient
    ) {
        self.modelProvider = modelProvider
        self.whisperCppClient = whisperCppClient
        self.fluidAudioClient = fluidAudioClient
    }

    func transcribe(audioURL: URL, glossaryPrompt: String, language: String) async throws -> String {
        let model = modelProvider()

        switch model.backendKind {
        case .whisperCpp:
            return try await whisperCppClient.transcribe(
                audioURL: audioURL,
                model: model,
                glossaryPrompt: glossaryPrompt,
                language: language
            )
        case .fluidAudio:
            return try await fluidAudioClient.transcribe(
                audioURL: audioURL,
                model: model,
                language: language
            )
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }

    func warmUp(model: ModelManifestModel, language: String) async throws {
        switch model.backendKind {
        case .whisperCpp:
            try await whisperCppClient.warmUp(model: model, language: language)
        case .fluidAudio:
            try await fluidAudioClient.warmUp(model: model)
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }
}
