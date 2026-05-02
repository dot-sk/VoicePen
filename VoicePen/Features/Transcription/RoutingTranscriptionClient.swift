import Foundation

protocol WhisperCppTranscribing {
    func transcribe(
        audioURL: URL,
        model: ModelManifestModel,
        glossaryPrompt: String,
        language: String
    ) async throws -> String

    func warmUp(model: ModelManifestModel, language: String) async throws
}

protocol FluidAudioTranscribing {
    func transcribe(audioURL: URL, model: ModelManifestModel, language: String) async throws -> String
    func warmUp(model: ModelManifestModel) async throws
}

extension WhisperCppTranscriptionClient: WhisperCppTranscribing {}
extension FluidAudioTranscriptionClient: FluidAudioTranscribing {}

final class RoutingTranscriptionClient: TranscriptionClient, ModelWarmupClient {
    private let modelProvider: () -> ModelManifestModel
    private let whisperCppClient: WhisperCppTranscribing
    private let fluidAudioClient: FluidAudioTranscribing

    init(
        modelProvider: @escaping () -> ModelManifestModel,
        whisperCppClient: WhisperCppTranscribing,
        fluidAudioClient: FluidAudioTranscribing
    ) {
        self.modelProvider = modelProvider
        self.whisperCppClient = whisperCppClient
        self.fluidAudioClient = fluidAudioClient
    }

    func transcribe(audioURL: URL, glossaryPrompt: String, language: String) async throws -> TranscriptionClientResult {
        let model = modelProvider()
        let modelMetadata = VoiceTranscriptionModelMetadata(model: model)

        switch model.backendKind {
        case .whisperCpp:
            let text = try await whisperCppClient.transcribe(
                audioURL: audioURL,
                model: model,
                glossaryPrompt: glossaryPrompt,
                language: language
            )
            return TranscriptionClientResult(text: text, modelMetadata: modelMetadata)
        case .fluidAudio:
            let text = try await fluidAudioClient.transcribe(
                audioURL: audioURL,
                model: model,
                language: language
            )
            return TranscriptionClientResult(text: text, modelMetadata: modelMetadata)
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
