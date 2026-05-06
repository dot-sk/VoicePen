import Foundation

nonisolated enum MeetingSystemAudioSourceMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case all
    case selectedAppsOnly
    case allExceptSelectedApps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All system audio"
        case .selectedAppsOnly:
            return "Selected apps only"
        case .allExceptSelectedApps:
            return "All except selected apps"
        }
    }
}

nonisolated struct MeetingAudioAppSelection: Codable, Equatable, Identifiable, Sendable {
    var displayName: String
    var bundleIdentifier: String

    var id: String { bundleIdentifier }

    init(displayName: String, bundleIdentifier: String) {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = normalizedBundleIdentifier
        self.displayName = normalizedDisplayName.isEmpty ? normalizedBundleIdentifier : normalizedDisplayName
    }

    var isValid: Bool {
        !bundleIdentifier.isEmpty
    }
}

nonisolated struct MeetingSystemAudioSourceSettings: Equatable, Sendable {
    var mode: MeetingSystemAudioSourceMode
    var selectedApps: [MeetingAudioAppSelection]

    static let all = MeetingSystemAudioSourceSettings(mode: .all, selectedApps: [])

    var bundleIdentifiers: [String] {
        selectedApps.map(\.bundleIdentifier)
    }
}

nonisolated struct MeetingSystemAudioTapPlan: Equatable, Sendable {
    var mode: MeetingSystemAudioSourceMode
    var bundleIdentifiers: [String]

    var isExclusive: Bool {
        mode == .all || mode == .allExceptSelectedApps
    }

    var usesBundleIdentifierFilter: Bool {
        mode != .all
    }

    static func build(settings: MeetingSystemAudioSourceSettings) -> MeetingSystemAudioTapPlan {
        MeetingSystemAudioTapPlan(
            mode: settings.mode,
            bundleIdentifiers: normalizedBundleIdentifiers(settings.bundleIdentifiers)
        )
    }

    private static func normalizedBundleIdentifiers(_ bundleIdentifiers: [String]) -> [String] {
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

nonisolated struct MeetingSystemAudioSourcePreflightResult: Equatable, Sendable {
    var settings: MeetingSystemAudioSourceSettings
    var warning: String?
}

nonisolated enum MeetingSystemAudioSourcePreflight {
    static func resolve(
        settings: MeetingSystemAudioSourceSettings,
        runningBundleIdentifiers: Set<String>
    ) -> MeetingSystemAudioSourcePreflightResult {
        switch settings.mode {
        case .all:
            return MeetingSystemAudioSourcePreflightResult(settings: settings, warning: nil)
        case .selectedAppsOnly:
            guard !settings.selectedApps.isEmpty else {
                return fallbackResult(reason: "Selected apps only needs at least one app. VoicePen switched Meeting system audio to All system audio for this recording.")
            }
            let selectedBundleIdentifiers = Set(settings.bundleIdentifiers)
            guard !selectedBundleIdentifiers.isDisjoint(with: runningBundleIdentifiers) else {
                return fallbackResult(reason: "None of the selected Meeting audio apps are running. VoicePen switched Meeting system audio to All system audio for this recording.")
            }
            return MeetingSystemAudioSourcePreflightResult(settings: settings, warning: nil)
        case .allExceptSelectedApps:
            guard !settings.selectedApps.isEmpty else {
                return fallbackResult(
                    reason: "All except selected apps needs at least one app to exclude. VoicePen switched Meeting system audio to All system audio for this recording.")
            }
            return MeetingSystemAudioSourcePreflightResult(settings: settings, warning: nil)
        }
    }

    private static func fallbackResult(reason: String) -> MeetingSystemAudioSourcePreflightResult {
        MeetingSystemAudioSourcePreflightResult(settings: .all, warning: reason)
    }
}
