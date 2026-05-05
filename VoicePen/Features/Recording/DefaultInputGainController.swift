import CoreAudio
import Foundation

protocol DefaultInputGainControlling: AnyObject {
    func boostDefaultInputGain() -> DefaultInputGainRestoreToken?
    func restoreDefaultInputGain(_ token: DefaultInputGainRestoreToken)
}

struct DefaultInputGainRestoreToken: Equatable {
    struct RestoredGain: Equatable {
        let deviceID: AudioDeviceID
        let element: AudioObjectPropertyElement
        let originalVolume: Float32
        let boostedVolume: Float32
    }

    let gains: [RestoredGain]
}

final class NoOpDefaultInputGainController: DefaultInputGainControlling {
    func boostDefaultInputGain() -> DefaultInputGainRestoreToken? {
        nil
    }

    func restoreDefaultInputGain(_: DefaultInputGainRestoreToken) {}
}

final class CoreAudioDefaultInputGainController: DefaultInputGainControlling {
    private let audioSystem: CoreAudioInputGainSystem

    init(audioSystem: CoreAudioInputGainSystem = LiveCoreAudioInputGainSystem()) {
        self.audioSystem = audioSystem
    }

    func boostDefaultInputGain() -> DefaultInputGainRestoreToken? {
        guard let deviceID = audioSystem.defaultInputDeviceID() else {
            return nil
        }

        var restoredGains: [DefaultInputGainRestoreToken.RestoredGain] = []
        for element in candidateElements(for: deviceID) {
            guard audioSystem.isInputVolumeSettable(deviceID: deviceID, element: element),
                let originalVolume = audioSystem.inputVolume(deviceID: deviceID, element: element)
            else {
                continue
            }

            guard audioSystem.setInputVolume(1.0, deviceID: deviceID, element: element) else {
                continue
            }

            restoredGains.append(
                DefaultInputGainRestoreToken.RestoredGain(
                    deviceID: deviceID,
                    element: element,
                    originalVolume: originalVolume,
                    boostedVolume: 1.0
                )
            )
        }

        return restoredGains.isEmpty ? nil : DefaultInputGainRestoreToken(gains: restoredGains)
    }

    func restoreDefaultInputGain(_ token: DefaultInputGainRestoreToken) {
        for gain in token.gains {
            guard let currentVolume = audioSystem.inputVolume(deviceID: gain.deviceID, element: gain.element),
                abs(currentVolume - gain.boostedVolume) < 0.02,
                audioSystem.isInputVolumeSettable(deviceID: gain.deviceID, element: gain.element)
            else {
                continue
            }

            _ = audioSystem.setInputVolume(
                gain.originalVolume,
                deviceID: gain.deviceID,
                element: gain.element
            )
        }
    }

    private func candidateElements(for deviceID: AudioDeviceID) -> [AudioObjectPropertyElement] {
        var elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain]
        let channelCount = max(0, audioSystem.inputChannelCount(deviceID: deviceID))
        if channelCount > 0 {
            elements += (1...channelCount).map { AudioObjectPropertyElement($0) }
        }
        return Array(Set(elements)).sorted()
    }
}

protocol CoreAudioInputGainSystem {
    func defaultInputDeviceID() -> AudioDeviceID?
    func inputChannelCount(deviceID: AudioDeviceID) -> Int
    func inputVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float32?
    func isInputVolumeSettable(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool
    func setInputVolume(
        _ volume: Float32,
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Bool
}

struct LiveCoreAudioInputGainSystem: CoreAudioInputGainSystem {
    func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else {
            return nil
        }
        return deviceID
    }

    func inputChannelCount(deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var propertySize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize) == noErr,
            propertySize > 0
        else {
            return 0
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &propertySize,
                bufferListPointer
            ) == noErr
        else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            bufferListPointer.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(0) { total, buffer in
            total + Int(buffer.mNumberChannels)
        }
    }

    func inputVolume(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Float32? {
        var volume = Float32(0)
        var propertySize = UInt32(MemoryLayout<Float32>.size)
        var address = inputVolumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, &volume)
        return status == noErr ? volume : nil
    }

    func isInputVolumeSettable(deviceID: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
        var address = inputVolumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        var isSettable = DarwinBoolean(false)
        let status = AudioObjectIsPropertySettable(deviceID, &address, &isSettable)
        return status == noErr && isSettable.boolValue
    }

    func setInputVolume(
        _ volume: Float32,
        deviceID: AudioDeviceID,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var clampedVolume = min(max(volume, 0), 1)
        let propertySize = UInt32(MemoryLayout<Float32>.size)
        var address = inputVolumeAddress(element: element)
        guard AudioObjectHasProperty(deviceID, &address) else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            propertySize,
            &clampedVolume
        )
        return status == noErr
    }

    private func inputVolumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: element
        )
    }
}
