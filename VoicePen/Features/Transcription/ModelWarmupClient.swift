import Foundation

nonisolated protocol ModelWarmupClient: AnyObject, Sendable {
    func warmUp(model: ModelManifestModel, language: String) async throws
    func releaseInactiveResources(selectedModelID: String?) async
    func releaseResourcesForDeletion(modelID: String) async -> Bool
}

extension ModelWarmupClient {
    func releaseInactiveResources(selectedModelID: String?) async {}
    func releaseResourcesForDeletion(modelID: String) async -> Bool { true }
}

nonisolated enum ModelRuntimeState: Equatable, Sendable {
    case notLoaded
    case warming(modelId: String)
    case ready(modelId: String)
    case failed(modelId: String, message: String)
}
