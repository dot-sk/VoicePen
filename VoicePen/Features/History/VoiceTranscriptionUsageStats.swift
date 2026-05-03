import Foundation

nonisolated struct VoiceTranscriptionUsageStats: Equatable, Sendable {
    static let manualTypingWordsPerMinute = 65.0

    let totalDuration: TimeInterval
    let transcribedSessionCount: Int
    let totalWordCount: Int
    let todayWordCount: Int
    let currentStreakDayCount: Int
    let bestDay: VoiceDailyUsageStats?
    let milestones: [VoiceUsageMilestone]

    init(
        totalDuration: TimeInterval = 0,
        transcribedSessionCount: Int = 0,
        totalWordCount: Int = 0,
        todayWordCount: Int = 0,
        currentStreakDayCount: Int = 0,
        bestDay: VoiceDailyUsageStats? = nil
    ) {
        self.totalDuration = max(0, totalDuration)
        self.transcribedSessionCount = max(0, transcribedSessionCount)
        self.totalWordCount = max(0, totalWordCount)
        self.todayWordCount = max(0, todayWordCount)
        self.currentStreakDayCount = max(0, currentStreakDayCount)
        self.bestDay = bestDay
        self.milestones = Self.milestones(
            transcribedSessionCount: self.transcribedSessionCount,
            totalWordCount: self.totalWordCount,
            estimatedTimeSavedDuration: Self.estimatedTimeSavedDuration(
                totalWordCount: self.totalWordCount,
                totalDuration: self.totalDuration
            )
        )
    }

    init(entries: [VoiceHistoryEntry], now: Date = Date(), calendar: Calendar = .current) {
        let countedEntries = entries.filter(Self.shouldCount)
        totalDuration = countedEntries.reduce(0) { total, entry in
            total + (entry.duration ?? 0)
        }
        transcribedSessionCount = countedEntries.count
        totalWordCount = countedEntries.reduce(0) { total, entry in
            total + entry.usageWordCount
        }
        let dailyWordCounts = Self.dailyWordCounts(from: countedEntries, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        todayWordCount = dailyWordCounts[today] ?? 0
        currentStreakDayCount = Self.currentStreakDayCount(
            activeDays: Set(dailyWordCounts.keys),
            today: today,
            calendar: calendar
        )
        bestDay = Self.bestDay(from: dailyWordCounts)
        milestones = Self.milestones(
            transcribedSessionCount: transcribedSessionCount,
            totalWordCount: totalWordCount,
            estimatedTimeSavedDuration: Self.estimatedTimeSavedDuration(
                totalWordCount: totalWordCount,
                totalDuration: totalDuration
            )
        )
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
        Self.estimatedTimeSavedDuration(
            totalWordCount: totalWordCount,
            totalDuration: totalDuration
        )
    }

    var readableEstimatedTimeSavedText: String {
        Self.readableDurationText(for: estimatedTimeSavedDuration)
    }

    var unlockedMilestoneCount: Int {
        milestones.filter(\.isUnlocked).count
    }

    var nextMilestone: VoiceUsageMilestone? {
        milestones.first { !$0.isUnlocked }
    }

    var latestReachedMilestone: VoiceUsageMilestone? {
        milestones.last { $0.isUnlocked }
    }

    var reachedMilestoneText: String {
        guard let latestReachedMilestone else { return "Reached: none yet" }
        return "Reached: \(latestReachedMilestone.title)"
    }

    var nextMilestoneText: String {
        guard let nextMilestone else { return "All milestones unlocked" }
        return "Next: \(nextMilestone.title)"
    }

    nonisolated private static func shouldCount(_ entry: VoiceHistoryEntry) -> Bool {
        guard entry.status != .failed else { return false }
        guard let duration = entry.duration, duration > 0 else { return false }
        return true
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

    nonisolated private static func format(_ value: Double, unit: String) -> String {
        let formattedValue =
            value >= 10
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

    nonisolated private static func estimatedTimeSavedDuration(
        totalWordCount: Int,
        totalDuration: TimeInterval
    ) -> TimeInterval {
        let estimatedManualTypingDuration =
            (Double(totalWordCount) / Self.manualTypingWordsPerMinute) * 60
        return max(0, estimatedManualTypingDuration - totalDuration)
    }

    private static func dailyWordCounts(
        from entries: [VoiceHistoryEntry],
        calendar: Calendar
    ) -> [Date: Int] {
        entries.reduce(into: [:]) { result, entry in
            let day = calendar.startOfDay(for: entry.createdAt)
            result[day, default: 0] += entry.usageWordCount
        }
    }

    private static func currentStreakDayCount(
        activeDays: Set<Date>,
        today: Date,
        calendar: Calendar
    ) -> Int {
        let startDay =
            activeDays.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var day = startDay
        var count = 0

        while activeDays.contains(day) {
            count += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = previousDay
        }

        return count
    }

    private static func bestDay(from dailyWordCounts: [Date: Int]) -> VoiceDailyUsageStats? {
        dailyWordCounts
            .map { VoiceDailyUsageStats(date: $0.key, wordCount: $0.value) }
            .filter { $0.wordCount > 0 }
            .max {
                if $0.wordCount == $1.wordCount {
                    return $0.date < $1.date
                }
                return $0.wordCount < $1.wordCount
            }
    }

    private static func milestones(
        transcribedSessionCount: Int,
        totalWordCount: Int,
        estimatedTimeSavedDuration: TimeInterval
    ) -> [VoiceUsageMilestone] {
        [
            VoiceUsageMilestone(
                title: "First dictation",
                currentValue: transcribedSessionCount,
                targetValue: 1,
                unit: "session"
            ),
            VoiceUsageMilestone(
                title: "10 dictations",
                currentValue: transcribedSessionCount,
                targetValue: 10,
                unit: "sessions"
            ),
            VoiceUsageMilestone(
                title: "1,000 words",
                currentValue: totalWordCount,
                targetValue: 1_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "1 hour saved",
                currentValue: Int(estimatedTimeSavedDuration.rounded(.down)),
                targetValue: 3_600,
                unit: "seconds"
            )
        ]
    }
}

nonisolated struct VoiceDailyUsageStats: Equatable, Sendable {
    var date: Date
    var wordCount: Int
}

nonisolated struct VoiceUsageMilestone: Equatable, Identifiable, Sendable {
    var title: String
    var currentValue: Int
    var targetValue: Int
    var unit: String

    var id: String { title }

    var isUnlocked: Bool {
        currentValue >= targetValue
    }

    var progress: Double {
        guard targetValue > 0 else { return 1 }
        return min(1, max(0, Double(currentValue) / Double(targetValue)))
    }

    var remainingValue: Int {
        max(0, targetValue - currentValue)
    }
}
