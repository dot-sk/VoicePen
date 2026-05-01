import Foundation

protocol AudioRecordingClient: AnyObject {
    func startRecording() throws
    func stopRecording() throws -> RecordingResult?
    func currentLevel() -> Double?
}

extension AudioRecordingClient {
    func currentLevel() -> Double? {
        nil
    }
}
