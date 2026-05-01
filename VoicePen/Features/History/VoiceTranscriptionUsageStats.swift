import Foundation

nonisolated struct VoiceTranscriptionUsageStats: Equatable, Sendable {
    let totalDuration: TimeInterval
    let transcribedSessionCount: Int

    init(totalDuration: TimeInterval = 0, transcribedSessionCount: Int = 0) {
        self.totalDuration = max(0, totalDuration)
        self.transcribedSessionCount = max(0, transcribedSessionCount)
    }

    init(entries: [VoiceHistoryEntry]) {
        let countedEntries = entries.filter(Self.shouldCount)
        totalDuration = countedEntries.reduce(0) { total, entry in
            total + (entry.duration ?? 0)
        }
        transcribedSessionCount = countedEntries.count
    }

    var totalMinutes: Double {
        totalDuration / 60
    }

    var totalHours: Double {
        totalDuration / 3_600
    }

    var totalDays: Double {
        totalDuration / 86_400
    }

    var primaryDurationText: String {
        switch totalDuration {
        case 86_400...:
            return Self.format(totalDays, unit: "d")
        case 3_600...:
            return Self.format(totalHours, unit: "h")
        case 60...:
            return Self.format(totalMinutes, unit: "min")
        default:
            return Self.format(totalDuration, unit: "s")
        }
    }

    var clockText: String {
        let totalSeconds = Int(totalDuration.rounded(.down))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        return String(format: "%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
    }

    nonisolated private static func shouldCount(_ entry: VoiceHistoryEntry) -> Bool {
        guard entry.status != .failed else { return false }
        guard let duration = entry.duration, duration > 0 else { return false }

        let bestText = entry.finalText.isEmpty ? entry.rawText : entry.finalText
        return !bestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated private static func format(_ value: Double, unit: String) -> String {
        let formattedValue = value >= 10
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formattedValue) \(unit)"
    }
}
