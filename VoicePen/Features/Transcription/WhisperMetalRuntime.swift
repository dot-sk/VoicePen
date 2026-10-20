import Darwin
import Foundation
import Metal
import whisper

nonisolated final class WhisperMetalModelPath: @unchecked Sendable {
    let directory: URL
    let modelPath: String
    private let marker: Data

    init(modelPath: String, root: URL = FileManager.default.temporaryDirectory.appendingPathComponent("voicepen-whisper-metal", isDirectory: true)) throws {
        let canonical = URL(fileURLWithPath: modelPath).resolvingSymlinksInPath()
        guard ModelArtifactPresence.exists(at: canonical) else {
            throw TranscriptionError.modelLoadFailed("Whisper weights are missing. Reinstall the selected model and retry.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Self.cleanAbandonedDirectories(in: root)
        directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.modelPath = directory.appendingPathComponent("weights.bin").path
        marker = Data("voicepen-whisper-metal-v1:\(getpid())".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try marker.write(to: directory.appendingPathComponent(".owner"), options: .atomic)
            try FileManager.default.createSymbolicLink(at: URL(fileURLWithPath: self.modelPath), withDestinationURL: canonical)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw TranscriptionError.modelLoadFailed("Could not prepare isolated Whisper weights. Check temporary-directory permissions and retry. \(error.localizedDescription)")
        }
    }

    deinit {
        guard (try? Data(contentsOf: directory.appendingPathComponent(".owner"))) == marker else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    static func cleanAbandonedDirectories(in root: URL) {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) else { return }
        for child in children {
            guard let values = try? child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
                values.isSymbolicLink == false, values.isDirectory == true,
                let marker = try? String(contentsOf: child.appendingPathComponent(".owner"), encoding: .utf8),
                marker.hasPrefix("voicepen-whisper-metal-v1:"),
                let pid = Int32(marker.dropFirst("voicepen-whisper-metal-v1:".count)), pid > 0,
                kill(pid, 0) == -1, errno == ESRCH
            else { continue }
            try? manager.removeItem(at: child)
        }
    }
}

nonisolated struct WhisperMetalAcceleration: Equatable, Sendable {
    let encoder: String
    let decoder: String
    let device: String
}

nonisolated final class WhisperMetalDiagnosticsStore: @unchecked Sendable {
    static let shared = WhisperMetalDiagnosticsStore()
    private let lock = NSLock()
    private var contexts: [String: [UUID: WhisperMetalAcceleration]] = [:]

    func update(path: String, owner: UUID, acceleration: WhisperMetalAcceleration?) {
        lock.lock()
        defer { lock.unlock() }
        contexts[path, default: [:]][owner] = acceleration
        if contexts[path]?.isEmpty == true { contexts[path] = nil }
    }

    func snapshot(path: String) -> WhisperMetalAcceleration? {
        lock.lock()
        defer { lock.unlock() }
        return contexts[path]?.values.first
    }
}

nonisolated struct WhisperMetalInitializationSignals {
    private var metal = false
    private var encoder = false
    private var decoder = false
    private var failed = false
    private var device = "MTL0"

    mutating func consume(_ line: String) {
        if line.contains("whisper_backend_init_gpu: using MTL"), line.contains(" backend") { metal = true }
        if line.contains("compute buffer (encode)") { encoder = true }
        if line.contains("compute buffer (decode)") { decoder = true }
        if line.contains("ggml_metal_init: found device:") {
            device = line.components(separatedBy: "found device:").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "MTL0"
        }
        if line.contains("Core ML model loaded") || line.contains("no GPU found") || line.contains("falling back to CPU")
            || line.contains("failed to initialize") || line.contains("failed to load library") || line.contains("failed to compile")
        {
            failed = true
        }
    }

    func validated() throws -> WhisperMetalAcceleration {
        guard metal, encoder, decoder, !failed else {
            throw TranscriptionError.modelLoadFailed(
                "Whisper requires Metal for its encoder and decoder. Metal or the packaged kernels could not initialize. Restart VoicePen, check GPU availability, or reinstall the app and retry."
            )
        }
        return WhisperMetalAcceleration(encoder: "Metal", decoder: "Metal", device: device)
    }
}

nonisolated final class WhisperMetalInitializationObserver: @unchecked Sendable {
    static let shared = WhisperMetalInitializationObserver()
    private let initializationLock = NSLock()
    private let signalsLock = NSLock()
    private var signals: WhisperMetalInitializationSignals?

    func initialize(path: String, parameters: whisper_context_params) throws -> (OpaquePointer, WhisperMetalAcceleration) {
        initializationLock.lock()
        defer { initializationLock.unlock() }
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw TranscriptionError.modelLoadFailed("Whisper requires an available Metal GPU. Check GPU availability and retry.")
        }
        signalsLock.lock()
        signals = WhisperMetalInitializationSignals()
        signalsLock.unlock()
        whisper_log_set(
            { _, text, _ in
                guard let text else { return }
                WhisperMetalInitializationObserver.shared.consume(String(cString: text))
            }, nil)
        let context = whisper_init_from_file_with_params(path, parameters)
        signalsLock.lock()
        let observed = signals
        signals = nil
        signalsLock.unlock()
        guard let context else {
            throw TranscriptionError.modelLoadFailed(
                "Whisper could not initialize the selected weights and Metal kernels. Check the model installation, reinstall the app if its kernels are missing, and retry.")
        }
        do { return (context, try (observed ?? WhisperMetalInitializationSignals()).validated()) } catch {
            whisper_free(context)
            throw error
        }
    }

    private func consume(_ text: String) {
        signalsLock.lock()
        signals?.consume(text)
        signalsLock.unlock()
    }
}
