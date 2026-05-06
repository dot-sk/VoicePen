import Foundation

nonisolated struct VoiceTranscriptionModelMetadata: Codable, Equatable, Sendable {
    var modelId: String
    var displayName: String
    var backend: String
    var version: String
    var appVersion: String?

    static let unknown = VoiceTranscriptionModelMetadata(
        modelId: "Unknown",
        displayName: "Unknown",
        backend: "Unknown",
        version: "Unknown",
        appVersion: nil
    )

    init(
        modelId: String,
        displayName: String,
        backend: String,
        version: String,
        appVersion: String? = nil
    ) {
        self.modelId = modelId
        self.displayName = displayName
        self.backend = backend
        self.version = version
        self.appVersion = Self.normalizedAppVersion(appVersion)
    }

    init(
        id: String,
        displayName: String,
        sourceKind: String,
        version: String,
        appVersion: String? = nil
    ) {
        self.init(
            modelId: id,
            displayName: displayName,
            backend: sourceKind,
            version: version,
            appVersion: appVersion
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

    func withAppVersion(_ appVersion: String) -> VoiceTranscriptionModelMetadata {
        VoiceTranscriptionModelMetadata(
            modelId: modelId,
            displayName: displayName,
            backend: backend,
            version: version,
            appVersion: appVersion
        )
    }

    private static func normalizedAppVersion(_ appVersion: String?) -> String? {
        let trimmed = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
