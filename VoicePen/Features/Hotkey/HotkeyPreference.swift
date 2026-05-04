import Foundation
import KeyboardShortcuts

enum HotkeyPreference: String, CaseIterable, Identifiable {
    case option
    case leftOption
    case rightOption
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .option:
            return "Option (either side)"
        case .leftOption:
            return "Left Option"
        case .rightOption:
            return "Right Option"
        case .custom:
            return "Custom shortcut"
        }
    }
}

extension HotkeyPreference {
    @MainActor
    func menuBarHint(customShortcutDescription: () -> String? = {
        KeyboardShortcuts.getShortcut(for: .voicePenPushToTalk)?.description
    }) -> String {
        switch self {
        case .option:
            return "Option"
        case .leftOption:
            return "Left Option"
        case .rightOption:
            return "Right Option"
        case .custom:
            return customShortcutDescription() ?? "Custom shortcut not set"
        }
    }
}
