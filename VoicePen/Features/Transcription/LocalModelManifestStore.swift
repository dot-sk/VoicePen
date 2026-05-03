import Foundation

final class LocalModelManifestStore {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func loadManifestOrDefault() -> ModelManifest {
        do {
            return try loadManifest()
        } catch {
            AppLogger.error("Failed to load model manifest: \(error.localizedDescription)")
            return .fallback
        }
    }

    func loadManifest() throws -> ModelManifest {
        guard let url = manifestURL() else {
            throw ModelManifestError.missingManifest
        }

        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(ModelManifest.self, from: data)
        try validate(manifest)
        return manifest
    }

    private func manifestURL() -> URL? {
        bundle.url(forResource: "model-manifest", withExtension: "json")
            ?? bundle.url(
                forResource: "model-manifest",
                withExtension: "json",
                subdirectory: "Resources"
            )
    }

    private func validate(_ manifest: ModelManifest) throws {
        guard manifest.schemaVersion >= 1 else {
            throw ModelManifestError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        guard !manifest.recommendedModel.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelManifestError.invalidRecommendedModel
        }

        guard !manifest.recommendedModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelManifestError.invalidRecommendedModel
        }
    }
}

private enum ModelManifestError: LocalizedError {
    case missingManifest
    case unsupportedSchemaVersion(Int)
    case invalidRecommendedModel

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Bundled model manifest is missing."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported model manifest schema version: \(version)."
        case .invalidRecommendedModel:
            return "Bundled model manifest has an invalid recommended model."
        }
    }
}
