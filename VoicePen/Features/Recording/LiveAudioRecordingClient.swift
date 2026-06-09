@preconcurrency import AVFoundation
import Foundation

nonisolated final class LiveAudioRecordingClient: NSObject, AudioRecordingClient, @unchecked Sendable {
    private let tempDirectory: URL
    private let fileManager: FileManager
    private let microphoneVoiceProcessingEnabledProvider: @MainActor () -> Bool
    private let workerQueue = DispatchQueue(label: "voicepen.live-audio-recording", qos: .userInitiated)
    private let recordingMeter = LiveRecordingMeter()
    private var preparedCapture: PreparedAudioCapture?
    private var session: LiveAudioRecordingSession?

    init(
        tempDirectory: URL,
        fileManager: FileManager = .default,
        microphoneVoiceProcessingEnabledProvider: @escaping @MainActor () -> Bool = { true }
    ) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
        self.microphoneVoiceProcessingEnabledProvider = microphoneVoiceProcessingEnabledProvider
    }

    func prepareForRecording() async {
        let microphoneVoiceProcessingEnabled = await microphoneVoiceProcessingEnabledProvider()
        do {
            try await performOnWorker { [self] in
                try prepareForRecordingOnWorker(microphoneVoiceProcessingEnabled: microphoneVoiceProcessingEnabled)
            }
        } catch {
            AppLogger.error("Failed to prepare dictation microphone capture: \(error.localizedDescription)")
        }
    }

    func invalidatePreparedRecording() async {
        await performOnWorker { [self] in
            invalidatePreparedRecordingOnWorker()
        }
    }

    func startRecording() async throws {
        let microphoneVoiceProcessingEnabled = await microphoneVoiceProcessingEnabledProvider()
        try await performOnWorker { [self] in
            try startRecordingOnWorker(microphoneVoiceProcessingEnabled: microphoneVoiceProcessingEnabled)
        }
    }

    func stopRecording() async throws -> RecordingResult? {
        try await performOnWorker { [self] in
            try stopRecordingOnWorker()
        }
    }

    func currentLevel() -> Double? {
        recordingMeter.currentLevel()
    }

    private func prepareForRecordingOnWorker(microphoneVoiceProcessingEnabled: Bool) throws {
        guard session == nil else { return }
        if let preparedCapture,
            preparedCapture.microphoneVoiceProcessingEnabled == microphoneVoiceProcessingEnabled
        {
            preparedCapture.engine.prepare()
            return
        }

        preparedCapture = try makePreparedCapture(microphoneVoiceProcessingEnabled: microphoneVoiceProcessingEnabled)
    }

    private func invalidatePreparedRecordingOnWorker() {
        guard session == nil else { return }
        preparedCapture?.stop()
        preparedCapture = nil
        recordingMeter.reset()
    }

    private func startRecordingOnWorker(microphoneVoiceProcessingEnabled: Bool) throws {
        guard session == nil else { throw RecordingError.alreadyRecording }
        if preparedCapture?.microphoneVoiceProcessingEnabled != microphoneVoiceProcessingEnabled {
            preparedCapture?.stop()
            preparedCapture = nil
        }
        if preparedCapture == nil {
            preparedCapture = try makePreparedCapture(microphoneVoiceProcessingEnabled: microphoneVoiceProcessingEnabled)
        }
        guard let preparedCapture else {
            throw RecordingError.couldNotStart
        }

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let url = tempDirectory.appendingPathComponent("voicepen-\(UUID().uuidString).wav")

        guard let converter = preparedCapture.makeConverter() else {
            throw RecordingError.couldNotStart
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: preparedCapture.outputFormat.settings)

        let session = LiveAudioRecordingSession(
            preparedCapture: preparedCapture,
            audioFile: audioFile,
            converter: converter,
            url: url,
            startedAt: Date(),
            fileManager: fileManager,
            recordingMeter: recordingMeter
        )
        self.session = session
        recordingMeter.reset()

        preparedCapture.inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(VoicePenConfig.recordingAudioTapBufferSize),
            format: preparedCapture.inputFormat
        ) { [session] buffer, _ in
            session.processInputBuffer(buffer)
        }

        do {
            try preparedCapture.engine.start()
        } catch {
            session.cancelAfterStartFailure()
            self.session = nil
            preparedCapture.stop()
            self.preparedCapture = nil
            recordingMeter.reset()
            throw error
        }
    }

    private func stopRecordingOnWorker() throws -> RecordingResult? {
        guard let session else { return nil }
        self.session = nil
        defer {
            recordingMeter.reset()
        }
        return try session.stop()
    }

    private func makePreparedCapture(microphoneVoiceProcessingEnabled: Bool) throws -> PreparedAudioCapture {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        MicrophoneVoiceProcessingActivation.apply(
            isEnabled: microphoneVoiceProcessingEnabled,
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
            )
        else {
            throw RecordingError.couldNotStart
        }

        engine.prepare()
        return PreparedAudioCapture(
            engine: engine,
            inputNode: inputNode,
            inputFormat: inputFormat,
            captureFormat: captureFormat,
            outputFormat: outputFormat,
            microphoneVoiceProcessingEnabled: microphoneVoiceProcessingEnabled
        )
    }

    private func performOnWorker(_ operation: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            workerQueue.async {
                operation()
                continuation.resume()
            }
        }
    }

    private func performOnWorker<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            workerQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

nonisolated private final class PreparedAudioCapture: @unchecked Sendable {
    let engine: AVAudioEngine
    let inputNode: AVAudioInputNode
    let inputFormat: AVAudioFormat
    let captureFormat: AVAudioFormat
    let outputFormat: AVAudioFormat
    let microphoneVoiceProcessingEnabled: Bool

    init(
        engine: AVAudioEngine,
        inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        captureFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        microphoneVoiceProcessingEnabled: Bool
    ) {
        self.engine = engine
        self.inputNode = inputNode
        self.inputFormat = inputFormat
        self.captureFormat = captureFormat
        self.outputFormat = outputFormat
        self.microphoneVoiceProcessingEnabled = microphoneVoiceProcessingEnabled
    }

    func makeConverter() -> AVAudioConverter? {
        AVAudioConverter(from: inputFormat, to: captureFormat)
    }

    func stop() {
        inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

nonisolated private final class LiveAudioRecordingSession: @unchecked Sendable {
    private let preparedCapture: PreparedAudioCapture
    private let audioFile: AVAudioFile
    private let converter: AVAudioConverter
    private let url: URL
    private let startedAt: Date
    private let fileManager: FileManager
    private let recordingMeter: LiveRecordingMeter
    private let lock = NSLock()
    private var recordingError: Error?
    private var didFinish = false

    init(
        preparedCapture: PreparedAudioCapture,
        audioFile: AVAudioFile,
        converter: AVAudioConverter,
        url: URL,
        startedAt: Date,
        fileManager: FileManager,
        recordingMeter: LiveRecordingMeter
    ) {
        self.preparedCapture = preparedCapture
        self.audioFile = audioFile
        self.converter = converter
        self.url = url
        self.startedAt = startedAt
        self.fileManager = fileManager
        self.recordingMeter = recordingMeter
    }

    func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let didFinish = didFinish
        lock.unlock()
        guard !didFinish else { return }

        recordingMeter.ingest(buffer)

        lock.lock()
        defer { lock.unlock() }
        guard !self.didFinish else { return }

        guard
            let captureBuffer = AVAudioPCMBuffer(
                pcmFormat: preparedCapture.captureFormat,
                frameCapacity: convertedFrameCapacity(
                    inputFrames: buffer.frameLength,
                    inputSampleRate: buffer.format.sampleRate,
                    outputSampleRate: preparedCapture.captureFormat.sampleRate
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
                outputFormat: preparedCapture.outputFormat
            ),
            outputBuffer.frameLength > 0
        else {
            return
        }

        do {
            try audioFile.write(from: outputBuffer)
        } catch {
            recordingError = error
        }
    }

    func stop() throws -> RecordingResult {
        preparedCapture.stop()

        lock.lock()
        didFinish = true
        let recordingError = recordingError
        lock.unlock()

        recordingMeter.reset()

        if recordingError != nil {
            throw RecordingError.audioWriteFailed
        }

        guard fileManager.fileExists(atPath: url.path) else {
            throw RecordingError.missingOutputFile
        }

        return RecordingResult(url: url, startedAt: startedAt, endedAt: Date())
    }

    func cancelAfterStartFailure() {
        preparedCapture.stop()
        lock.lock()
        didFinish = true
        recordingError = nil
        lock.unlock()
        recordingMeter.reset()
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
