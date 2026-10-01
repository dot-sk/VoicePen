@preconcurrency import CoreAudio
import Foundation

nonisolated enum AudioInputSelection: Hashable, Sendable {
    case systemDefault
    case device(uid: String, name: String)

    var id: String {
        switch self {
        case .systemDefault:
            return "system-default"
        case let .device(uid, _):
            return "device:\(uid)"
        }
    }

    var deviceUID: String? {
        guard case let .device(uid, _) = self else { return nil }
        return uid
    }

    var lastKnownName: String? {
        guard case let .device(_, name) = self else { return nil }
        return name
    }

    var normalized: AudioInputSelection {
        switch self {
        case .systemDefault:
            return .systemDefault
        case let .device(uid, name):
            let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedUID.isEmpty, !normalizedName.isEmpty else {
                return .systemDefault
            }
            return .device(uid: normalizedUID, name: normalizedName)
        }
    }

    static func == (lhs: AudioInputSelection, rhs: AudioInputSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

nonisolated struct AudioInputDevice: Equatable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String?

    init(id: AudioDeviceID, uid: String? = nil, name: String?) {
        self.id = id
        self.uid =
            uid?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (id == kAudioObjectUnknown ? "" : "audio-device-\(id)")
        self.name = name
    }

    static let systemDefaultFallback = AudioInputDevice(
        id: AudioDeviceID(kAudioObjectUnknown),
        uid: "",
        name: nil
    )

    var displayName: String {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "Unnamed input device"
        }
        return name
    }

    var systemDefaultDisplayText: String {
        guard id != kAudioObjectUnknown, displayName != "Unnamed input device" else {
            return "System default"
        }
        return "System default (\(displayName))"
    }
}

nonisolated struct AudioInputDeviceSnapshot: Equatable, Sendable {
    let defaultDevice: AudioInputDevice
    let devices: [AudioInputDevice]

    static let empty = AudioInputDeviceSnapshot(defaultDevice: .systemDefaultFallback, devices: [])
}

nonisolated struct AudioInputDeviceOption: Identifiable, Equatable, Sendable {
    let selection: AudioInputSelection
    let title: String
    let isAvailable: Bool

    var id: String { selection.id }
}

nonisolated protocol AudioInputDeviceObservation: AnyObject, Sendable {
    func cancel()
}

nonisolated protocol AudioInputDeviceProviding: AnyObject, Sendable {
    func snapshot() -> AudioInputDeviceSnapshot

    func observeChanges(
        _ handler: @escaping @MainActor @Sendable (AudioInputDeviceSnapshot) -> Void
    ) -> AudioInputDeviceObservation
}

nonisolated final class NoOpAudioInputDeviceObservation: AudioInputDeviceObservation, @unchecked Sendable {
    func cancel() {}
}

nonisolated protocol AudioInputDeviceResolving: AnyObject, Sendable {
    func resolveSelectedInputDevice() throws -> AudioInputDevice
}

nonisolated enum AudioInputSelectionError: LocalizedError, Equatable, Sendable {
    case missingSystemDefault
    case selectedDeviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingSystemDefault:
            return "No system default microphone is available."
        case let .selectedDeviceUnavailable(name):
            return "The selected microphone \"\(name)\" is unavailable. Reconnect it or choose another microphone in Settings."
        }
    }
}

nonisolated final class AudioInputSelectionCoordinator: AudioInputDeviceResolving, @unchecked Sendable {
    private let provider: AudioInputDeviceProviding
    private let lock = NSLock()
    private var selection: AudioInputSelection

    init(
        provider: AudioInputDeviceProviding,
        selection: AudioInputSelection = .systemDefault
    ) {
        self.provider = provider
        self.selection = selection.normalized
    }

    func updateSelection(_ selection: AudioInputSelection) {
        lock.lock()
        self.selection = selection.normalized
        lock.unlock()
    }

    func currentSelection() -> AudioInputSelection {
        lock.lock()
        defer { lock.unlock() }
        return selection
    }

    func resolveSelectedInputDevice() throws -> AudioInputDevice {
        let selection = currentSelection()
        let snapshot = provider.snapshot()

        switch selection {
        case .systemDefault:
            guard snapshot.defaultDevice.id != kAudioObjectUnknown else {
                throw AudioInputSelectionError.missingSystemDefault
            }
            return snapshot.defaultDevice
        case let .device(uid, name):
            guard let device = snapshot.devices.first(where: { $0.uid == uid }) else {
                throw AudioInputSelectionError.selectedDeviceUnavailable(name)
            }
            return device
        }
    }

    func options(snapshot: AudioInputDeviceSnapshot? = nil) -> [AudioInputDeviceOption] {
        let snapshot = snapshot ?? provider.snapshot()
        let selection = currentSelection()
        let duplicateNames = Dictionary(grouping: snapshot.devices, by: \.displayName)
            .filter { $0.value.count > 1 }
            .keys

        var options = [
            AudioInputDeviceOption(
                selection: .systemDefault,
                title: snapshot.defaultDevice.systemDefaultDisplayText,
                isAvailable: snapshot.defaultDevice.id != kAudioObjectUnknown
            )
        ]
        options += snapshot.devices.map { device in
            let title =
                duplicateNames.contains(device.displayName)
                ? "\(device.displayName) (\(device.uid))"
                : device.displayName
            return AudioInputDeviceOption(
                selection: .device(uid: device.uid, name: device.displayName),
                title: title,
                isAvailable: true
            )
        }

        if case let .device(uid, name) = selection,
            !snapshot.devices.contains(where: { $0.uid == uid })
        {
            options.append(
                AudioInputDeviceOption(
                    selection: selection,
                    title: "\(name) (Unavailable)",
                    isAvailable: false
                )
            )
        }

        return options
    }
}

nonisolated protocol CoreAudioInputDeviceSystem: Sendable {
    func audioDeviceIDs() -> [AudioDeviceID]
    func defaultInputDeviceID() -> AudioDeviceID?
    func inputChannelCount(deviceID: AudioDeviceID) -> Int
    func deviceUID(deviceID: AudioDeviceID) -> String?
    func deviceName(deviceID: AudioDeviceID) -> String?
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AudioInputDeviceObservation
}

nonisolated final class CoreAudioInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    private let system: CoreAudioInputDeviceSystem

    init(system: CoreAudioInputDeviceSystem = LiveCoreAudioInputDeviceSystem()) {
        self.system = system
    }

    func snapshot() -> AudioInputDeviceSnapshot {
        let devices = system.audioDeviceIDs()
            .filter { system.inputChannelCount(deviceID: $0) > 0 }
            .compactMap(makeDevice)
            .sorted {
                let nameOrder = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
                return nameOrder == .orderedSame ? $0.uid < $1.uid : nameOrder == .orderedAscending
            }

        let defaultDevice =
            system.defaultInputDeviceID()
            .flatMap { id in devices.first(where: { $0.id == id }) ?? makeDevice(id) }
            ?? .systemDefaultFallback

        return AudioInputDeviceSnapshot(defaultDevice: defaultDevice, devices: devices)
    }

    func observeChanges(
        _ handler: @escaping @MainActor @Sendable (AudioInputDeviceSnapshot) -> Void
    ) -> AudioInputDeviceObservation {
        let observation = AudioInputDeviceSnapshotObservation(
            snapshotProvider: { [weak self] in self?.snapshot() ?? .empty },
            system: system,
            handler: handler
        )
        observation.start()
        return observation
    }

    private func makeDevice(_ id: AudioDeviceID) -> AudioInputDevice? {
        guard let uid = system.deviceUID(deviceID: id)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !uid.isEmpty
        else {
            return nil
        }
        return AudioInputDevice(id: id, uid: uid, name: system.deviceName(deviceID: id))
    }
}

nonisolated private final class AudioInputDeviceSnapshotObservation:
    AudioInputDeviceObservation, @unchecked Sendable
{
    private let snapshotProvider: @Sendable () -> AudioInputDeviceSnapshot
    private let system: CoreAudioInputDeviceSystem
    private let handler: @MainActor @Sendable (AudioInputDeviceSnapshot) -> Void
    private let lock = NSLock()
    private var lastSnapshot: AudioInputDeviceSnapshot
    private var systemObservation: AudioInputDeviceObservation?
    private var isCancelled = false
    private var isRefreshScheduled = false

    init(
        snapshotProvider: @escaping @Sendable () -> AudioInputDeviceSnapshot,
        system: CoreAudioInputDeviceSystem,
        handler: @escaping @MainActor @Sendable (AudioInputDeviceSnapshot) -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.system = system
        self.handler = handler
        self.lastSnapshot = snapshotProvider()
    }

    deinit {
        cancel()
    }

    func start() {
        lock.lock()
        guard !isCancelled, systemObservation == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        let observation = system.observeChanges { [weak self] in
            self?.scheduleRefresh()
        }

        lock.lock()
        if isCancelled {
            lock.unlock()
            observation.cancel()
            return
        }
        systemObservation = observation
        lock.unlock()
        scheduleRefresh()
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let observation = systemObservation
        systemObservation = nil
        lock.unlock()
        observation?.cancel()
    }

    private func scheduleRefresh() {
        lock.lock()
        guard !isCancelled, !isRefreshScheduled else {
            lock.unlock()
            return
        }
        isRefreshScheduled = true
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            self?.emitScheduledRefresh()
        }
    }

    private func emitScheduledRefresh() {
        lock.lock()
        guard !isCancelled else {
            isRefreshScheduled = false
            lock.unlock()
            return
        }
        isRefreshScheduled = false
        lock.unlock()

        let snapshot = snapshotProvider()
        lock.lock()
        guard !isCancelled, snapshot != lastSnapshot else {
            lock.unlock()
            return
        }
        lastSnapshot = snapshot
        lock.unlock()

        Task { @MainActor in
            handler(snapshot)
        }
    }
}

nonisolated struct LiveCoreAudioInputDeviceSystem: CoreAudioInputDeviceSystem {
    func audioDeviceIDs() -> [AudioDeviceID] {
        var address = Self.devicesAddress()
        var propertySize: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &propertySize
            ) == noErr,
            propertySize > 0
        else {
            return []
        }

        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        let status = deviceIDs.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &propertySize,
                bytes.baseAddress!
            )
        }
        return status == noErr ? deviceIDs : []
    }

    func defaultInputDeviceID() -> AudioDeviceID? {
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
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
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

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(propertySize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &propertySize,
                rawBuffer
            ) == noErr
        else {
            return 0
        }

        return UnsafeMutableAudioBufferListPointer(
            rawBuffer.assumingMemoryBound(to: AudioBufferList.self)
        )
        .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    func deviceUID(deviceID: AudioDeviceID) -> String? {
        stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    func deviceName(deviceID: AudioDeviceID) -> String? {
        stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
    }

    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AudioInputDeviceObservation {
        let observation = LiveCoreAudioInputDeviceSystemObservation(system: self, handler: handler)
        observation.start()
        return observation
    }

    private func stringProperty(
        deviceID: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var reference: Unmanaged<CFString>?
        var propertySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &propertySize,
            &reference
        )
        guard status == noErr, let reference else { return nil }
        let value = reference.takeRetainedValue() as String
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate static func devicesAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    fileprivate static func defaultInputDeviceAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    fileprivate static func nameAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

nonisolated private final class LiveCoreAudioInputDeviceSystemObservation:
    AudioInputDeviceObservation, @unchecked Sendable
{
    private struct Listener {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let system: LiveCoreAudioInputDeviceSystem
    private let handler: @Sendable () -> Void
    private let queue = DispatchQueue.main
    private let lock = NSLock()
    private var systemListeners: [Listener] = []
    private var nameListeners: [Listener] = []
    private var isCancelled = false

    init(
        system: LiveCoreAudioInputDeviceSystem,
        handler: @escaping @Sendable () -> Void
    ) {
        self.system = system
        self.handler = handler
    }

    deinit {
        cancel()
    }

    func start() {
        addSystemListener(address: LiveCoreAudioInputDeviceSystem.devicesAddress(), rebuildNames: true)
        addSystemListener(address: LiveCoreAudioInputDeviceSystem.defaultInputDeviceAddress(), rebuildNames: false)
        rebuildNameListeners()
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true
        let listeners = systemListeners + nameListeners
        systemListeners = []
        nameListeners = []
        lock.unlock()

        listeners.forEach(removeListener)
    }

    private func addSystemListener(
        address: AudioObjectPropertyAddress,
        rebuildNames: Bool
    ) {
        lock.lock()
        let canAddListener = !isCancelled
        lock.unlock()
        guard canAddListener else { return }

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            if rebuildNames {
                self.rebuildNameListeners()
            }
            self.handler()
        }
        guard
            addListener(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                address: address,
                block: block
            )
        else {
            return
        }

        lock.lock()
        if isCancelled {
            lock.unlock()
            removeListener(
                Listener(
                    objectID: AudioObjectID(kAudioObjectSystemObject),
                    address: address,
                    block: block
                )
            )
            return
        }
        systemListeners.append(
            Listener(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                address: address,
                block: block
            ))
        lock.unlock()
    }

    private func rebuildNameListeners() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        let oldListeners = nameListeners
        nameListeners = []
        lock.unlock()
        oldListeners.forEach(removeListener)

        for deviceID in system.audioDeviceIDs() where system.inputChannelCount(deviceID: deviceID) > 0 {
            let address = LiveCoreAudioInputDeviceSystem.nameAddress()
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.handler()
            }
            guard addListener(objectID: deviceID, address: address, block: block) else {
                continue
            }

            lock.lock()
            if isCancelled {
                lock.unlock()
                removeListener(Listener(objectID: deviceID, address: address, block: block))
                continue
            }
            nameListeners.append(Listener(objectID: deviceID, address: address, block: block))
            lock.unlock()
        }
    }

    private func addListener(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> Bool {
        var address = address
        return AudioObjectAddPropertyListenerBlock(objectID, &address, queue, block) == noErr
    }

    private func removeListener(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(
            listener.objectID,
            &address,
            queue,
            listener.block
        )
    }
}
