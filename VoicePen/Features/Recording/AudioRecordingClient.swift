import Foundation

protocol AudioRecordingClient: AnyObject {
    func startRecording() throws
    func stopRecording() throws -> RecordingResult?
}
