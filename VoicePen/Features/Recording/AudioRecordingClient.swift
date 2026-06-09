import Foundation

nonisolated protocol AudioRecordingClient: AnyObject, Sendable {
    func prepareForRecording() async
    func invalidatePreparedRecording() async
    func startRecording() async throws
    func stopRecording() async throws -> RecordingResult?
    func currentLevel() -> Double?
}

extension AudioRecordingClient {
    func prepareForRecording() async {}

    func invalidatePreparedRecording() async {}

    func currentLevel() -> Double? {
        nil
    }
}
