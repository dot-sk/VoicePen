import Foundation

nonisolated struct ModelManifest: Codable, Equatable {
    var schemaVersion: Int
    var recommendedModel: ModelManifestModel
    var compatibleModels: [ModelManifestModel]

    static let fallback = ModelManifest(
        schemaVersion: 2,
        recommendedModel: .fallback,
        compatibleModels: [.fallback]
    )
}

nonisolated struct ModelManifestModel: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var version: String
    var sizeLabel: String
    var sourceRepo: String
    var sourceKind: String
    var backend: String
    var isQuantized: Bool
    var supportedLanguageCodes: [String]
    var description: String
    var downloadURL: String?
    var artifactFileName: String?
    var byteSize: Int64?
    var sha256: String?
    var capabilities: ModelManifestModelCapabilities?
    var companionArtifacts: [ModelManifestArtifact]?

    var backendKind: ModelBackend {
        ModelBackend(rawValue: backend) ?? .unsupported
    }

    var supportsTimestamps: Bool {
        switch backendKind {
        case .whisperCpp:
            return true
        case .unsupported:
            return capabilities?.timestamps ?? false
        }
    }

    func supports(language: String) -> Bool {
        supportedLanguageCodes.contains("multilingual")
            || supportedLanguageCodes.contains(language)
            || language == "auto"
    }

    var languageSupportLabel: String {
        let normalizedCodes = Set(supportedLanguageCodes.map { $0.lowercased() })
        if normalizedCodes.contains("multilingual") {
            return "Multilingual"
        }
        if normalizedCodes == ["en"] {
            return "English only"
        }
        return supportedLanguageCodes.map { $0.uppercased() }.sorted().joined(separator: ", ")
    }

    var localArtifactFileName: String {
        artifactFileName ?? "\(id).bin"
    }

    var requiredCompanionArtifacts: [ModelManifestArtifact] {
        companionArtifacts ?? []
    }

    var remoteFile: ModelAssetRemoteFile? {
        guard let downloadURL, let byteSize, let sha256 else {
            return nil
        }
        return ModelAssetRemoteFile(
            downloadURL: downloadURL,
            byteSize: byteSize,
            sha256: sha256
        )
    }

    func requiredUserArtifactURLs(paths: AppPaths) -> [URL] {
        let mainArtifactURL = paths.userModelFile(for: id, fileName: localArtifactFileName)
        let companionURLs = requiredCompanionArtifacts.map { artifact in
            paths.userModelArtifact(for: id, localPath: artifact.localPath)
        }
        return [mainArtifactURL] + companionURLs
    }

    func expectedArtifactURLs(paths: AppPaths) -> [URL] {
        paths.expectedModelFiles(for: id, fileName: localArtifactFileName)
            + requiredCompanionArtifacts.flatMap { artifact in
                paths.expectedModelArtifacts(for: id, localPath: artifact.localPath)
            }
    }

    func missingArtifactURLs(paths: AppPaths) -> [URL] {
        let mainModelMissing = paths.existingModelFile(for: id, fileName: localArtifactFileName) == nil
        let missingMainModelURLs =
            mainModelMissing
            ? paths.expectedModelFiles(for: id, fileName: localArtifactFileName)
            : []

        let missingCompanionURLs = requiredCompanionArtifacts.flatMap { artifact -> [URL] in
            guard paths.existingModelArtifact(for: id, localPath: artifact.localPath) == nil else {
                return []
            }
            return paths.expectedModelArtifacts(for: id, localPath: artifact.localPath)
        }

        return missingMainModelURLs + missingCompanionURLs
    }

    func isInstalled(paths: AppPaths) -> Bool {
        paths.existingModelFile(for: id, fileName: localArtifactFileName) != nil
            && requiredCompanionArtifacts.allSatisfy { artifact in
                paths.existingModelArtifact(for: id, localPath: artifact.localPath) != nil
            }
    }

    static let fallback = ModelManifestModel(
        id: VoicePenConfig.modelId,
        displayName: VoicePenConfig.modelDisplayName,
        version: VoicePenConfig.modelVersion,
        sizeLabel: VoicePenConfig.modelSizeLabel,
        sourceRepo: VoicePenConfig.modelSourceRepo,
        sourceKind: "whisper.cpp GGML",
        backend: "whisperCpp",
        isQuantized: true,
        supportedLanguageCodes: ["multilingual"],
        description: "Pinned fallback model used when the bundled manifest cannot be loaded.",
        downloadURL: "https://github.com/dot-sk/VoicePen/releases/download/model-assets-v1/ggml-large-v3-turbo-q5_0.bin",
        artifactFileName: "ggml-large-v3-turbo-q5_0.bin",
        byteSize: 574_041_195,
        sha256: "394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2",
        capabilities: ModelManifestModelCapabilities(timestamps: true),
        companionArtifacts: [
            ModelManifestArtifact(
                id: "coreml-encoder",
                displayName: "Core ML encoder",
                downloadURL: "https://github.com/dot-sk/VoicePen/releases/download/model-assets-v1/ggml-large-v3-turbo-encoder.mlmodelc.zip",
                fileName: "ggml-large-v3-turbo-encoder.mlmodelc.zip",
                localPath: "ggml-large-v3-turbo-encoder.mlmodelc",
                archiveKind: .zip,
                byteSize: 1_172_980_883,
                sha256: "1b62109a40668c7a989564c843411b9f638f0511f97f34ad2afa7367703dfda4",
                archiveRoot: "ggml-large-v3-turbo-encoder.mlmodelc",
                requiredPaths: [
                    "metadata.json",
                    "model.mil",
                    "weights/weight.bin"
                ]
            )
        ]
    )
}

nonisolated struct ModelManifestModelCapabilities: Codable, Equatable {
    var timestamps: Bool
}

nonisolated struct ModelManifestArtifact: Codable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var downloadURL: String
    var fileName: String
    var localPath: String
    var archiveKind: ModelArtifactArchiveKind
    var byteSize: Int64?
    var sha256: String?
    var archiveRoot: String?
    var requiredPaths: [String]?

    var remoteFile: ModelAssetRemoteFile? {
        guard let byteSize, let sha256 else {
            return nil
        }
        return ModelAssetRemoteFile(
            downloadURL: downloadURL,
            byteSize: byteSize,
            sha256: sha256
        )
    }

    var resolvedArchiveRoot: String {
        archiveRoot ?? localPath
    }

    var resolvedRequiredPaths: [String] {
        requiredPaths ?? []
    }
}

nonisolated enum ModelArtifactArchiveKind: String, Codable, Equatable {
    case none
    case zip
}

nonisolated enum ModelBackend: String, Equatable {
    case whisperCpp
    case unsupported
}
