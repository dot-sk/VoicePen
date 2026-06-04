@preconcurrency import AVFoundation
import Foundation

final class LiveAudioRecordingClient: NSObject, AudioRecordingClient {
    private let tempDirectory: URL
    private let fileManager: FileManager
    private let microphoneVoiceProcessingEnabledProvider: () -> Bool
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var captureFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var currentURL: URL?
    private var startedAt: Date?
    private var recordingError: Error?
    private var latestVoiceBandLevel: Double?
    private let levelLock = NSLock()

    init(
        tempDirectory: URL,
        fileManager: FileManager = .default,
        microphoneVoiceProcessingEnabledProvider: @escaping () -> Bool = { true }
    ) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
        self.microphoneVoiceProcessingEnabledProvider = microphoneVoiceProcessingEnabledProvider
    }

    func startRecording() throws {
        guard engine == nil else { throw RecordingError.alreadyRecording }

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let url = tempDirectory.appendingPathComponent("voicepen-\(UUID().uuidString).wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        MicrophoneVoiceProcessingActivation.apply(
            isEnabled: microphoneVoiceProcessingEnabledProvider(),
            context: "dictation microphone capture"
        ) {
            try inputNode.setVoiceProcessingEnabled(true)
        }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecordingError.couldNotStart
        }

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let captureFormat = ActiveChannelMonoMixer.makeFloatFormat(
                sampleRate: 16_000,
                channelCount: inputFormat.channelCount
            ),
            let converter = AVAudioConverter(from: inputFormat, to: captureFormat)
        else {
            throw RecordingError.couldNotStart
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: outputFormat.settings)

        self.engine = engine
        self.audioFile = audioFile
        self.converter = converter
        self.captureFormat = captureFormat
        self.outputFormat = outputFormat
        currentURL = url
        startedAt = Date()
        recordingError = nil
        updateLatestVoiceBandLevel(nil)

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.engine = nil
            self.audioFile = nil
            self.converter = nil
            self.captureFormat = nil
            self.outputFormat = nil
            currentURL = nil
            startedAt = nil
            recordingError = nil
            updateLatestVoiceBandLevel(nil)
            throw error
        }
    }

    func stopRecording() throws -> RecordingResult? {
        guard let engine else { return nil }
        guard let startedAt, let currentURL else { throw RecordingError.missingOutputFile }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.audioFile = nil
        self.converter = nil
        self.captureFormat = nil
        self.outputFormat = nil
        self.currentURL = nil
        self.startedAt = nil
        updateLatestVoiceBandLevel(nil)

        if recordingError != nil {
            recordingError = nil
            throw RecordingError.audioWriteFailed
        }

        let endedAt = Date()
        guard fileManager.fileExists(atPath: currentURL.path) else {
            throw RecordingError.missingOutputFile
        }

        return RecordingResult(url: currentURL, startedAt: startedAt, endedAt: endedAt)
    }

    func currentLevel() -> Double? {
        levelLock.lock()
        defer { levelLock.unlock() }
        return latestVoiceBandLevel
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter,
            let captureFormat,
            let outputFormat,
            let captureBuffer = AVAudioPCMBuffer(
                pcmFormat: captureFormat,
                frameCapacity: convertedFrameCapacity(
                    inputFrames: buffer.frameLength,
                    inputSampleRate: buffer.format.sampleRate,
                    outputSampleRate: captureFormat.sampleRate
                )
            )
        else {
            recordingError = RecordingError.audioWriteFailed
            return
        }

        let inputProvider = AudioConverterInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: captureBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.next(inputStatus: inputStatus)
        }

        guard conversionError == nil else {
            recordingError = RecordingError.audioWriteFailed
            return
        }

        guard status == .haveData || status == .inputRanDry,
            captureBuffer.frameLength > 0,
            let outputBuffer = ActiveChannelMonoMixer.makeMonoBuffer(
                from: captureBuffer,
                outputFormat: outputFormat
            ),
            outputBuffer.frameLength > 0
        else {
            return
        }

        do {
            try audioFile?.write(from: outputBuffer)
        } catch {
            recordingError = error
        }

        let samples = ActiveChannelMonoMixer.monoSamples(from: outputBuffer)
        let level = VoiceBandAnalyzer.normalizedVoiceBandLevel(
            samples: samples,
            sampleRate: outputFormat.sampleRate
        )
        updateLatestVoiceBandLevel(level)
    }

    private func convertedFrameCapacity(
        inputFrames: AVAudioFrameCount,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) -> AVAudioFrameCount {
        guard inputSampleRate > 0, outputSampleRate > 0 else {
            return inputFrames
        }

        let ratio = outputSampleRate / inputSampleRate
        return AVAudioFrameCount((Double(inputFrames) * ratio).rounded(.up)) + 32
    }

    private func updateLatestVoiceBandLevel(_ level: Double?) {
        levelLock.lock()
        latestVoiceBandLevel = level
        levelLock.unlock()
    }
}

nonisolated private final class AudioConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !didProvideInput else {
            inputStatus.pointee = .noDataNow
            return nil
        }

        didProvideInput = true
        inputStatus.pointee = .haveData
        return buffer
    }
}
