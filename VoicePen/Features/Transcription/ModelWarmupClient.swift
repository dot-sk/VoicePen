import Foundation

protocol ModelWarmupClient: AnyObject {
    func warmUp(model: ModelManifestModel, language: String) async throws
}

enum ModelRuntimeState: Equatable {
    case notLoaded
    case warming(modelId: String)
    case ready(modelId: String)
    case failed(modelId: String, message: String)
}
