import Foundation

nonisolated struct VoiceTranscriptionModelMetadata: Codable, Equatable, Sendable {
    var modelId: String
    var displayName: String
    var backend: String
    var version: String

    static let unknown = VoiceTranscriptionModelMetadata(
        modelId: "Unknown",
        displayName: "Unknown",
        backend: "Unknown",
        version: "Unknown"
    )

    init(
        modelId: String,
        displayName: String,
        backend: String,
        version: String
    ) {
        self.modelId = modelId
        self.displayName = displayName
        self.backend = backend
        self.version = version
    }

    init(
        id: String,
        displayName: String,
        sourceKind: String,
        version: String
    ) {
        self.init(
            modelId: id,
            displayName: displayName,
            backend: sourceKind,
            version: version
        )
    }

    init(model: ModelManifestModel) {
        self.init(
            id: model.id,
            displayName: model.displayName,
            sourceKind: model.sourceKind,
            version: model.version
        )
    }
}
