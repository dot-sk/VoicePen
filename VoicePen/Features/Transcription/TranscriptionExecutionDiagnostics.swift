import Foundation

nonisolated struct TranscriptionExecutionDiagnostics: Codable, Equatable, Sendable {
    let packageID: String
    let inputSampleCount: Int
    let nativeBackend: String
    let loadMilliseconds: Double
    let frontendMilliseconds: Double
    let encoderMilliseconds: Double
    let decodingMilliseconds: Double
    var inferenceMilliseconds: Double?
}

nonisolated final class GigaAMDiagnosticsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: (modelID: String, diagnostics: TranscriptionExecutionDiagnostics)?

    func update(modelID: String, diagnostics: TranscriptionExecutionDiagnostics) {
        lock.lock()
        latest = (modelID, diagnostics)
        lock.unlock()
    }

    func snapshot(modelID: String) -> TranscriptionExecutionDiagnostics? {
        lock.lock()
        defer { lock.unlock() }
        return latest?.modelID == modelID ? latest?.diagnostics : nil
    }
}
