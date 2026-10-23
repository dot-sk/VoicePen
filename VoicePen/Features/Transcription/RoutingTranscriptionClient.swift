import Foundation

nonisolated protocol WhisperCppTranscribing: Sendable {
    func releaseResources(except modelID: String?) async
    func releaseResourcesForDeletion(modelID: String) async -> Bool
    func prepareTranscription(
        model: ModelManifestModel,
        decodingProfile: LocalDecodingProfile
    ) async throws -> PreparedTranscription

    func transcribe(
        _ request: TranscriptionRequest,
        model: ModelManifestModel,
        decodingProfile: LocalDecodingProfile
    ) async throws -> TranscriptionClientResult

    func warmUp(
        model: ModelManifestModel,
        language: String,
        decodingProfile: LocalDecodingProfile
    ) async throws
}

extension WhisperCppTranscribing {
    func releaseResources(except modelID: String?) async {}
    func releaseResourcesForDeletion(modelID: String) async -> Bool { true }
    func prepareTranscription(
        model: ModelManifestModel,
        decodingProfile: LocalDecodingProfile
    ) async throws -> PreparedTranscription {
        PreparedTranscription { request in
            try await self.transcribe(
                request,
                model: model,
                decodingProfile: decodingProfile
            )
        }
    }

    func prepareTranscription(model: ModelManifestModel) async throws -> PreparedTranscription {
        try await prepareTranscription(model: model, decodingProfile: .standard)
    }

    func transcribe(
        _ request: TranscriptionRequest,
        model: ModelManifestModel
    ) async throws -> TranscriptionClientResult {
        try await transcribe(request, model: model, decodingProfile: .standard)
    }

    func warmUp(model: ModelManifestModel, language: String) async throws {
        try await warmUp(model: model, language: language, decodingProfile: .standard)
    }

}

extension WhisperCppTranscriptionClient: WhisperCppTranscribing {}

@MainActor
final class RoutingTranscriptionClient: TranscriptionClient, ModelWarmupClient {
    private let modelProvider: () -> ModelManifestModel
    private let decodingProfileProvider: () -> LocalDecodingProfile
    private let whisperCppClient: WhisperCppTranscribing
    private let gigaAMClient: WhisperCppTranscribing?
    private let nemotronClient: WhisperCppTranscribing?

    init(
        modelProvider: @escaping () -> ModelManifestModel,
        decodingProfileProvider: @escaping () -> LocalDecodingProfile = { .standard },
        whisperCppClient: WhisperCppTranscribing,
        gigaAMClient: WhisperCppTranscribing? = nil,
        nemotronClient: WhisperCppTranscribing? = nil
    ) {
        self.modelProvider = modelProvider
        self.decodingProfileProvider = decodingProfileProvider
        self.whisperCppClient = whisperCppClient
        self.gigaAMClient = gigaAMClient
        self.nemotronClient = nemotronClient
    }

    func prepareTranscription() async throws -> PreparedTranscription {
        let (model, savedProfile) = await MainActor.run {
            (modelProvider(), decodingProfileProvider())
        }
        let capabilities = RecognitionCapabilities(model: model)
        let decodingProfile = capabilities.effectiveProfile(savedProfile)
        let modelMetadata = VoiceTranscriptionModelMetadata(model: model)

        let backend: WhisperCppTranscribing
        switch model.backendKind {
        case .whisperCpp: backend = whisperCppClient
        case .gigaAM:
            guard let gigaAMClient else { throw TranscriptionError.unsupportedModel(model.id) }
            backend = gigaAMClient
        case .nemotron:
            guard let nemotronClient else { throw TranscriptionError.unsupportedModel(model.id) }
            backend = nemotronClient
        case .unsupported: throw TranscriptionError.unsupportedModel(model.id)
        }
        let prepared = try await backend.prepareTranscription(
            model: model,
            decodingProfile: decodingProfile
        )
        return PreparedTranscription(capabilities: capabilities) { request in
            let result = try await prepared.transcribe(request)
            return TranscriptionClientResult(
                text: result.text,
                segments: result.segments,
                modelMetadata: modelMetadata,
                executionDiagnostics: result.executionDiagnostics,
                confidence: result.confidence
            )
        }
    }

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionClientResult {
        let prepared = try await prepareTranscription()
        return try await prepared.transcribe(request)
    }

    func releaseInactiveResources(selectedModelID: String?) async {
        await whisperCppClient.releaseResources(except: selectedModelID)
        await gigaAMClient?.releaseResources(except: selectedModelID)
        await nemotronClient?.releaseResources(except: selectedModelID)
    }

    func releaseResourcesForDeletion(modelID: String) async -> Bool {
        guard await whisperCppClient.releaseResourcesForDeletion(modelID: modelID) else { return false }
        guard await gigaAMClient?.releaseResourcesForDeletion(modelID: modelID) ?? true else { return false }
        return await nemotronClient?.releaseResourcesForDeletion(modelID: modelID) ?? true
    }

    func warmUp(model: ModelManifestModel, language: String) async throws {
        switch model.backendKind {
        case .whisperCpp:
            try await whisperCppClient.warmUp(
                model: model,
                language: language,
                decodingProfile: .standard
            )
        case .gigaAM:
            guard let gigaAMClient else { throw TranscriptionError.unsupportedModel(model.id) }
            try await gigaAMClient.warmUp(model: model, language: "auto", decodingProfile: .standard)
        case .nemotron:
            guard let nemotronClient else { throw TranscriptionError.unsupportedModel(model.id) }
            try await nemotronClient.warmUp(model: model, language: "en", decodingProfile: .standard)
        case .unsupported:
            throw TranscriptionError.unsupportedModel(model.id)
        }
    }
}
