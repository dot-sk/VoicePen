import Foundation

enum MicrophoneVoiceProcessingActivation {
    nonisolated static func apply(
        isEnabled: Bool,
        context: String,
        enable: () throws -> Void,
        log: (String) -> Void = { AppLogger.info($0) }
    ) {
        guard isEnabled else { return }

        do {
            try enable()
        } catch {
            log("System microphone voice processing skipped for \(context): \(error.localizedDescription)")
        }
    }
}
