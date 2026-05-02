import Foundation

nonisolated struct VoiceTranscriptionUsageStats: Equatable, Sendable {
    static let manualTypingWordsPerMinute = 65.0

    let totalDuration: TimeInterval
    let transcribedSessionCount: Int
    let totalWordCount: Int

    init(
        totalDuration: TimeInterval = 0,
        transcribedSessionCount: Int = 0,
        totalWordCount: Int = 0
    ) {
        self.totalDuration = max(0, totalDuration)
        self.transcribedSessionCount = max(0, transcribedSessionCount)
        self.totalWordCount = max(0, totalWordCount)
    }

    init(entries: [VoiceHistoryEntry]) {
        let countedEntries = entries.filter(Self.shouldCount)
        totalDuration = countedEntries.reduce(0) { total, entry in
            total + (entry.duration ?? 0)
        }
        transcribedSessionCount = countedEntries.count
        totalWordCount = countedEntries.reduce(0) { total, entry in
            total + Self.wordCount(in: entry.bestText)
        }
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

    var readableDurationText: String {
        Self.readableDurationText(for: totalDuration)
    }

    var estimatedManualTypingDuration: TimeInterval {
        (Double(totalWordCount) / Self.manualTypingWordsPerMinute) * 60
    }

    var estimatedTimeSavedDuration: TimeInterval {
        max(0, estimatedManualTypingDuration - totalDuration)
    }

    var readableEstimatedTimeSavedText: String {
        Self.readableDurationText(for: estimatedTimeSavedDuration)
    }

    nonisolated private static func shouldCount(_ entry: VoiceHistoryEntry) -> Bool {
        guard entry.status != .failed else { return false }
        guard let duration = entry.duration, duration > 0 else { return false }

        let bestText = entry.bestText
        return !bestText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated private static func readableDurationText(for duration: TimeInterval) -> String {
        guard duration >= 60 else {
            return duration > 0 ? "Less than 1 minute" : "0 minutes"
        }

        let totalMinutes = Int(duration.rounded(.down)) / 60
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        let parts = [
            Self.formattedComponent(days, singular: "day", plural: "days"),
            Self.formattedComponent(hours, singular: "hour", plural: "hours"),
            Self.formattedComponent(minutes, singular: "minute", plural: "minutes")
        ].compactMap { $0 }

        return parts.isEmpty ? "0 minutes" : parts.joined(separator: " ")
    }

    nonisolated private static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    nonisolated private static func format(_ value: Double, unit: String) -> String {
        let formattedValue = value >= 10
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return "\(formattedValue) \(unit)"
    }

    nonisolated private static func formattedComponent(
        _ value: Int,
        singular: String,
        plural: String
    ) -> String? {
        guard value > 0 else { return nil }
        return "\(value) \(value == 1 ? singular : plural)"
    }
}
