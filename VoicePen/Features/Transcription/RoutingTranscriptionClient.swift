import Foundation

protocol WhisperCppTranscribing {
    func transcribe(
        audioURL: URL,
        model: ModelManifestModel,
        glossaryPrompt: String,
        language: String,
        includeTimestamps: Bool
    ) async throws -> TranscriptionClientResult

    func warmUp(model: ModelManifestModel, language: String) async throws
}

extension WhisperCppTranscriptionClient: WhisperCppTranscribing {}

final class RoutingTranscriptionClient: TranscriptionClient, ModelWarmupClient {
    private let modelProvider: () -> ModelManifestModel
    private let whisperCppClient: WhisperCppTranscribing

    init(
        modelProvider: @escaping () -> ModelManifestModel,
        whisperCppClient: WhisperCppTranscribing
    ) {
        self.modelProvider = modelProvider
        self.whisperCppClient = whisperCppClient
    }

    func transcribe(
        audioURL: URL,
        glossaryPrompt: String,
        language: String,
        includeTimestamps: Bool
    ) async throws -> TranscriptionClientResult {
        let model = modelProvider()
        let modelMetadata = VoiceTranscriptionModelMetadata(model: model)

        switch model.backendKind {
        case .whisperCpp:
            let result = try await whisperCppClient.transcribe(
                audioURL: audioURL,
                model: model,
                glossaryPrompt: glossaryPrompt,
                language: language,
                includeTimestamps: includeTimestamps
            )
            return TranscriptionClientResult(
                text: result.text,
                segments: result.segments,
                modelMetadata: modelMetadata
            )
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }

    func warmUp(model: ModelManifestModel, language: String) async throws {
        switch model.backendKind {
        case .whisperCpp:
            try await whisperCppClient.warmUp(model: model, language: language)
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }
}
