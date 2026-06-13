import Foundation

nonisolated struct VoiceTranscriptionUsageStats: Equatable, Sendable {
    static let manualTypingWordsPerMinute = 65.0

    let totalDuration: TimeInterval
    let transcribedSessionCount: Int
    let totalWordCount: Int
    let todayWordCount: Int
    let currentStreakDayCount: Int
    let bestStreakDayCount: Int
    let bestDay: VoiceDailyUsageStats?
    let week: VoiceWeeklyUsageStats
    let milestones: [VoiceUsageMilestone]

    init(
        totalDuration: TimeInterval = 0,
        transcribedSessionCount: Int = 0,
        totalWordCount: Int = 0,
        todayWordCount: Int = 0,
        currentStreakDayCount: Int = 0,
        bestStreakDayCount: Int? = nil,
        bestDay: VoiceDailyUsageStats? = nil,
        week: VoiceWeeklyUsageStats = .empty
    ) {
        self.totalDuration = max(0, totalDuration)
        self.transcribedSessionCount = max(0, transcribedSessionCount)
        self.totalWordCount = max(0, totalWordCount)
        self.todayWordCount = max(0, todayWordCount)
        self.currentStreakDayCount = max(0, currentStreakDayCount)
        self.bestStreakDayCount = max(0, bestStreakDayCount ?? currentStreakDayCount)
        self.bestDay = bestDay
        self.week = week
        self.milestones = Self.milestones(
            transcribedSessionCount: self.transcribedSessionCount,
            totalWordCount: self.totalWordCount,
            currentStreakDayCount: self.currentStreakDayCount,
            bestDayWordCount: self.bestDay?.wordCount ?? 0,
            estimatedTimeSavedDuration: Self.estimatedTimeSavedDuration(
                totalWordCount: self.totalWordCount
            )
        )
    }

    init(entries: [VoiceHistoryEntry], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let weekStartDate = Self.weekStart(containing: now, calendar: calendar)
        let usage = Self.aggregateUsage(
            from: entries,
            weekStartDate: weekStartDate,
            calendar: calendar
        )

        totalDuration = usage.totalDuration
        transcribedSessionCount = usage.transcribedSessionCount
        totalWordCount = usage.totalWordCount
        todayWordCount = usage.dailyUsageTotals[today]?.wordCount ?? 0
        bestDay = usage.bestDay

        let dailyUsageTotals = usage.dailyUsageTotals
        let activeDays = Set(dailyUsageTotals.keys)
        currentStreakDayCount = Self.currentStreakDayCount(
            activeDays: activeDays,
            today: today,
            calendar: calendar
        )
        bestStreakDayCount = Self.bestStreakDayCount(
            activeDays: activeDays,
            calendar: calendar
        )
        week = Self.weeklyUsageStats(
            dailyUsageTotals: dailyUsageTotals,
            hourlyActivity: usage.weeklyHourlyActivity,
            startDate: weekStartDate,
            calendar: calendar
        )
        milestones = Self.milestones(
            transcribedSessionCount: transcribedSessionCount,
            totalWordCount: totalWordCount,
            currentStreakDayCount: currentStreakDayCount,
            bestDayWordCount: bestDay?.wordCount ?? 0,
            estimatedTimeSavedDuration: Self.estimatedTimeSavedDuration(
                totalWordCount: totalWordCount
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
            totalWordCount: totalWordCount
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
        totalWordCount: Int
    ) -> TimeInterval {
        max(0, (Double(totalWordCount) / Self.manualTypingWordsPerMinute) * 60)
    }

    private static func aggregateUsage(
        from entries: [VoiceHistoryEntry],
        weekStartDate: Date,
        calendar: Calendar
    ) -> UsageAggregation {
        var aggregation = UsageAggregation()
        var weeklyHourlyActivity = emptyHourlyActivity()

        entries.forEach { entry in
            guard shouldCount(entry) else { return }

            aggregation.transcribedSessionCount += 1
            aggregation.totalDuration += entry.duration ?? 0
            aggregation.totalWordCount += entry.usageWordCount

            let day = calendar.startOfDay(for: entry.createdAt)
            aggregation.dailyUsageTotals[day, default: DailyUsageTotals()].add(entry)

            let dayWordCount = aggregation.dailyUsageTotals[day]?.wordCount ?? 0
            if dayWordCount > 0 {
                if let bestDay = aggregation.bestDay {
                    if dayWordCount > bestDay.wordCount
                        || (dayWordCount == bestDay.wordCount && day > bestDay.date)
                    {
                        aggregation.bestDay = VoiceDailyUsageStats(date: day, wordCount: dayWordCount)
                    }
                } else {
                    aggregation.bestDay = VoiceDailyUsageStats(date: day, wordCount: dayWordCount)
                }
            }

            guard let weekdayOffset = calendar.dateComponents([.day], from: weekStartDate, to: day).day,
                (0..<7).contains(weekdayOffset)
            else { return }

            let hour = calendar.component(.hour, from: entry.createdAt)
            let index = (weekdayOffset * 24) + hour
            let current = weeklyHourlyActivity[index]
            weeklyHourlyActivity[index] = VoiceHourlyActivityStats(
                weekdayIndex: weekdayOffset,
                hour: hour,
                sessionCount: current.sessionCount + 1,
                wordCount: current.wordCount + entry.usageWordCount,
                audioDuration: current.audioDuration + (entry.duration ?? 0)
            )
        }

        aggregation.weeklyHourlyActivity = weeklyHourlyActivity
        return aggregation
    }

    private static func weeklyUsageStats(
        dailyUsageTotals: [Date: DailyUsageTotals],
        hourlyActivity: [VoiceHourlyActivityStats],
        startDate: Date,
        calendar: Calendar
    ) -> VoiceWeeklyUsageStats {
        let days: [VoiceDailySavedTimeStats] = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: startDate) ?? startDate
            let day = calendar.startOfDay(for: date)
            let totals = dailyUsageTotals[day] ?? DailyUsageTotals()
            return VoiceDailySavedTimeStats(
                date: day,
                weekdayIndex: offset,
                wordCount: totals.wordCount,
                sessionCount: totals.sessionCount,
                audioDuration: totals.duration,
                estimatedTimeSavedDuration: estimatedTimeSavedDuration(
                    totalWordCount: totals.wordCount
                )
            )
        }
        let weekTotals = days.reduce(into: DailyUsageTotals()) { result, day in
            result.wordCount += day.wordCount
            result.sessionCount += day.sessionCount
            result.duration += day.audioDuration
        }

        return VoiceWeeklyUsageStats(
            startDate: startDate,
            days: days,
            hourlyActivity: hourlyActivity,
            wordCount: weekTotals.wordCount,
            sessionCount: weekTotals.sessionCount,
            audioDuration: weekTotals.duration,
            estimatedTimeSavedDuration: estimatedTimeSavedDuration(
                totalWordCount: weekTotals.wordCount
            )
        )
    }

    private static func emptyHourlyActivity() -> [VoiceHourlyActivityStats] {
        (0..<7).flatMap { weekdayIndex in
            (0..<24).map { hour in
                VoiceHourlyActivityStats(
                    weekdayIndex: weekdayIndex,
                    hour: hour,
                    sessionCount: 0,
                    wordCount: 0,
                    audioDuration: 0
                )
            }
        }
    }

    private static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
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

    private static func bestStreakDayCount(
        activeDays: Set<Date>,
        calendar: Calendar
    ) -> Int {
        var previousDay: Date?
        var currentCount = 0
        var bestCount = 0

        for day in activeDays.sorted() {
            if let previousDay,
                let nextDay = calendar.date(byAdding: .day, value: 1, to: previousDay),
                calendar.isDate(nextDay, inSameDayAs: day)
            {
                currentCount += 1
            } else {
                currentCount = 1
            }

            bestCount = max(bestCount, currentCount)
            previousDay = day
        }

        return bestCount
    }

    private struct DailyUsageTotals {
        var wordCount = 0
        var sessionCount = 0
        var duration: TimeInterval = 0

        mutating func add(_ entry: VoiceHistoryEntry) {
            wordCount += entry.usageWordCount
            sessionCount += 1
            duration += entry.duration ?? 0
        }
    }

    private struct UsageAggregation {
        var totalDuration: TimeInterval = 0
        var transcribedSessionCount = 0
        var totalWordCount = 0
        var dailyUsageTotals: [Date: DailyUsageTotals] = [:]
        var weeklyHourlyActivity: [VoiceHourlyActivityStats] = []
        var bestDay: VoiceDailyUsageStats?
    }

    private static func milestones(
        transcribedSessionCount: Int,
        totalWordCount: Int,
        currentStreakDayCount: Int,
        bestDayWordCount: Int,
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
                title: "100 words",
                currentValue: totalWordCount,
                targetValue: 100,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "1,000 words",
                currentValue: totalWordCount,
                targetValue: 1_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "10 dictations",
                currentValue: transcribedSessionCount,
                targetValue: 10,
                unit: "sessions"
            ),
            VoiceUsageMilestone(
                title: "3-day streak",
                currentValue: currentStreakDayCount,
                targetValue: 3,
                unit: "days"
            ),
            VoiceUsageMilestone(
                title: "1,500-word day",
                currentValue: bestDayWordCount,
                targetValue: 1_500,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "5,000 words",
                currentValue: totalWordCount,
                targetValue: 5_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "7-day streak",
                currentValue: currentStreakDayCount,
                targetValue: 7,
                unit: "days"
            ),
            VoiceUsageMilestone(
                title: "1 hour avoided",
                currentValue: Int(estimatedTimeSavedDuration.rounded(.down)),
                targetValue: 3_600,
                unit: "seconds"
            ),
            VoiceUsageMilestone(
                title: "25,000 words",
                currentValue: totalWordCount,
                targetValue: 25_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "5,000-word day",
                currentValue: bestDayWordCount,
                targetValue: 5_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "14-day streak",
                currentValue: currentStreakDayCount,
                targetValue: 14,
                unit: "days"
            ),
            VoiceUsageMilestone(
                title: "10 hours avoided",
                currentValue: Int(estimatedTimeSavedDuration.rounded(.down)),
                targetValue: 36_000,
                unit: "seconds"
            ),
            VoiceUsageMilestone(
                title: "100,000 words",
                currentValue: totalWordCount,
                targetValue: 100_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "30-day streak",
                currentValue: currentStreakDayCount,
                targetValue: 30,
                unit: "days"
            ),
            VoiceUsageMilestone(
                title: "250,000 words",
                currentValue: totalWordCount,
                targetValue: 250_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "10,000-word day",
                currentValue: bestDayWordCount,
                targetValue: 10_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "50 hours avoided",
                currentValue: Int(estimatedTimeSavedDuration.rounded(.down)),
                targetValue: 180_000,
                unit: "seconds"
            ),
            VoiceUsageMilestone(
                title: "500,000 words",
                currentValue: totalWordCount,
                targetValue: 500_000,
                unit: "words"
            ),
            VoiceUsageMilestone(
                title: "100-day streak",
                currentValue: currentStreakDayCount,
                targetValue: 100,
                unit: "days"
            ),
            VoiceUsageMilestone(
                title: "1,000,000 words",
                currentValue: totalWordCount,
                targetValue: 1_000_000,
                unit: "words"
            )
        ]
    }
}

nonisolated struct VoiceWeeklyUsageStats: Equatable, Sendable {
    static let empty = VoiceWeeklyUsageStats(
        startDate: Date(timeIntervalSince1970: 0),
        days: (0..<7).map { offset in
            VoiceDailySavedTimeStats(
                date: Date(timeIntervalSince1970: Double(offset) * 86_400),
                weekdayIndex: offset,
                wordCount: 0,
                sessionCount: 0,
                audioDuration: 0,
                estimatedTimeSavedDuration: 0
            )
        },
        hourlyActivity: (0..<7).flatMap { weekday in
            (0..<24).map { hour in
                VoiceHourlyActivityStats(
                    weekdayIndex: weekday,
                    hour: hour,
                    sessionCount: 0,
                    wordCount: 0,
                    audioDuration: 0
                )
            }
        },
        wordCount: 0,
        sessionCount: 0,
        audioDuration: 0,
        estimatedTimeSavedDuration: 0
    )

    let startDate: Date
    let days: [VoiceDailySavedTimeStats]
    let hourlyActivity: [VoiceHourlyActivityStats]
    let wordCount: Int
    let sessionCount: Int
    let audioDuration: TimeInterval
    let estimatedTimeSavedDuration: TimeInterval

    var activeDayCount: Int {
        days.filter(\.isActive).count
    }

    var bestSavedTimeDay: VoiceDailySavedTimeStats? {
        days
            .filter { $0.estimatedTimeSavedDuration > 0 }
            .max {
                if $0.estimatedTimeSavedDuration == $1.estimatedTimeSavedDuration {
                    return $0.date < $1.date
                }
                return $0.estimatedTimeSavedDuration < $1.estimatedTimeSavedDuration
            }
    }
}

nonisolated struct VoiceHourlyActivityStats: Equatable, Identifiable, Sendable {
    var weekdayIndex: Int
    var hour: Int
    var sessionCount: Int
    var wordCount: Int
    var audioDuration: TimeInterval

    var id: String {
        "\(weekdayIndex)-\(hour)"
    }
}

nonisolated struct VoiceDailySavedTimeStats: Equatable, Identifiable, Sendable {
    var date: Date
    var weekdayIndex: Int
    var wordCount: Int
    var sessionCount: Int
    var audioDuration: TimeInterval
    var estimatedTimeSavedDuration: TimeInterval

    var id: Date { date }

    var isActive: Bool {
        sessionCount > 0
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
