import Foundation

protocol WhisperCppTranscribing: Sendable {
    func transcribe(
        _ request: TranscriptionRequest,
        model: ModelManifestModel
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

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionClientResult {
        let model = modelProvider()
        let modelMetadata = VoiceTranscriptionModelMetadata(model: model)

        switch model.backendKind {
        case .whisperCpp:
            let result = try await whisperCppClient.transcribe(request, model: model)
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
