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

    var isModelReady: Bool {
        model.isPresent
    }

    var isCoreMLReady: Bool {
        companionArtifacts.contains { artifact in
            artifact.id == "coreml-encoder" && artifact.isPresent
        }
    }

    var accelerationSummary: String {
        guard isModelReady else { return "Model missing" }
        switch backendKind {
        case .whisperCpp:
            return isCoreMLReady ? "Core ML ready" : "Acceleration missing"
        case .fluidAudio:
            return "Core ML ready"
        case .unsupported:
            return "Unknown"
        }
    }

    static func inspect(model: ModelManifestModel, paths: AppPaths, fileManager: FileManager = .default) -> ModelAccelerationStatus {
        guard model.backendKind == .whisperCpp else {
            let modelDirectory = paths.existingModelDirectory(for: model.id)
            let expectedModelDirectory = modelDirectory ?? paths.userModelDirectory(for: model.id)
            let isPresent: Bool
            if model.backendKind == .fluidAudio {
                isPresent = FluidAudioModelInstallation.installedDirectory(model: model, paths: paths) != nil
            } else {
                isPresent = modelDirectory.map { ModelArtifactPresence.exists(at: $0, fileManager: fileManager) } ?? false
            }
            return ModelAccelerationStatus(
                model: ModelArtifactStatus(
                    id: "model-directory",
                    displayName: model.backendKind == .fluidAudio ? "FluidAudio model" : "Model directory",
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
            displayName: "GGML model",
            expectedURL: expectedModelURL,
            isPresent: modelURL.map { ModelArtifactPresence.exists(at: $0, fileManager: fileManager) } ?? false
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
            backendKind: model.backendKind
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
