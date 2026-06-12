@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

nonisolated protocol CoreAudioMicrophoneCapturing: AnyObject, Sendable {
    var inputFormat: AVAudioFormat { get }
    var isPrepared: Bool { get }
    func prepare() throws
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws
    func stop()
    func teardown()
}

nonisolated enum CoreAudioMicrophoneCaptureError: LocalizedError, Equatable {
    case missingDefaultInputDevice
    case couldNotCreateComponent
    case componentInstance
    case invalidInputFormat
    case failedToEnableInput
    case failedToDisableOutput
    case failedToSetCurrentDevice
    case failedToSetInputFormat
    case failedToConfigureCallback
    case initializeFailed(OSStatus)
    case startFailed(OSStatus)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .missingDefaultInputDevice:
            return "No default input device is available for microphone capture."
        case .couldNotCreateComponent:
            return "Failed to create HAL Audio Unit component."
        case .componentInstance:
            return "Failed to create HAL Audio Unit instance."
        case .invalidInputFormat:
            return "Default input format is unavailable."
        case .failedToEnableInput:
            return "Failed to enable HAL input."
        case .failedToDisableOutput:
            return "Failed to disable HAL output bus."
        case .failedToSetCurrentDevice:
            return "Failed to select default input device for HAL capture."
        case .failedToSetInputFormat:
            return "Failed to configure HAL input format."
        case .failedToConfigureCallback:
            return "Failed to configure HAL input callback."
        case let .initializeFailed(status):
            return "Failed to initialize HAL microphone unit: OSStatus(\(status))."
        case let .startFailed(status):
            return "Failed to start HAL microphone unit: OSStatus(\(status))."
        case .unsupportedFormat:
            return "Audio unit input format is unsupported."
        }
    }
}

protocol CoreAudioMicrophoneComponentFinding: Sendable {
    nonisolated func findHALOutputComponent() -> AudioComponent?
}

nonisolated protocol CoreAudioMicrophoneAudioUnitManaging: Sendable {
    func makeInstance(component: AudioComponent) -> (status: OSStatus, unit: AudioUnit?)
    func setProperty(
        unit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        data: UnsafeRawPointer,
        dataSize: UInt32
    ) -> OSStatus
    func getProperty(
        unit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        data: UnsafeMutableRawPointer,
        dataSize: UnsafeMutablePointer<UInt32>
    ) -> OSStatus
    func initialize(unit: AudioUnit) -> OSStatus
    func uninitialize(unit: AudioUnit)
    func dispose(unit: AudioUnit)
    func start(unit: AudioUnit) -> OSStatus
    func stop(unit: AudioUnit)
    func renderInput(
        unit: AudioUnit,
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32,
        data: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus
}

struct DefaultCoreAudioMicrophoneComponentFinder: CoreAudioMicrophoneComponentFinding {
    nonisolated func findHALOutputComponent() -> AudioComponent? {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AudioComponentFindNext(nil, &description)
    }
}

struct LiveCoreAudioMicrophoneAudioUnitManager: CoreAudioMicrophoneAudioUnitManaging {
    func makeInstance(component: AudioComponent) -> (status: OSStatus, unit: AudioUnit?) {
        var unit: AudioUnit?
        let status = AudioComponentInstanceNew(component, &unit)
        return (status, unit)
    }

    func setProperty(
        unit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        data: UnsafeRawPointer,
        dataSize: UInt32
    ) -> OSStatus {
        AudioUnitSetProperty(unit, propertyID, scope, element, data, dataSize)
    }

    func getProperty(
        unit: AudioUnit,
        propertyID: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        data: UnsafeMutableRawPointer,
        dataSize: UnsafeMutablePointer<UInt32>
    ) -> OSStatus {
        AudioUnitGetProperty(unit, propertyID, scope, element, data, dataSize)
    }

    func initialize(unit: AudioUnit) -> OSStatus {
        AudioUnitInitialize(unit)
    }

    func uninitialize(unit: AudioUnit) {
        AudioUnitUninitialize(unit)
    }

    func dispose(unit: AudioUnit) {
        AudioComponentInstanceDispose(unit)
    }

    func start(unit: AudioUnit) -> OSStatus {
        AudioOutputUnitStart(unit)
    }

    func stop(unit: AudioUnit) {
        AudioOutputUnitStop(unit)
    }

    func renderInput(
        unit: AudioUnit,
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        busNumber: UInt32,
        frameCount: UInt32,
        data: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        AudioUnitRender(unit, actionFlags, timeStamp, busNumber, frameCount, data)
    }
}

nonisolated final class CoreAudioMicrophoneCapture: CoreAudioMicrophoneCapturing, @unchecked Sendable {
    private struct State {
        let inputFormat: AVAudioFormat
        let callback: @Sendable (AVAudioPCMBuffer) -> Void
    }

    private let callbackQueue: DispatchQueue
    private let defaultInputDeviceProvider: DefaultAudioInputDeviceProviding
    private let componentFinder: CoreAudioMicrophoneComponentFinding
    private let audioUnitManager: CoreAudioMicrophoneAudioUnitManaging
    private let lock = NSLock()
    private var unit: AudioUnit?
    private var isPreparedValue = false
    private var isCapturing = false
    private var state: State?

    private let fallbackInputFormat: AVAudioFormat
    private(set) var inputFormat: AVAudioFormat

    init(
        defaultInputDeviceProvider: DefaultAudioInputDeviceProviding = CoreAudioDefaultInputDeviceProvider(),
        componentFinder: CoreAudioMicrophoneComponentFinding = DefaultCoreAudioMicrophoneComponentFinder(),
        audioUnitManager: CoreAudioMicrophoneAudioUnitManaging = LiveCoreAudioMicrophoneAudioUnitManager(),
        callbackQueue: DispatchQueue = DispatchQueue(label: "voicepen.core-audio-microphone-capture")
    ) {
        self.defaultInputDeviceProvider = defaultInputDeviceProvider
        self.componentFinder = componentFinder
        self.audioUnitManager = audioUnitManager
        self.callbackQueue = callbackQueue
        self.fallbackInputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        self.inputFormat = fallbackInputFormat
    }

    var isPrepared: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPreparedValue
    }

    func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        if isPreparedValue {
            return
        }

        let inputDeviceID = try resolveDefaultInputDeviceID()
        guard let component = componentFinder.findHALOutputComponent() else {
            throw CoreAudioMicrophoneCaptureError.couldNotCreateComponent
        }

        let instance = audioUnitManager.makeInstance(component: component)
        guard instance.status == noErr, let unit = instance.unit else {
            throw CoreAudioMicrophoneCaptureError.componentInstance
        }

        do {
            try enableInput(on: unit)
            try disableOutput(on: unit)
            try setCurrentInputDevice(unit: unit, inputDeviceID)
            let defaultFormat = try resolveInputFormat(on: unit)
            let inputFormat = try configureInputFormat(on: unit, defaultFormat: defaultFormat)

            let initialized = audioUnitManager.initialize(unit: unit)
            guard initialized == noErr else {
                throw CoreAudioMicrophoneCaptureError.initializeFailed(initialized)
            }

            self.unit = unit
            self.inputFormat = inputFormat
            self.state = nil
            self.isPreparedValue = true
        } catch {
            audioUnitManager.dispose(unit: unit)
            throw error
        }
    }

    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard isPreparedValue else {
            throw CoreAudioMicrophoneCaptureError.invalidInputFormat
        }
        guard !isCapturing else { return }
        guard let unit else {
            throw CoreAudioMicrophoneCaptureError.componentInstance
        }

        state = State(inputFormat: inputFormat, callback: onBuffer)

        var callbackStruct = AURenderCallbackStruct(
            inputProc: Self.micRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        let callbackSize = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        let setCallbackStatus = audioUnitManager.setProperty(
            unit: unit,
            propertyID: kAudioOutputUnitProperty_SetInputCallback,
            scope: kAudioUnitScope_Global,
            element: 0,
            data: &callbackStruct,
            dataSize: callbackSize
        )
        guard setCallbackStatus == noErr else {
            state = nil
            throw CoreAudioMicrophoneCaptureError.failedToConfigureCallback
        }

        let startStatus = audioUnitManager.start(unit: unit)
        guard startStatus == noErr else {
            clearCallback(on: unit)
            state = nil
            throw CoreAudioMicrophoneCaptureError.startFailed(startStatus)
        }

        isCapturing = true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isPreparedValue, isCapturing, let unit else {
            return
        }

        audioUnitManager.stop(unit: unit)
        clearCallback(on: unit)
        isCapturing = false
        state = nil
    }

    func teardown() {
        stop()
        lock.lock()
        let unitToDispose = unit
        unit = nil
        isPreparedValue = false
        isCapturing = false
        inputFormat = fallbackInputFormat
        state = nil
        lock.unlock()

        if let unitToDispose {
            audioUnitManager.uninitialize(unit: unitToDispose)
            audioUnitManager.dispose(unit: unitToDispose)
        }
    }

    private func clearCallback(on unit: AudioUnit) {
        var callbackStruct = AURenderCallbackStruct()
        let callbackSize = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        _ = audioUnitManager.setProperty(
            unit: unit,
            propertyID: kAudioOutputUnitProperty_SetInputCallback,
            scope: kAudioUnitScope_Global,
            element: 0,
            data: &callbackStruct,
            dataSize: callbackSize
        )
    }

    private func resolveDefaultInputDeviceID() throws -> AudioDeviceID {
        let device = defaultInputDeviceProvider.currentDefaultInputDevice().id
        guard device != kAudioObjectUnknown else {
            throw CoreAudioMicrophoneCaptureError.missingDefaultInputDevice
        }
        return device
    }

    private func resolveInputFormat(on unit: AudioUnit) throws -> AudioStreamBasicDescription {
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = audioUnitManager.getProperty(
            unit: unit,
            propertyID: kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Input,
            element: 1,
            data: &asbd,
            dataSize: &size
        )
        guard status == noErr else {
            throw CoreAudioMicrophoneCaptureError.invalidInputFormat
        }
        return asbd
    }

    private func float32InputFormat(from inputFormat: AudioStreamBasicDescription) throws -> AVAudioFormat {
        var format = inputFormat
        guard format.mChannelsPerFrame > 0 else {
            throw CoreAudioMicrophoneCaptureError.invalidInputFormat
        }

        let bytesPerFrame = UInt32(MemoryLayout<Float32>.size) * format.mChannelsPerFrame
        format.mFormatID = kAudioFormatLinearPCM
        format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        format.mBitsPerChannel = 32
        format.mBytesPerPacket = bytesPerFrame
        format.mBytesPerFrame = bytesPerFrame
        format.mFramesPerPacket = 1

        guard let converted = AVAudioFormat(streamDescription: &format) else {
            throw CoreAudioMicrophoneCaptureError.unsupportedFormat
        }
        return converted
    }

    private func nativeInputFormat(from inputFormat: AudioStreamBasicDescription) throws -> AVAudioFormat {
        var format = inputFormat
        guard format.mSampleRate > 0, format.mChannelsPerFrame > 0,
            let nativeFormat = AVAudioFormat(streamDescription: &format)
        else {
            throw CoreAudioMicrophoneCaptureError.unsupportedFormat
        }
        return nativeFormat
    }

    private func configureInputFormat(
        on unit: AudioUnit,
        defaultFormat: AudioStreamBasicDescription
    ) throws -> AVAudioFormat {
        let floatFormat = try float32InputFormat(from: defaultFormat)
        do {
            try setInputStreamFormat(unit: unit, floatFormat)
            return floatFormat
        } catch CoreAudioMicrophoneCaptureError.failedToSetInputFormat {
            return try nativeInputFormat(from: defaultFormat)
        }
    }

    private func setInputStreamFormat(unit: AudioUnit, _ format: AVAudioFormat) throws {
        var asbd = format.streamDescription.pointee
        let size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = audioUnitManager.setProperty(
            unit: unit,
            propertyID: kAudioUnitProperty_StreamFormat,
            scope: kAudioUnitScope_Output,
            element: 1,
            data: &asbd,
            dataSize: size
        )
        guard status == noErr else {
            throw CoreAudioMicrophoneCaptureError.failedToSetInputFormat
        }
    }

    private func enableInput(on unit: AudioUnit) throws {
        var enableInput: UInt32 = 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = audioUnitManager.setProperty(
            unit: unit,
            propertyID: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Input,
            element: 1,
            data: &enableInput,
            dataSize: size
        )
        guard status == noErr else {
            throw CoreAudioMicrophoneCaptureError.failedToEnableInput
        }
    }

    private func disableOutput(on unit: AudioUnit) throws {
        var disableOutput: UInt32 = 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        let status = audioUnitManager.setProperty(
            unit: unit,
            propertyID: kAudioOutputUnitProperty_EnableIO,
            scope: kAudioUnitScope_Output,
            element: 0,
            data: &disableOutput,
            dataSize: size
        )
        guard status == noErr else {
            throw CoreAudioMicrophoneCaptureError.failedToDisableOutput
        }
    }

    private func setCurrentInputDevice(unit: AudioUnit, _ deviceID: AudioDeviceID) throws {
        var device = deviceID
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = audioUnitManager.setProperty(
            unit: unit,
            propertyID: kAudioOutputUnitProperty_CurrentDevice,
            scope: kAudioUnitScope_Global,
            element: 0,
            data: &device,
            dataSize: size
        )
        guard status == noErr else {
            throw CoreAudioMicrophoneCaptureError.failedToSetCurrentDevice
        }
    }

    nonisolated private func renderInputBuffer(
        actionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
        timeStamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        lock.lock()
        let isCapturing = isCapturing
        let state = state
        let unit = unit
        guard isCapturing,
            let state,
            let unit,
            let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: state.inputFormat,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        else {
            lock.unlock()
            return noErr
        }
        lock.unlock()

        inputBuffer.frameLength = AVAudioFrameCount(frameCount)
        let renderStatus = audioUnitManager.renderInput(
            unit: unit,
            actionFlags: actionFlags,
            timeStamp: timeStamp,
            busNumber: 1,
            frameCount: frameCount,
            data: inputBuffer.mutableAudioBufferList
        )
        guard renderStatus == noErr else {
            return renderStatus
        }

        callbackQueue.async { [callback = state.callback, inputBuffer] in
            callback(inputBuffer)
        }
        return noErr
    }

    private static let micRenderCallback: AURenderCallback = {
        inRefCon, ioActionFlags, inTimeStamp, _, inNumberFrames, _ in
        let capture = Unmanaged<CoreAudioMicrophoneCapture>.fromOpaque(inRefCon).takeUnretainedValue()
        return capture.renderInputBuffer(
            actionFlags: ioActionFlags,
            timeStamp: inTimeStamp,
            frameCount: inNumberFrames
        )
    }
}
