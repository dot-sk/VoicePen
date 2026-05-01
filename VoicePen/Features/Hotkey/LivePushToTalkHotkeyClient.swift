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

final class LivePushToTalkHotkeyClient: PushToTalkHotkeyClient {
    private let settingsStore: AppSettingsStore
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var onKeyDown: (() -> Void)?
    private var onKeyUp: (() -> Void)?
    private var isModifierPressed = false
    private var holdGate: HotkeyHoldGate?
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
        holdGate = HotkeyHoldGate(holdDuration: settingsStore.hotkeyHoldDuration)

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

        globalEventMonitor = nil
        localEventMonitor = nil
        onKeyDown = nil
        onKeyUp = nil
        isModifierPressed = false
        holdGate?.cancel()
        holdGate = nil

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
        KeyboardShortcuts.onKeyDown(for: .voicePenPushToTalk) {
            self.beginHold(onKeyDown: onKeyDown)
        }

        KeyboardShortcuts.onKeyUp(for: .voicePenPushToTalk) {
            self.endHold(onKeyUp: onKeyUp)
        }
    }

    private func installModifierMonitoring() {
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierEvent(event)
        }

        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleModifierEvent(event)
            return event
        }
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard matchesSelectedModifier(event) else { return }

        let isPressed = event.modifierFlags.contains(.option)
        guard isPressed != isModifierPressed else { return }
        isModifierPressed = isPressed

        if isPressed {
            beginHold()
        } else {
            endHold()
        }
    }

    private func beginHold(onKeyDown: (() -> Void)? = nil) {
        let action = onKeyDown ?? self.onKeyDown
        holdGate?.keyDown {
            action?()
        }
    }

    private func endHold(onKeyUp: (() -> Void)? = nil) {
        let action = onKeyUp ?? self.onKeyUp
        holdGate?.keyUp {
            action?()
        }
    }

    private func matchesSelectedModifier(_ event: NSEvent) -> Bool {
        switch settingsStore.hotkeyPreference {
        case .option:
            return event.keyCode == 0x3A || event.keyCode == 0x3D
        case .leftOption:
            return event.keyCode == 0x3A
        case .rightOption:
            return event.keyCode == 0x3D
        case .custom:
            return false
        }
    }
}
