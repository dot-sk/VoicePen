import Foundation

nonisolated struct ModelManifest: Codable, Equatable {
    var schemaVersion: Int
    var recommendedModel: ModelManifestModel
    var compatibleModels: [ModelManifestModel]

    static let fallback = ModelManifest(
        schemaVersion: 1,
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
        downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin",
        artifactFileName: "ggml-large-v3-turbo-q5_0.bin",
        capabilities: ModelManifestModelCapabilities(timestamps: true),
        companionArtifacts: [
            ModelManifestArtifact(
                id: "coreml-encoder",
                displayName: "Core ML encoder",
                downloadURL: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip",
                fileName: "ggml-large-v3-turbo-encoder.mlmodelc.zip",
                localPath: "ggml-large-v3-turbo-encoder.mlmodelc",
                archiveKind: .zip
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
}

nonisolated enum ModelArtifactArchiveKind: String, Codable, Equatable {
    case none
    case zip
}

nonisolated enum ModelBackend: String, Equatable {
    case whisperCpp
    case unsupported
}
