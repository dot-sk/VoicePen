import FluidAudio
import Foundation

nonisolated enum FluidAudioModelInstallation {
    typealias ModelsExist = (URL, AsrModelVersion) -> Bool

    static func parakeetVersion(for model: ModelManifestModel) -> AsrModelVersion? {
        switch model.id {
        case "parakeet-tdt-0.6b-v3":
            return .v3
        case "parakeet-tdt-0.6b-v2":
            return .v2
        default:
            return nil
        }
    }

    static func installedDirectory(
        model: ModelManifestModel,
        paths: AppPaths,
        modelsExist: ModelsExist = { directory, version in
            AsrModels.modelsExist(at: directory, version: version)
        }
    ) -> URL? {
        guard paths.hasCompletedUserModelDownload(for: model.id),
            let version = parakeetVersion(for: model)
        else {
            return nil
        }

        let userDirectory = paths.userModelDirectory(for: model.id)
        return modelsExist(userDirectory, version) ? userDirectory : nil
    }

    static func isInstalled(
        model: ModelManifestModel,
        paths: AppPaths,
        modelsExist: ModelsExist = { directory, version in
            AsrModels.modelsExist(at: directory, version: version)
        }
    ) -> Bool {
        installedDirectory(model: model, paths: paths, modelsExist: modelsExist) != nil
    }
}
