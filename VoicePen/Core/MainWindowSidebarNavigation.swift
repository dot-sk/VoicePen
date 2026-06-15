import Foundation

enum VoicePenSettingsSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case model
    case modes
    case config
    case dictionary
    case meetings
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "Home"
        case .model:
            return "Models"
        case .modes:
            return "Modes"
        case .config:
            return "Settings"
        case .dictionary:
            return "Dictionary"
        case .meetings:
            return "Meetings"
        case .history:
            return "Sessions"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "house"
        case .model:
            return "sparkles"
        case .modes:
            return "terminal"
        case .config:
            return "slider.horizontal.3"
        case .dictionary:
            return "text.book.closed"
        case .meetings:
            return "person.2.wave.2"
        case .history:
            return "mic"
        case .about:
            return "info.circle"
        }
    }
}

struct MainWindowSidebarSectionGroups: Equatable, Sendable {
    let primary: [VoicePenSettingsSection]
    let settings: [VoicePenSettingsSection]
    let bottom: [VoicePenSettingsSection]

    static func make(modesFeatureEnabled: Bool) -> MainWindowSidebarSectionGroups {
        var settings: [VoicePenSettingsSection] = [
            .dictionary,
            .model
        ]
        if modesFeatureEnabled {
            settings.append(.modes)
        }
        settings.append(.about)

        return MainWindowSidebarSectionGroups(
            primary: [.general, .meetings, .history],
            settings: settings,
            bottom: [.config]
        )
    }
}

enum MainWindowSidebarNavigation {
    static func systemImage(
        for section: VoicePenSettingsSection,
        showsMeetingRecordingPanel: Bool,
        meetingRecordingSystemImage: String
    ) -> String {
        if section == .meetings, showsMeetingRecordingPanel {
            return meetingRecordingSystemImage
        }
        return section.systemImage
    }

    static func sectionForKeyboardShortcut(keyCode: UInt16) -> VoicePenSettingsSection? {
        switch keyCode {
        case 18, 83:
            return .general
        case 19, 84:
            return .meetings
        case 20, 85:
            return .history
        default:
            return nil
        }
    }
}
