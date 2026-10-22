import FluidAudio
import Foundation

public struct NemotronSpeakerTurn: Sendable {
    public let startSeconds: Double
    public let endSeconds: Double
    public let speakerIndex: Int
}

// FluidAudio exposes mutable Core ML backing arrays, used only on the owning actor
private final class LoadedModels: @unchecked Sendable {
    let value: Nemotron3Models
    init(_ value: Nemotron3Models) { self.value = value }
}

public actor NemotronOfflineContext {
    private let modelDirectory: URL
    private var models: LoadedModels?
    private var loading: Task<LoadedModels, Error>?
    private var generation = 0

    public init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    public func warmUp() async throws {
        _ = try await loadModels()
    }

    public func unload() {
        generation += 1
        loading?.cancel()
        loading = nil
        models = nil
    }

    public func diarize(samples: [Float]) async throws -> [NemotronSpeakerTurn] {
        let requestGeneration = generation
        let loaded = try await loadModels()
        try checkRequest(requestGeneration)
        let engine = Nemotron3Diarizer(config: .offline, models: loaded.value)
        var probabilities: [Float] = []
        var frameCount = 0
        for offset in stride(from: 0, to: samples.count, by: 1_600) {
            try checkRequest(requestGeneration)
            engine.appendAudio(Array(samples[offset..<min(offset + 1_600, samples.count)]))
            let chunks = try engine.processBufferedAudio()
            for chunk in chunks {
                probabilities.append(contentsOf: chunk.probabilities)
                frameCount += chunk.frameCount
            }
            if !chunks.isEmpty {
                await Task.yield()
            }
        }
        try checkRequest(requestGeneration)
        for chunk in try engine.finishStream() {
            probabilities.append(contentsOf: chunk.probabilities)
            frameCount += chunk.frameCount
        }
        try checkRequest(requestGeneration)
        return Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frameCount).map {
            NemotronSpeakerTurn(
                startSeconds: Double($0.startSeconds), endSeconds: Double($0.endSeconds),
                speakerIndex: $0.speakerIndex
            )
        }
    }

    private func checkRequest(_ requestGeneration: Int) throws {
        try Task.checkCancellation()
        guard generation == requestGeneration else { throw CancellationError() }
    }

    private func loadModels() async throws -> LoadedModels {
        try Task.checkCancellation()
        if let models { return models }
        let loadGeneration = generation
        let task: Task<LoadedModels, Error>
        if let loading {
            task = loading
        } else {
            let directory = modelDirectory
            task = Task.detached {
                let models = try await Nemotron3Models.load(
                    config: .offline, directory: directory, computeUnits: .all
                )
                return LoadedModels(models)
            }
            loading = task
        }
        do {
            let loaded = try await task.value
            guard generation == loadGeneration else { throw CancellationError() }
            models = loaded
            loading = nil
            try Task.checkCancellation()
            return loaded
        } catch {
            if generation == loadGeneration { loading = nil }
            throw error
        }
    }
}
