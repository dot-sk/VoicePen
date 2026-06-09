import AppKit
import Foundation
import KeyboardShortcuts

enum HotkeyError: LocalizedError, Equatable {
    case shortcutMissing

    var errorDescription: String? {
        switch self {
        case .shortcutMissing:
            "VoicePen custom shortcut is not configured."
        }
    }
}

extension KeyboardShortcuts.Name {
    static let voicePenPushToTalk = Self("voicePenPushToTalk")
}

@MainActor
final class LivePushToTalkHotkeyClient: PushToTalkHotkeyClient {
    private let settingsStore: AppSettingsStore
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var isModifierPressed = false
    private let pressTracker = HotkeyPressStateTracker(cooldown: 0.08)
    private var customShortcutTask: Task<Void, Never>?
    private var isInstalled = false

    init(settingsStore: AppSettingsStore) {
        self.settingsStore = settingsStore
    }

    func install(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) throws {
        uninstall()
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        installEventTapIfPossible()

        switch settingsStore.hotkeyPreference {
        case .option, .leftOption, .rightOption:
            installModifierMonitoring()
        case .custom:
            try installCustomShortcut(onKeyDown: onKeyDown, onKeyUp: onKeyUp)
        }

        isInstalled = true
    }

    func uninstall() {
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
        }
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
        }
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }

        globalEventMonitor = nil
        localEventMonitor = nil
        eventTap = nil
        eventTapRunLoopSource = nil
        onKeyDown = nil
        onKeyUp = nil
        isModifierPressed = false
        customShortcutTask?.cancel()
        customShortcutTask = nil
        pressTracker.cancel()

        if isInstalled {
            KeyboardShortcuts.disable(.voicePenPushToTalk)
        }

        isInstalled = false
    }

    private func installCustomShortcut(
        onKeyDown: @escaping () -> Void,
        onKeyUp: @escaping () -> Void
    ) throws {
        guard KeyboardShortcuts.getShortcut(for: .voicePenPushToTalk) != nil else {
            throw HotkeyError.shortcutMissing
        }

        KeyboardShortcuts.enable(.voicePenPushToTalk)
        customShortcutTask = Task { @MainActor [weak self] in
            for await event in KeyboardShortcuts.events(for: .voicePenPushToTalk) {
                guard let self else { return }
                switch event {
                case .keyDown:
                    self.beginPress(onKeyDown: onKeyDown)
                case .keyUp:
                    self.endPress(onKeyUp: onKeyUp)
                }
            }
        }
    }

    private func installModifierMonitoring() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierEvent(event)
            }
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleModifierEvent(event)
            }
            return event
        }
    }

    private func installEventTapIfPossible() {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.tapDisabledByTimeout.rawValue)
            | (1 << CGEventType.tapDisabledByUserInput.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: CGEventMask(eventMask),
                callback: { _, type, event, userInfo in
                    guard let userInfo else {
                        return Unmanaged.passUnretained(event)
                    }

                    let client = Unmanaged<LivePushToTalkHotkeyClient>
                        .fromOpaque(userInfo)
                        .takeUnretainedValue()
                    Task { @MainActor in
                        client.handleEventTap(type: type, event: event)
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            AppLogger.info("Push-to-talk CG event tap unavailable; using NSEvent/KeyboardShortcuts fallback")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        eventTap = tap
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handleEventTap(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        case .keyDown:
            guard matchesSelectedCustomShortcutKeyDown(event) else { return }
            beginPress()
        case .keyUp:
            guard matchesSelectedCustomShortcutKeyUp(event) else { return }
            endPress()
        case .flagsChanged:
            handleModifierEventTap(event)
        default:
            break
        }
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard matchesSelectedModifier(event) else { return }

        let isPressed = event.modifierFlags.contains(.option)
        guard isPressed != isModifierPressed else { return }
        isModifierPressed = isPressed

        if isPressed {
            beginPress()
        } else {
            endPress()
        }
    }

    private func handleModifierEventTap(_ event: CGEvent) {
        guard settingsStore.hotkeyPreference != .custom else { return }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard matchesSelectedModifierKeyCode(keyCode) else { return }

        let isPressed = event.flags.contains(.maskAlternate)
        guard isPressed != isModifierPressed else { return }
        isModifierPressed = isPressed

        if isPressed {
            beginPress()
        } else {
            endPress()
        }
    }

    private func beginPress(onKeyDown: (() -> Void)? = nil) {
        let action = onKeyDown ?? self.onKeyDown
        pressTracker.keyDown {
            action?()
        }
    }

    private func endPress(onKeyUp: (() -> Void)? = nil) {
        let action = onKeyUp ?? self.onKeyUp
        pressTracker.keyUp {
            action?()
        }
    }

    private func matchesSelectedModifier(_ event: NSEvent) -> Bool {
        matchesSelectedModifierKeyCode(Int(event.keyCode))
    }

    private func matchesSelectedModifierKeyCode(_ keyCode: Int) -> Bool {
        switch settingsStore.hotkeyPreference {
        case .option:
            return keyCode == 0x3A || keyCode == 0x3D
        case .leftOption:
            return keyCode == 0x3A
        case .rightOption:
            return keyCode == 0x3D
        case .custom:
            return false
        }
    }

    private func matchesSelectedCustomShortcutKeyDown(_ event: CGEvent) -> Bool {
        guard settingsStore.hotkeyPreference == .custom,
            let shortcut = KeyboardShortcuts.getShortcut(for: .voicePenPushToTalk)
        else {
            return false
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == shortcut.carbonKeyCode else { return false }

        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let eventModifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection(relevantModifiers)
        let shortcutModifiers = shortcut.modifiers.intersection(relevantModifiers)
        return eventModifiers == shortcutModifiers
    }

    private func matchesSelectedCustomShortcutKeyUp(_ event: CGEvent) -> Bool {
        guard settingsStore.hotkeyPreference == .custom,
            let shortcut = KeyboardShortcuts.getShortcut(for: .voicePenPushToTalk)
        else {
            return false
        }

        return Int(event.getIntegerValueField(.keyboardEventKeycode)) == shortcut.carbonKeyCode
    }
}
