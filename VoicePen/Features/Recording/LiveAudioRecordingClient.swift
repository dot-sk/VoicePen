import AVFoundation
import Foundation

final class LiveAudioRecordingClient: NSObject, AudioRecordingClient {
    private let tempDirectory: URL
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var startedAt: Date?

    init(tempDirectory: URL, fileManager: FileManager = .default) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
    }

    func startRecording() throws {
        guard recorder == nil else { throw RecordingError.alreadyRecording }

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let url = tempDirectory.appendingPathComponent("voicepen-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecordingError.couldNotStart
        }

        self.recorder = recorder
        currentURL = url
        startedAt = Date()
    }

    func stopRecording() throws -> RecordingResult? {
        guard let recorder else { return nil }
        guard let startedAt, let currentURL else { throw RecordingError.missingOutputFile }

        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        self.startedAt = nil

        let endedAt = Date()
        guard fileManager.fileExists(atPath: currentURL.path) else {
            throw RecordingError.missingOutputFile
        }

        return RecordingResult(url: currentURL, startedAt: startedAt, endedAt: endedAt)
    }
}
