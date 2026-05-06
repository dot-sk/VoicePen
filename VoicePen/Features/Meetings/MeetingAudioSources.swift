@preconcurrency import AVFoundation
@preconcurrency import CoreAudio
import Foundation

protocol MeetingAudioSourceClient: AnyObject {
    var source: MeetingSourceKind { get }
    var status: MeetingSourceHealth { get }
    var level: Double? { get }

    func start(at offset: TimeInterval) async throws
    func stop(at offset: TimeInterval) async throws -> [MeetingAudioChunk]
    func cancel() async throws
}

final class CompositeMeetingRecordingClient: MeetingRecordingClient {
    private let microphoneSource: MeetingAudioSourceClient
    private let systemAudioSource: MeetingAudioSourceClient

    private var startedAt: Date?
    private var partial = false
    private var errorMessages: [String] = []

    init(
        microphoneSource: MeetingAudioSourceClient,
        systemAudioSource: MeetingAudioSourceClient
    ) {
        self.microphoneSource = microphoneSource
        self.systemAudioSource = systemAudioSource
    }

    var sourceStatus: MeetingSourceStatus {
        MeetingSourceStatus(
            microphone: microphoneSource.status,
            systemAudio: systemAudioSource.status,
            microphoneLevel: microphoneSource.level,
            systemAudioLevel: systemAudioSource.level
        )
    }

    func start() async throws {
        guard startedAt == nil else { throw MeetingRecordingError.alreadyRecording }

        startedAt = Date()
        partial = false
        errorMessages = []

        do {
            try await withTaskCancellationHandler {
                try await microphoneSource.start(at: 0)
                try Task.checkCancellation()
                try await systemAudioSource.start(at: 0)
                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor [weak self] in
                    await self?.cancelSourcesAfterStartFailure()
                }
            }
        } catch {
            await cancelSourcesAfterStartFailure()
            throw error
        }
    }

    func stop() async throws -> MeetingRecordingResult {
        guard let startedAt else { throw MeetingRecordingError.notRecording }
        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(startedAt))

        let microphoneChunks = await stopSource(microphoneSource, at: duration)
        let systemAudioChunks = await stopSource(systemAudioSource, at: duration)
        let chunks = microphoneChunks + systemAudioChunks
        let sourceFlags = MeetingSourceFlags(
            microphoneCaptured: !microphoneChunks.isEmpty,
            systemAudioCaptured: !systemAudioChunks.isEmpty,
            partial: partial || microphoneSource.status == .failed || systemAudioSource.status == .failed
        )
        let errorMessage = errorMessages.isEmpty ? nil : errorMessages.joined(separator: " ")
        cleanupState()

        guard !chunks.isEmpty else {
            throw MeetingRecordingError.noCapturedAudio
        }

        return MeetingRecordingResult(
            startedAt: startedAt,
            endedAt: endedAt,
            chunks: chunks,
            sourceFlags: sourceFlags,
            errorMessage: errorMessage,
            duration: duration
        )
    }

    func cancel() async throws {
        var firstError: Error?
        do {
            try await microphoneSource.cancel()
        } catch {
            firstError = error
        }
        do {
            try await systemAudioSource.cancel()
        } catch {
            firstError = firstError ?? error
        }
        cleanupState()
        if let firstError {
            throw firstError
        }
    }

    private func cancelSourcesAfterStartFailure() async {
        try? await microphoneSource.cancel()
        try? await systemAudioSource.cancel()
        cleanupState()
    }

    private func stopSource(_ source: MeetingAudioSourceClient, at offset: TimeInterval) async -> [MeetingAudioChunk] {
        do {
            return try await source.stop(at: offset)
        } catch {
            partial = true
            errorMessages.append(error.localizedDescription)
            return []
        }
    }

    private func cleanupState() {
        startedAt = nil
    }
}

final class AVFoundationMicrophoneMeetingAudioSource: MeetingAudioSourceClient {
    let source = MeetingSourceKind.microphone

    private let tempDirectory: URL
    private let fileManager: FileManager
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var currentSink: MeetingAudioBufferFileSink?
    private var currentSegmentStartOffset: TimeInterval = 0
    private var chunks: [MeetingAudioChunk] = []
    private var recordingError: Error?
    private var sourceStatus = MeetingSourceHealth.unavailable

    init(tempDirectory: URL, fileManager: FileManager = .default) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
    }

    var status: MeetingSourceHealth {
        sourceStatus
    }

    var level: Double? {
        currentSink?.level
    }

    func start(at offset: TimeInterval) async throws {
        guard engine == nil else { throw MeetingRecordingError.alreadyRecording }
        chunks = []
        recordingError = nil
        try startSegment(at: offset)
    }

    func stop(at offset: TimeInterval) async throws -> [MeetingAudioChunk] {
        if engine != nil {
            try finishSegment(at: offset, healthAfterStop: .unavailable)
        }
        let finishedChunks = chunks
        chunks = []
        return finishedChunks
    }

    func cancel() async throws {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        converter = nil
        targetFormat = nil
        currentSink?.cancel()
        currentSink = nil
        chunks = []
        sourceStatus = .unavailable
    }

    private func startSegment(at offset: TimeInterval) throws {
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw MeetingRecordingError.captureFailed("Microphone input format is unavailable.")
        }

        let outputURL = tempDirectory.appendingPathComponent("voicepen-meeting-mic-\(UUID().uuidString).wav")
        let sink = try MeetingAudioBufferFileSink(source: source, outputURL: outputURL, format: targetFormat)

        self.engine = engine
        self.converter = converter
        self.targetFormat = targetFormat
        currentSink = sink
        currentSegmentStartOffset = offset
        recordingError = nil

        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            sourceStatus = .capturing
        } catch {
            inputNode.removeTap(onBus: 0)
            self.engine = nil
            self.converter = nil
            self.targetFormat = nil
            currentSink = nil
            sourceStatus = .failed
            throw error
        }
    }

    private func finishSegment(at offset: TimeInterval, healthAfterStop: MeetingSourceHealth) throws {
        guard let engine, let currentSink else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        converter = nil
        targetFormat = nil

        if let recordingError {
            sourceStatus = .failed
            currentSink.cancel()
            self.currentSink = nil
            throw recordingError
        }

        if let chunk = try currentSink.finish(startOffset: currentSegmentStartOffset, endOffset: offset) {
            chunks.append(chunk)
        }
        self.currentSink = nil
        sourceStatus = healthAfterStop
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let converter,
            let targetFormat,
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: convertedFrameCapacity(
                    inputFrames: buffer.frameLength,
                    inputSampleRate: buffer.format.sampleRate,
                    outputSampleRate: targetFormat.sampleRate
                )
            )
        else {
            recordingError = MeetingRecordingError.captureFailed("Microphone audio could not be converted.")
            sourceStatus = .failed
            return
        }

        let inputProvider = MeetingAudioConverterInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.next(inputStatus: inputStatus)
        }

        guard conversionError == nil, status == .haveData || status == .inputRanDry else {
            recordingError = MeetingRecordingError.captureFailed("Microphone audio conversion failed.")
            sourceStatus = .failed
            return
        }

        guard outputBuffer.frameLength > 0 else { return }
        do {
            try currentSink?.append(outputBuffer)
        } catch {
            recordingError = error
            sourceStatus = .failed
        }
    }

    private func convertedFrameCapacity(
        inputFrames: AVAudioFrameCount,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) -> AVAudioFrameCount {
        guard inputSampleRate > 0, outputSampleRate > 0 else {
            return inputFrames
        }
        return AVAudioFrameCount((Double(inputFrames) * outputSampleRate / inputSampleRate).rounded(.up)) + 32
    }
}

final class CoreAudioSystemOutputSource: MeetingAudioSourceClient {
    let source = MeetingSourceKind.systemAudio

    private let tempDirectory: URL
    private let fileManager: FileManager
    private let settingsProvider: () -> MeetingSystemAudioSourceSettings
    private let queue = DispatchQueue(label: "voicepen.meeting.system-audio")
    private var tap: AudioHardwareTap?
    private var aggregateDevice: AudioHardwareAggregateDevice?
    private var ioProcID: AudioDeviceIOProcID?
    private var currentSink: MeetingAudioBufferFileSink?
    private var inputHandler: CoreAudioTapInputHandler?
    private var currentSegmentStartOffset: TimeInterval = 0
    private var chunks: [MeetingAudioChunk] = []
    private var sourceStatus = MeetingSourceHealth.unavailable

    init(
        tempDirectory: URL,
        fileManager: FileManager = .default,
        settingsProvider: @escaping () -> MeetingSystemAudioSourceSettings = { .all }
    ) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
        self.settingsProvider = settingsProvider
    }

    var status: MeetingSourceHealth {
        if inputHandler?.hasFailed == true {
            return .failed
        }
        return sourceStatus
    }

    var level: Double? {
        currentSink?.level
    }

    func start(at offset: TimeInterval) async throws {
        guard aggregateDevice == nil else { throw MeetingRecordingError.alreadyRecording }
        chunks = []
        try startSegment(at: offset)
    }

    func stop(at offset: TimeInterval) async throws -> [MeetingAudioChunk] {
        if aggregateDevice != nil {
            try finishSegment(at: offset, healthAfterStop: .unavailable)
        }
        let finishedChunks = chunks
        chunks = []
        return finishedChunks
    }

    func cancel() async throws {
        stopCoreAudioObjects()
        currentSink?.cancel()
        currentSink = nil
        inputHandler = nil
        chunks = []
        sourceStatus = .unavailable
    }

    private func startSegment(at offset: TimeInterval) throws {
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let description = try makeTapDescription()

        guard let tap = try AudioHardwareSystem.shared.makeProcessTap(description: description) else {
            throw MeetingRecordingError.systemAudioPermissionDenied
        }

        guard var streamDescription = try? tap.format,
            let format = AVAudioFormat(streamDescription: &streamDescription)
        else {
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            throw MeetingRecordingError.captureFailed("System audio tap format is unavailable.")
        }

        let aggregateDescription: [String: Any] = [
            "name": "VoicePen Meeting System Audio",
            "uid": "com.voicepen.meeting.system-audio.\(UUID().uuidString)",
            "private": true,
            "tapautostart": false,
            "taps": [["uid": try tap.uid]]
        ]
        guard let aggregateDevice = try AudioHardwareSystem.shared.makeAggregateDevice(description: aggregateDescription) else {
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            throw MeetingRecordingError.captureFailed("System audio aggregate device could not be created.")
        }

        let outputURL = tempDirectory.appendingPathComponent("voicepen-meeting-system-\(UUID().uuidString).caf")
        let sink = try MeetingAudioBufferFileSink(source: source, outputURL: outputURL, format: format)
        let inputHandler = CoreAudioTapInputHandler(sink: sink, format: format)
        var ioProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDevice.id, queue) { _, inputData, _, _, _ in
            inputHandler.append(inputData)
        }
        guard createStatus == noErr, let ioProcID else {
            sink.cancel()
            try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            throw MeetingRecordingError.captureFailed("System audio IO callback could not be created.")
        }

        let startStatus = AudioDeviceStart(aggregateDevice.id, ioProcID)
        guard startStatus == noErr else {
            sink.cancel()
            AudioDeviceDestroyIOProcID(aggregateDevice.id, ioProcID)
            try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            throw MeetingRecordingError.systemAudioPermissionDenied
        }

        self.tap = tap
        self.aggregateDevice = aggregateDevice
        self.ioProcID = ioProcID
        currentSink = sink
        self.inputHandler = inputHandler
        currentSegmentStartOffset = offset
        sourceStatus = .capturing
    }

    private func makeTapDescription() throws -> CATapDescription {
        let plan = MeetingSystemAudioTapPlan.build(settings: settingsProvider())
        let description: CATapDescription
        switch plan.mode {
        case .all:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        case .selectedAppsOnly:
            description = CATapDescription(stereoMixdownOfProcesses: [])
        case .allExceptSelectedApps:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        }

        if plan.usesBundleIdentifierFilter {
            guard #available(macOS 26.0, *) else {
                throw MeetingRecordingError.captureFailed(
                    "System audio app filtering requires macOS 26 or later."
                )
            }
            description.bundleIDs = plan.bundleIdentifiers
            description.isProcessRestoreEnabled = true
        }

        description.name = "VoicePen Meeting System Audio"
        description.uuid = UUID()
        description.isPrivate = true
        return description
    }

    private func finishSegment(at offset: TimeInterval, healthAfterStop: MeetingSourceHealth) throws {
        guard let currentSink else { return }
        stopCoreAudioObjects()
        if inputHandler?.hasFailed == true {
            sourceStatus = .failed
            currentSink.cancel()
            self.currentSink = nil
            inputHandler = nil
            throw MeetingRecordingError.captureFailed("System audio could not be written.")
        }
        if let chunk = try currentSink.finish(startOffset: currentSegmentStartOffset, endOffset: offset) {
            chunks.append(chunk)
        }
        self.currentSink = nil
        inputHandler = nil
        sourceStatus = healthAfterStop
    }

    private func stopCoreAudioObjects() {
        if let aggregateDevice, let ioProcID {
            AudioDeviceStop(aggregateDevice.id, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDevice.id, ioProcID)
        }
        if let aggregateDevice {
            try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
        }
        if let tap {
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
        }
        self.ioProcID = nil
        self.aggregateDevice = nil
        self.tap = nil
    }
}

nonisolated private final class CoreAudioTapInputHandler: @unchecked Sendable {
    private let sink: MeetingAudioBufferFileSink
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var failed = false

    init(sink: MeetingAudioBufferFileSink, format: AVAudioFormat) {
        self.sink = sink
        self.format = format
    }

    var hasFailed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }

    func append(_ inputData: UnsafePointer<AudioBufferList>?) {
        guard let inputData,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                bufferListNoCopy: inputData,
                deallocator: nil
            ),
            buffer.frameLength > 0
        else {
            return
        }

        do {
            try sink.append(buffer)
        } catch {
            lock.lock()
            failed = true
            lock.unlock()
        }
    }
}

nonisolated final class MeetingAudioBufferFileSink: @unchecked Sendable {
    let source: MeetingSourceKind
    let outputURL: URL

    private let lock = NSLock()
    private let audioFile: AVAudioFile
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter?
    private var didWriteSamples = false
    private var didFinish = false
    private var latestLevel: Double?

    init(source: MeetingSourceKind, outputURL: URL, format inputFormat: AVAudioFormat) throws {
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio output format is unavailable.")
        }

        self.source = source
        self.outputURL = outputURL
        self.outputFormat = outputFormat
        if inputFormat.isEquivalent(to: outputFormat) {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
                throw MeetingRecordingError.captureFailed("Meeting audio converter is unavailable.")
            }
            self.converter = converter
        }
        audioFile = try AVAudioFile(forWriting: outputURL, settings: outputFormat.settings)
    }

    var level: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestLevel
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        let outputBuffer = try writableBuffer(from: buffer)
        guard outputBuffer.frameLength > 0 else { return }
        try audioFile.write(from: outputBuffer)
        didWriteSamples = true
        latestLevel = normalizedLevel(from: outputBuffer)
    }

    func finish(startOffset: TimeInterval, endOffset: TimeInterval) throws -> MeetingAudioChunk? {
        lock.lock()
        didFinish = true
        let didWriteSamples = didWriteSamples
        lock.unlock()

        guard didWriteSamples,
            FileManager.default.fileExists(atPath: outputURL.path)
        else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        return MeetingAudioChunk(
            url: outputURL,
            source: source,
            startOffset: startOffset,
            duration: max(0, endOffset - startOffset)
        )
    }

    func cancel() {
        lock.lock()
        didFinish = true
        lock.unlock()
        try? FileManager.default.removeItem(at: outputURL)
    }

    private func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double? {
        guard let channelData = buffer.floatChannelData else { return nil }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else { return nil }

        var sum: Float = 0
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for frame in 0..<frameLength {
                sum += abs(samples[frame])
            }
        }

        return min(1, Double(sum / Float(frameLength * channelCount)) * 8)
    }

    private func writableBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard let converter else { return buffer }
        guard
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: convertedFrameCapacity(
                    inputFrames: buffer.frameLength,
                    inputSampleRate: buffer.format.sampleRate,
                    outputSampleRate: outputFormat.sampleRate
                )
            )
        else {
            throw MeetingRecordingError.captureFailed("Meeting audio output buffer is unavailable.")
        }

        let inputProvider = MeetingAudioConverterInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            inputProvider.next(inputStatus: inputStatus)
        }

        guard conversionError == nil, status == .haveData || status == .inputRanDry else {
            throw MeetingRecordingError.captureFailed("Meeting audio conversion failed.")
        }

        return outputBuffer
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

private extension AVAudioFormat {
    nonisolated func isEquivalent(to other: AVAudioFormat) -> Bool {
        commonFormat == other.commonFormat
            && sampleRate == other.sampleRate
            && channelCount == other.channelCount
            && isInterleaved == other.isInterleaved
    }
}

nonisolated private final class MeetingAudioConverterInputProvider: @unchecked Sendable {
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
