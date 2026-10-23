import Foundation

nonisolated struct ModelArtifactStatus: Equatable, Identifiable {
    let id: String
    let displayName: String
    let expectedURL: URL?
    let isPresent: Bool
}

nonisolated struct ModelAccelerationStatus: Equatable {
    let model: ModelArtifactStatus
    let companionArtifacts: [ModelArtifactStatus]
    let backendKind: ModelBackend
    var installationIsCompatible = true
    var actualWhisperAcceleration: WhisperMetalAcceleration?

    var isModelReady: Bool {
        model.isPresent
    }

    var accelerationSummary: String {
        guard installationIsCompatible else { return "Incompatible installation" }
        guard isModelReady else { return "Model missing" }
        switch backendKind {
        case .gigaAM:
            return "Metal required"
        case .nemotron:
            return "Core ML (CPU + Neural Engine policy)"
        case .whisperCpp:
            return actualWhisperAcceleration.map { "Encoder: \($0.encoder), decoder: \($0.decoder), \($0.device)" } ?? "Metal required"
        case .unsupported:
            return "Unknown"
        }
    }

    static func inspect(model: ModelManifestModel, paths: AppPaths, fileManager: FileManager = .default) -> ModelAccelerationStatus {
        if model.backendKind == .nemotron {
            let present = model.isInstalled(paths: paths)
            return ModelAccelerationStatus(
                model: ModelArtifactStatus(id: model.id, displayName: "Core ML model", expectedURL: paths.userModelDirectory(for: model.id), isPresent: present),
                companionArtifacts: [],
                backendKind: .nemotron,
                installationIsCompatible: present || !FileManager.default.fileExists(atPath: paths.userModelCompletionMarker(for: model.id).path)
            )
        }
        guard model.backendKind == .whisperCpp || model.backendKind == .gigaAM else {
            let modelDirectory = paths.existingModelDirectory(for: model.id)
            let expectedModelDirectory = modelDirectory ?? paths.userModelDirectory(for: model.id)
            let isPresent = modelDirectory.map { ModelArtifactPresence.exists(at: $0, fileManager: fileManager) } ?? false
            return ModelAccelerationStatus(
                model: ModelArtifactStatus(
                    id: "model-directory",
                    displayName: "Model directory",
                    expectedURL: expectedModelDirectory,
                    isPresent: isPresent
                ),
                companionArtifacts: [],
                backendKind: model.backendKind
            )
        }

        let modelURL = paths.existingModelFile(for: model.id, fileName: model.localArtifactFileName)
        let expectedModelURL = modelURL ?? paths.userModelFile(for: model.id, fileName: model.localArtifactFileName)

        let modelStatus = ModelArtifactStatus(
            id: "model",
            displayName: model.backendKind == .gigaAM ? "GGUF model" : "GGML model",
            expectedURL: expectedModelURL,
            isPresent: model.backendKind == .gigaAM ? model.isInstalled(paths: paths) : modelURL.map { ModelArtifactPresence.exists(at: $0, fileManager: fileManager) } ?? false
        )

        let companionStatuses = model.requiredCompanionArtifacts.map { artifact in
            let artifactURL = paths.existingModelArtifact(for: model.id, localPath: artifact.localPath)
            let expectedArtifactURL = artifactURL ?? paths.userModelArtifact(for: model.id, localPath: artifact.localPath)
            return ModelArtifactStatus(
                id: artifact.id,
                displayName: artifact.displayName,
                expectedURL: expectedArtifactURL,
                isPresent: artifactURL.map { ModelArtifactPresence.exists(at: $0, fileManager: fileManager) } ?? false
            )
        }

        return ModelAccelerationStatus(
            model: modelStatus,
            companionArtifacts: companionStatuses,
            backendKind: model.backendKind,
            installationIsCompatible: model.backendKind != .gigaAM || modelURL == nil || model.isInstalled(paths: paths),
            actualWhisperAcceleration: model.backendKind == .whisperCpp
                ? modelURL.flatMap { WhisperMetalDiagnosticsStore.shared.snapshot(path: $0.resolvingSymlinksInPath().path) } : nil
        )
    }

}

nonisolated enum ModelArtifactPresence {
    static func exists(at url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        guard isDirectory.boolValue else {
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                let size = attributes[.size] as? NSNumber
            else {
                return false
            }
            return size.int64Value > 0
        }

        guard let contents = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return !contents.isEmpty
    }
}
