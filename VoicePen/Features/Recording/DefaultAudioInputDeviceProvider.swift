@preconcurrency import CoreAudio
import Foundation

nonisolated struct DefaultAudioInputDevice: Equatable, Sendable {
    let id: AudioDeviceID
    let name: String?

    static let systemDefaultFallback = DefaultAudioInputDevice(
        id: AudioDeviceID(kAudioObjectUnknown),
        name: nil
    )

    var systemDefaultDisplayText: String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "System default"
        }

        return "System default (\(name))"
    }
}

nonisolated protocol DefaultAudioInputDeviceObservation: AnyObject, Sendable {
    func cancel()
}

nonisolated protocol DefaultAudioInputDeviceProviding: AnyObject, Sendable {
    func currentDefaultInputDevice() -> DefaultAudioInputDevice

    func observeDefaultInputDeviceChanges(
        _ handler: @escaping @MainActor @Sendable (DefaultAudioInputDevice) -> Void
    ) -> DefaultAudioInputDeviceObservation
}

nonisolated final class NoOpDefaultAudioInputDeviceObservation: DefaultAudioInputDeviceObservation, @unchecked Sendable {
    func cancel() {}
}

nonisolated final class CoreAudioDefaultInputDeviceProvider: DefaultAudioInputDeviceProviding {
    func currentDefaultInputDevice() -> DefaultAudioInputDevice {
        guard let deviceID = defaultInputDeviceID() else {
            return .systemDefaultFallback
        }

        return DefaultAudioInputDevice(
            id: deviceID,
            name: inputDeviceName(deviceID: deviceID)
        )
    }

    func observeDefaultInputDeviceChanges(
        _ handler: @escaping @MainActor @Sendable (DefaultAudioInputDevice) -> Void
    ) -> DefaultAudioInputDeviceObservation {
        var address = Self.defaultInputDeviceAddress()
        let queue = DispatchQueue.main
        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let device = self.currentDefaultInputDevice()
            Task { @MainActor in
                handler(device)
            }
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listenerBlock
        )
        guard status == noErr else {
            return NoOpDefaultAudioInputDeviceObservation()
        }

        return CoreAudioDefaultInputDeviceObservation(
            address: address,
            queue: queue,
            listenerBlock: listenerBlock
        )
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.defaultInputDeviceAddress()

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private func inputDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        var nameReference: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &nameReference
        )
        guard status == noErr, let nameReference else {
            return nil
        }

        let name = nameReference.takeRetainedValue() as String
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private static func defaultInputDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

nonisolated private final class CoreAudioDefaultInputDeviceObservation:
    DefaultAudioInputDeviceObservation, @unchecked Sendable
{
    private let address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private let listenerBlock: AudioObjectPropertyListenerBlock
    private let lock = NSLock()
    private var isCancelled = false

    init(
        address: AudioObjectPropertyAddress,
        queue: DispatchQueue,
        listenerBlock: @escaping AudioObjectPropertyListenerBlock
    ) {
        self.address = address
        self.queue = queue
        self.listenerBlock = listenerBlock
    }

    deinit {
        cancel()
    }

    func cancel() {
        lock.lock()
        if isCancelled {
            lock.unlock()
            return
        }
        isCancelled = true
        lock.unlock()

        var address = address
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            queue,
            listenerBlock
        )
    }
}
