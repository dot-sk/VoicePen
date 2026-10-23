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
        guard manifest.schemaVersion >= 2 else {
            throw ModelManifestError.unsupportedSchemaVersion(manifest.schemaVersion)
        }

        guard !manifest.recommendedModel.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelManifestError.invalidRecommendedModel
        }

        guard !manifest.recommendedModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelManifestError.invalidRecommendedModel
        }

        for model in [manifest.recommendedModel] + manifest.compatibleModels {
            guard isAllowedAsset(model.remoteFile, model: model) else {
                throw ModelManifestError.invalidModelAsset(model.id)
            }
            for artifact in model.requiredCompanionArtifacts {
                guard isAllowedAsset(artifact.remoteFile, model: model) else {
                    throw ModelManifestError.invalidModelAsset("\(model.id)/\(artifact.id)")
                }
                if artifact.archiveKind == .zip,
                    artifact.archiveRoot?.isEmpty != false || artifact.resolvedRequiredPaths.isEmpty
                {
                    throw ModelManifestError.invalidModelAsset("\(model.id)/\(artifact.id)")
                }
            }
        }
    }

    private func isAllowedAsset(_ remoteFile: ModelAssetRemoteFile?, model: ModelManifestModel) -> Bool {
        guard let url = remoteFile?.url else { return false }
        if model.backendKind == .nemotron {
            let components = url.pathComponents
            guard url.scheme == "https", url.host == "huggingface.co", components.count > 6,
                components[1] == "FluidInference", components[2] == "nemotron-speech-streaming-en-0.6b-coreml",
                components[3] == "resolve", components[4].count == 40,
                components[4].allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                components[5] == "nemotron_coreml_2240ms",
                let mainURL = model.remoteFile?.url
            else { return false }
            return Array(components.prefix(6)) == Array(mainURL.pathComponents.prefix(6))
        }
        return url.scheme == "https"
            && url.host == "github.com"
            && url.path.contains("/releases/download/model-assets-")
    }
}

private enum ModelManifestError: LocalizedError {
    case missingManifest
    case unsupportedSchemaVersion(Int)
    case invalidRecommendedModel
    case invalidModelAsset(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "Bundled model manifest is missing."
        case .unsupportedSchemaVersion(let version):
            return "Unsupported model manifest schema version: \(version)."
        case .invalidRecommendedModel:
            return "Bundled model manifest has an invalid recommended model."
        case .invalidModelAsset(let id):
            return "Bundled model manifest has an invalid model asset: \(id)."
        }
    }
}
