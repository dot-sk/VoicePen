import Foundation

protocol WhisperCppTranscribing: Sendable {
    func prepareTranscription(
        model: ModelManifestModel
    ) async throws -> PreparedTranscription

    func transcribe(
        _ request: TranscriptionRequest,
        model: ModelManifestModel
    ) async throws -> TranscriptionClientResult

    func warmUp(
        model: ModelManifestModel,
        language: String
    ) async throws
}

extension WhisperCppTranscribing {
    func prepareTranscription(
        model: ModelManifestModel
    ) async throws -> PreparedTranscription {
        PreparedTranscription { request in
            try await self.transcribe(
                request,
                model: model
            )
        }
    }

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

    func prepareTranscription() async throws -> PreparedTranscription {
        let model = modelProvider()
        let modelMetadata = VoiceTranscriptionModelMetadata(model: model)

        switch model.backendKind {
        case .whisperCpp:
            let prepared = try await whisperCppClient.prepareTranscription(
                model: model
            )
            return PreparedTranscription { request in
                let result = try await prepared.transcribe(request)
                return TranscriptionClientResult(
                    text: result.text,
                    segments: result.segments,
                    modelMetadata: modelMetadata
                )
            }
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionClientResult {
        let prepared = try await prepareTranscription()
        return try await prepared.transcribe(request)
    }

    func warmUp(model: ModelManifestModel, language: String) async throws {
        switch model.backendKind {
        case .whisperCpp:
            try await whisperCppClient.warmUp(
                model: model,
                language: language
            )
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }
}
