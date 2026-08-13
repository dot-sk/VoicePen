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

final class CoreAudioMicrophoneMeetingAudioSource: MeetingAudioSourceClient {
    let source = MeetingSourceKind.microphone

    private let tempDirectory: URL
    private let fileManager: FileManager
    private let audioFileIO: MeetingAudioFileIO
    private let microphoneCapture: CoreAudioMicrophoneCapturing
    private var currentStream: MeetingMicrophoneStream?
    private var currentSegmentStartOffset: TimeInterval = 0
    private var chunks: [MeetingAudioChunk] = []
    private var sourceStatus = MeetingSourceHealth.unavailable

    init(
        tempDirectory: URL,
        fileManager: FileManager = .default,
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO(),
        microphoneCapture: CoreAudioMicrophoneCapturing = CoreAudioMicrophoneCapture()
    ) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
        self.audioFileIO = audioFileIO
        self.microphoneCapture = microphoneCapture
    }

    var status: MeetingSourceHealth {
        currentStream?.hasFailed == true ? .failed : sourceStatus
    }

    var level: Double? {
        currentStream?.level
    }

    func start(at offset: TimeInterval) async throws {
        try prepareStartState()
        try startSegment(at: offset)
    }

    func stop(at offset: TimeInterval) async throws -> [MeetingAudioChunk] {
        if currentStream != nil {
            try finishSegment(at: offset, healthAfterStop: .unavailable)
        }
        let finishedChunks = chunks
        chunks = []
        return finishedChunks
    }

    func cancel() async throws {
        microphoneCapture.teardown()
        currentStream?.cancel()
        currentStream = nil
        chunks = []
        sourceStatus = .unavailable
    }

    private func prepareStartState() throws {
        guard currentStream == nil else { throw MeetingRecordingError.alreadyRecording }
        chunks = []
    }

    private func startSegment(at offset: TimeInterval) throws {
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try microphoneCapture.prepare()
        let inputFormat = microphoneCapture.inputFormat
        let outputFormat = try audioFileIO.processingFormat()
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            let captureFormat = ActiveChannelMonoMixer.makeFloatFormat(
                sampleRate: audioFileIO.sampleRate,
                channelCount: inputFormat.channelCount
            )
        else {
            throw MeetingRecordingError.captureFailed("Microphone input format is unavailable.")
        }

        let outputURL = tempDirectory.appendingPathComponent("voicepen-meeting-mic-\(UUID().uuidString).wav")
        let sink = try MeetingAudioBufferFileSink(
            source: source,
            outputURL: outputURL,
            format: outputFormat,
            audioFileIO: audioFileIO
        )
        let stream: MeetingMicrophoneStream
        do {
            stream = try MeetingMicrophoneStream(
                inputFormat: inputFormat,
                captureFormat: captureFormat,
                outputFormat: outputFormat,
                sink: sink
            )
        } catch {
            sink.cancel()
            throw error
        }

        currentStream = stream
        currentSegmentStartOffset = offset

        do {
            try microphoneCapture.start(onBuffer: { [stream] buffer in
                stream.process(buffer)
            })
            sourceStatus = .capturing
        } catch {
            let error = MeetingRecordingError.captureFailed("Microphone capture could not be started.")
            sourceStatus = .failed
            cleanupRecordingFailure()
            throw error
        }
    }

    private func finishSegment(at offset: TimeInterval, healthAfterStop: MeetingSourceHealth) throws {
        microphoneCapture.stop()
        guard let currentStream else { return }
        let currentSegmentStartOffset = currentSegmentStartOffset
        self.currentStream = nil

        do {
            if let chunk = try currentStream.finish(
                startOffset: currentSegmentStartOffset,
                endOffset: offset
            ) {
                chunks.append(chunk)
            }
            sourceStatus = healthAfterStop
        } catch {
            sourceStatus = .failed
            throw error
        }
    }

    private func cleanupRecordingFailure() {
        microphoneCapture.stop()
        currentStream?.cancel()
        currentStream = nil
        chunks = []
    }
}

nonisolated private final class MeetingMicrophoneStream: @unchecked Sendable {
    private let converter: PCMStreamConverter
    private let outputFormat: AVAudioFormat
    private let sink: MeetingAudioBufferFileSink

    init(
        inputFormat: AVAudioFormat,
        captureFormat: AVAudioFormat,
        outputFormat: AVAudioFormat,
        sink: MeetingAudioBufferFileSink
    ) throws {
        do {
            converter = try PCMStreamConverter(
                inputFormat: inputFormat,
                outputFormat: captureFormat
            )
        } catch {
            throw MeetingRecordingError.captureFailed("Microphone audio converter is unavailable.")
        }
        self.outputFormat = outputFormat
        self.sink = sink
    }

    var hasFailed: Bool {
        sink.hasFailed
    }

    var level: Double? {
        sink.level
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        guard !sink.hasFailed else { return }

        do {
            let captureBuffer = try converter.convert(buffer)
            guard captureBuffer.frameLength > 0,
                let outputBuffer = ActiveChannelMonoMixer.makeMonoBuffer(
                    from: captureBuffer,
                    outputFormat: outputFormat
                ),
                outputBuffer.frameLength > 0
            else {
                return
            }
            try sink.append(outputBuffer)
        } catch {
            sink.fail(
                error as? MeetingRecordingError
                    ?? MeetingRecordingError.captureFailed("Microphone audio could not be processed.")
            )
        }
    }

    func finish(startOffset: TimeInterval, endOffset: TimeInterval) throws -> MeetingAudioChunk? {
        return try sink.finish(startOffset: startOffset, endOffset: endOffset)
    }

    func cancel() {
        sink.cancel()
    }
}

final class CoreAudioSystemOutputSource: MeetingAudioSourceClient {
    let source = MeetingSourceKind.systemAudio

    private let tempDirectory: URL
    private let fileManager: FileManager
    private let settingsProvider: () -> MeetingSystemAudioSourceSettings
    private let processResolver: MeetingSystemAudioProcessResolving
    private let audioFileIO: MeetingAudioFileIO
    private let queue = DispatchQueue(label: "voicepen.meeting.system-audio")
    private let queueKey = DispatchSpecificKey<Void>()
    private var tap: AudioHardwareTap?
    private var aggregateDevice: AudioHardwareAggregateDevice?
    private var ioProcID: AudioDeviceIOProcID?
    private var currentSink: MeetingAudioBufferFileSink?
    private var currentSegmentStartOffset: TimeInterval = 0
    private var chunks: [MeetingAudioChunk] = []
    private var sourceStatus = MeetingSourceHealth.unavailable

    init(
        tempDirectory: URL,
        fileManager: FileManager = .default,
        settingsProvider: @escaping () -> MeetingSystemAudioSourceSettings = { .all },
        processResolver: MeetingSystemAudioProcessResolving = LiveMeetingSystemAudioProcessResolver(),
        audioFileIO: MeetingAudioFileIO = AVFoundationMeetingAudioFileIO()
    ) {
        self.tempDirectory = tempDirectory
        self.fileManager = fileManager
        self.settingsProvider = settingsProvider
        self.processResolver = processResolver
        self.audioFileIO = audioFileIO
        queue.setSpecific(key: queueKey, value: ())
    }

    var status: MeetingSourceHealth {
        if currentSink?.hasFailed == true {
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
        drainCallbackQueue()
        currentSink?.cancel()
        currentSink = nil
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
        let sink: MeetingAudioBufferFileSink
        do {
            sink = try MeetingAudioBufferFileSink(
                source: source,
                outputURL: outputURL,
                format: format,
                audioFileIO: audioFileIO
            )
        } catch {
            try? AudioHardwareSystem.shared.destroyAggregateDevice(aggregateDevice)
            try? AudioHardwareSystem.shared.destroyProcessTap(tap)
            throw error
        }
        var ioProcID: AudioDeviceIOProcID?
        let createStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDevice.id, queue) { _, inputData, _, _, _ in
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    bufferListNoCopy: inputData,
                    deallocator: nil
                ),
                buffer.frameLength > 0
            else {
                return
            }
            try? sink.append(buffer)
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
        currentSegmentStartOffset = offset
        sourceStatus = .capturing
    }

    private func makeTapDescription() throws -> CATapDescription {
        let plan = MeetingSystemAudioTapPlan.build(settings: settingsProvider())
        let processObjectIDs = meetingSystemAudioProcessObjectIDs(for: plan, resolver: processResolver)
        let description: CATapDescription
        switch plan.mode {
        case .all:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        case .selectedAppsOnly:
            description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        case .allExceptSelectedApps:
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: processObjectIDs)
        }

        description.name = "VoicePen Meeting System Audio"
        description.uuid = UUID()
        description.isPrivate = true
        return description
    }

    private func finishSegment(at offset: TimeInterval, healthAfterStop: MeetingSourceHealth) throws {
        guard let currentSink else { return }
        stopCoreAudioObjects()
        drainCallbackQueue()
        do {
            if let chunk = try currentSink.finish(
                startOffset: currentSegmentStartOffset,
                endOffset: offset
            ) {
                chunks.append(chunk)
            }
        } catch {
            sourceStatus = .failed
            self.currentSink = nil
            throw error
        }
        self.currentSink = nil
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

    private func drainCallbackQueue() {
        guard DispatchQueue.getSpecific(key: queueKey) == nil else { return }
        queue.sync {}
    }
}

nonisolated protocol MeetingSystemAudioProcessResolving: Sendable {
    func processObjectIDs(matchingBundleIdentifiers bundleIdentifiers: [String]) -> [AudioObjectID]
}

nonisolated struct LiveMeetingSystemAudioProcessResolver: MeetingSystemAudioProcessResolving {
    func processObjectIDs(matchingBundleIdentifiers bundleIdentifiers: [String]) -> [AudioObjectID] {
        let selectedBundleIdentifiers = normalizedBundleIdentifiers(bundleIdentifiers)
        guard !selectedBundleIdentifiers.isEmpty else { return [] }

        return processObjectIDs().filter { processObjectID in
            guard let bundleIdentifier = bundleIdentifier(forProcessObjectID: processObjectID) else {
                return false
            }
            return selectedBundleIdentifiers.contains { selectedBundleIdentifier in
                MeetingSystemAudioProcessBundleMatcher.matches(
                    bundleIdentifier,
                    selectedBundleIdentifier: selectedBundleIdentifier
                )
            }
        }
    }

    private func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var propertySize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &propertySize
            ) == noErr,
            propertySize >= UInt32(MemoryLayout<AudioObjectID>.size)
        else {
            return []
        }

        let count = Int(propertySize) / MemoryLayout<AudioObjectID>.size
        var processObjectIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        let status = processObjectIDs.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return noErr }
            return AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &propertySize,
                baseAddress
            )
        }

        guard status == noErr else { return [] }
        return processObjectIDs.filter { $0 != kAudioObjectUnknown }
    }

    private func bundleIdentifier(forProcessObjectID processObjectID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(processObjectID, &address) else { return nil }

        var bundleIdentifierReference: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            processObjectID,
            &address,
            0,
            nil,
            &propertySize,
            &bundleIdentifierReference
        )
        guard status == noErr, let bundleIdentifierReference else { return nil }

        let bundleIdentifier = bundleIdentifierReference.takeRetainedValue() as String
        let trimmedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedBundleIdentifier.isEmpty ? nil : trimmedBundleIdentifier
    }

    private func normalizedBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for bundleIdentifier in bundleIdentifiers {
            let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            normalized.append(trimmed)
        }
        return normalized
    }
}

nonisolated enum MeetingSystemAudioProcessBundleMatcher {
    static func matches(_ bundleIdentifier: String, selectedBundleIdentifier: String) -> Bool {
        let bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedBundleIdentifier = selectedBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleIdentifier.isEmpty, !selectedBundleIdentifier.isEmpty else { return false }
        return bundleIdentifier == selectedBundleIdentifier
            || bundleIdentifier.hasPrefix("\(selectedBundleIdentifier).")
    }
}

nonisolated func meetingSystemAudioProcessObjectIDs(
    for plan: MeetingSystemAudioTapPlan,
    resolver: MeetingSystemAudioProcessResolving
) -> [AudioObjectID] {
    guard plan.usesBundleIdentifierFilter else { return [] }

    var seen = Set<AudioObjectID>()
    var processObjectIDs: [AudioObjectID] = []
    for processObjectID in resolver.processObjectIDs(matchingBundleIdentifiers: plan.bundleIdentifiers) {
        guard processObjectID != kAudioObjectUnknown, seen.insert(processObjectID).inserted else { continue }
        processObjectIDs.append(processObjectID)
    }
    return processObjectIDs
}
