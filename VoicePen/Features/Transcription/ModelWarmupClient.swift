import Foundation

@preconcurrency protocol ModelWarmupClient: AnyObject {
    func warmUp(model: ModelManifestModel, language: String) async throws
}

nonisolated enum ModelRuntimeState: Equatable, Sendable {
    case notLoaded
    case warming(modelId: String)
    case ready(modelId: String)
    case failed(modelId: String, message: String)
}
