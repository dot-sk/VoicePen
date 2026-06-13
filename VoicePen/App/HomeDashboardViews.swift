import Foundation
import SwiftUI

struct HomeDashboardView: View {
    let stats: HomeDashboardStats
    let appState: AppState
    let pushToTalkHint: String
    let statusAction: HomeStatusAction?
    let performStatusAction: (VoicePenSettingsSection) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private let dashboardGap: CGFloat = 16
    private let metricCardHeight: CGFloat = 132
    private let metricGridGap: CGFloat = 16
    private let metricGridWidth: CGFloat = 520
    private let analyticsRowHeight: CGFloat = 320

    private var theme: StatsTheme {
        StatsTheme.resolve(colorScheme)
    }

    private var topRowHeight: CGFloat {
        (metricCardHeight * 2) + metricGridGap
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(0, min(proxy.size.width, 1_260) - 68)
            let usesCompactLayout = contentWidth < 980

            ScrollView {
                dashboardContent(usesCompactLayout: usesCompactLayout)
                    .padding(.horizontal, 34)
                    .padding(.top, 22)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 1_260)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(theme.background)
    }

    private func dashboardContent(usesCompactLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: dashboardGap) {
            HomeStatusStrip(
                appState: appState,
                pushToTalkHint: pushToTalkHint,
                action: statusAction,
                performAction: performStatusAction,
                theme: theme
            )

            topDashboardRow(usesCompactLayout: usesCompactLayout)

            analyticsDashboardRow(usesCompactLayout: usesCompactLayout)

            MilestoneCard(
                milestone: stats.nextMilestone,
                theme: theme
            )
        }
    }

    @ViewBuilder
    private func topDashboardRow(usesCompactLayout: Bool) -> some View {
        if usesCompactLayout {
            VStack(alignment: .leading, spacing: dashboardGap) {
                WeeklyHeroCard(stats: stats, theme: theme)
                    .frame(maxWidth: .infinity)
                    .frame(height: topRowHeight)
                metricGrid(columns: 2, theme: theme)
                    .frame(height: topRowHeight)
            }
        } else {
            HStack(alignment: .top, spacing: dashboardGap) {
                WeeklyHeroCard(stats: stats, theme: theme)
                    .frame(maxWidth: .infinity)
                    .frame(height: topRowHeight)

                metricGrid(columns: 2, theme: theme)
                    .frame(width: metricGridWidth)
                    .frame(height: topRowHeight)
            }
        }
    }

    @ViewBuilder
    private func analyticsDashboardRow(usesCompactLayout: Bool) -> some View {
        if usesCompactLayout {
            VStack(alignment: .leading, spacing: dashboardGap) {
                DailyTypingAvoidedChart(
                    model: stats.dailyChartModel,
                    theme: theme
                )
                .frame(height: analyticsRowHeight)

                ActivityHeatmap(
                    model: stats.activityHeatmapModel,
                    theme: theme
                )
                .frame(height: analyticsRowHeight)
            }
        } else {
            HStack(alignment: .top, spacing: dashboardGap) {
                DailyTypingAvoidedChart(
                    model: stats.dailyChartModel,
                    theme: theme
                )
                .frame(maxWidth: .infinity)
                .frame(height: analyticsRowHeight)

                ActivityHeatmap(
                    model: stats.activityHeatmapModel,
                    theme: theme
                )
                .frame(maxWidth: .infinity)
                .frame(height: analyticsRowHeight)
            }
        }
    }

    private func metricGrid(columns columnCount: Int, theme: StatsTheme) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 184), spacing: metricGridGap),
                count: columnCount
            ),
            spacing: metricGridGap
        ) {
            metricCards(theme: theme)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func metricCards(theme: StatsTheme) -> some View {
        HomeMetricCard(
            title: "Words transcribed",
            value: HomeDashboardFormatting.wordCount(stats.weekWordCount),
            caption: "This week",
            symbol: "text.bubble",
            accent: theme.blue,
            progress: stats.weekWordProgress,
            secondaryValue: "\(stats.weekSessionCount.formatted()) sessions"
        )
        .frame(height: metricCardHeight)
        HomeMetricCard(
            title: "Spoken audio",
            value: HomeDashboardFormatting.compactClock(stats.weekAudioDuration),
            caption: "This week",
            symbol: "waveform",
            accent: theme.green,
            progress: stats.weekAudioProgress
        )
        .frame(height: metricCardHeight)
        HomeMetricCard(
            title: "Active days",
            value: HomeDashboardFormatting.cardCount(stats.weekActiveDayCount),
            caption: "Current streak \(HomeDashboardFormatting.cardCount(stats.currentStreakDayCount))",
            symbol: "calendar.badge.clock",
            accent: theme.purple,
            progress: Double(stats.weekActiveDayCount) / 7,
            miniSegments: MetricMiniSegments(filled: stats.weekActiveDayCount, total: 7),
            secondaryValue: "Best \(HomeDashboardFormatting.cardCount(stats.bestStreakDayCount)) days"
        )
        .frame(height: metricCardHeight)
        HomeMetricCard(
            title: "Streak",
            value: HomeDashboardFormatting.countWithUnit(stats.currentStreakDayCount, singular: "day"),
            caption: "Current / best",
            symbol: "flame",
            accent: theme.orange,
            progress: stats.streakProgress,
            secondaryValue:
                "\(HomeDashboardFormatting.cardCount(stats.currentStreakDayCount)) / \(HomeDashboardFormatting.cardCount(stats.bestStreakDayCount))"
        )
        .frame(height: metricCardHeight)
    }
}

struct HomeStatusAction {
    let title: String
    let destination: VoicePenSettingsSection
}

private struct HomeStatusStrip: View {
    let appState: AppState
    let pushToTalkHint: String
    let action: HomeStatusAction?
    let performAction: (VoicePenSettingsSection) -> Void
    let theme: StatsTheme

    private var level: HomeStatusLevel {
        switch appState {
        case .ready:
            return .ready
        case .missingMicrophonePermission, .error:
            return .notReady
        case .starting, .meetingRecording, .meetingProcessing,
            .downloadingModel, .preparingModel, .missingAccessibilityPermission,
            .missingSystemAudioPermission, .missingModel:
            return .actionRequired
        }
    }

    private var statusText: String {
        switch appState {
        case .ready:
            return "Ready · Push-to-talk \(pushToTalkHint) · Meeting recording ⌘R"
        case .missingMicrophonePermission:
            return "Not ready · Microphone permission missing"
        case .missingAccessibilityPermission:
            return "Action required · Accessibility permission missing"
        case .missingSystemAudioPermission:
            return "Action required · System audio permission missing"
        case .missingModel:
            return "Action required · Model missing"
        case let .error(message):
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedMessage.isEmpty ? "Not ready · Error" : "Not ready · \(trimmedMessage)"
        default:
            return appState.menuTitle
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(level.color)
                .frame(width: 11, height: 11)
                .accessibilityHidden(true)

            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
                .accessibilityValue(statusText)

            Spacer(minLength: 0)

            if let action {
                Button(action.title) {
                    performAction(action.destination)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(theme.blue)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .liquidGlassCapsule(theme: theme, tint: theme.blue)
    }
}

private enum HomeStatusLevel {
    case ready
    case actionRequired
    case notReady

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .actionRequired:
            return .orange
        case .notReady:
            return .red
        }
    }
}

private enum StatsTypography {
    static let panelLabel = Font.system(size: 12, weight: .semibold, design: .default)
    static let heroLabel = Font.system(size: 16, weight: .bold, design: .default)
    static let heroValue = Font.system(size: 54, weight: .bold, design: .default)
    static let heroSubtitle = Font.system(size: 14, weight: .medium, design: .default)
    static let metricLabel = Font.system(size: 12, weight: .semibold, design: .default)
    static let metricValue = Font.system(size: 26, weight: .bold, design: .default)
    static let body = Font.system(size: 14, weight: .regular, design: .default)
    static let small = Font.system(size: 13, weight: .medium, design: .default)
    static let smallStrong = Font.system(size: 13, weight: .semibold, design: .default)
    static let tiny = Font.system(size: 11, weight: .medium, design: .default)
    static let axis = Font.system(size: 10, weight: .medium, design: .default)

    static let labelTracking: CGFloat = 0.8
    static let metricLabelTracking: CGFloat = 0.7
    static let smallTracking: CGFloat = 0.3
}

struct HomeDashboardStats: Equatable {
    let week: VoiceWeeklyUsageStats
    let weekStartDate: Date
    let weekWordCount: Int
    let weekSessionCount: Int
    let weekAudioDuration: TimeInterval
    let weekEstimatedTimeSavedDuration: TimeInterval
    let weekActiveDayCount: Int
    let currentStreakDayCount: Int
    let bestStreakDayCount: Int
    let nextMilestone: VoiceUsageMilestone?
    let weeklyDays: [VoiceDailySavedTimeStats]
    let hourlyActivity: [HomeHourlyActivityStats]
    fileprivate let dailyChartModel: DailyTypingAvoidedChartModel
    fileprivate let activityHeatmapModel: ActivityHeatmapModel

    init(stats: VoiceTranscriptionUsageStats) {
        week = stats.week
        weekStartDate = week.startDate
        weekWordCount = stats.week.wordCount
        weekSessionCount = stats.week.sessionCount
        weekAudioDuration = stats.week.audioDuration
        weekEstimatedTimeSavedDuration = stats.week.estimatedTimeSavedDuration
        weekActiveDayCount = stats.week.activeDayCount
        currentStreakDayCount = stats.currentStreakDayCount
        bestStreakDayCount = stats.bestStreakDayCount
        nextMilestone = stats.nextMilestone
        weeklyDays = Self.completeWeek(
            from: stats.week.days,
            startDate: stats.week.startDate
        )
        hourlyActivity = Self.makeHourlyActivity(from: stats.week)
        dailyChartModel = DailyTypingAvoidedChartModel(days: weeklyDays, weekStartDate: weekStartDate)
        activityHeatmapModel = ActivityHeatmapModel(hourlyActivity: hourlyActivity)
    }

    init(
        week: VoiceWeeklyUsageStats,
        weekStartDate: Date? = nil,
        nextMilestone: VoiceUsageMilestone?,
        currentStreakDayCount: Int,
        bestStreakDayCount: Int,
        hourlyActivity: [HomeHourlyActivityStats]
    ) {
        self.week = week
        self.weekStartDate = weekStartDate ?? week.startDate
        weekWordCount = week.wordCount
        weekSessionCount = week.sessionCount
        weekAudioDuration = week.audioDuration
        weekEstimatedTimeSavedDuration = week.estimatedTimeSavedDuration
        weekActiveDayCount = week.activeDayCount
        self.currentStreakDayCount = currentStreakDayCount
        self.bestStreakDayCount = bestStreakDayCount
        self.nextMilestone = nextMilestone
        weeklyDays = Self.completeWeek(from: week.days, startDate: self.weekStartDate)
        self.hourlyActivity = hourlyActivity
        dailyChartModel = DailyTypingAvoidedChartModel(days: weeklyDays, weekStartDate: self.weekStartDate)
        activityHeatmapModel = ActivityHeatmapModel(hourlyActivity: hourlyActivity)
    }

    var hasWeekActivity: Bool {
        weekEstimatedTimeSavedDuration > 0 || weekSessionCount > 0 || weekWordCount > 0
    }

    var weekWordProgress: Double {
        guard weekWordCount > 0 else { return 0 }
        return min(1, Double(weekWordCount) / 5_000)
    }

    var weekAudioProgress: Double {
        guard weekAudioDuration > 0 else { return 0 }
        return min(1, weekAudioDuration / 3_600)
    }

    var streakProgress: Double {
        guard bestStreakDayCount > 0 else { return 0 }
        return min(1, Double(currentStreakDayCount) / Double(bestStreakDayCount))
    }

    var weekRangeLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: week.startDate) ?? week.startDate
        let dateRange = HomeDashboardDateRangeFormatter.weekRangeText(from: week.startDate, to: end)
        return "Mon-Sun - \(dateRange)"
    }

    var weekTotalSavedTime: TimeInterval {
        weekEstimatedTimeSavedDuration
    }

    var bestDay: VoiceDailySavedTimeStats? {
        weeklyDays.max {
            if $0.estimatedTimeSavedDuration == $1.estimatedTimeSavedDuration {
                return $0.date < $1.date
            }
            return $0.estimatedTimeSavedDuration < $1.estimatedTimeSavedDuration
        }
    }

    static func makeHourlyActivity(from week: VoiceWeeklyUsageStats) -> [HomeHourlyActivityStats] {
        HomeHourlyActivityStats.fillMatrix(from: week.hourlyActivity.map(HomeHourlyActivityStats.init(from:)))
    }

    private static func completeWeek(
        from days: [VoiceDailySavedTimeStats],
        startDate: Date
    ) -> [VoiceDailySavedTimeStats] {
        var byWeekday: [Int: VoiceDailySavedTimeStats] = [:]
        days.forEach { day in
            byWeekday[day.weekdayIndex] = day
        }

        let calendar = Calendar.current
        return (0..<7).map { weekday in
            if let day = byWeekday[weekday] {
                return day
            }
            return Self.makeWeeklyDay(
                date: calendar.date(byAdding: .day, value: weekday, to: startDate) ?? startDate,
                weekdayIndex: weekday,
                words: 0,
                sessions: 0,
                audio: 0,
                estimatedSeconds: 0
            )
        }
    }
}

struct HomeHourlyActivityStats: Identifiable, Equatable {
    let weekdayIndex: Int
    let hour: Int
    let sessionCount: Int
    let wordCount: Int
    let audioDuration: TimeInterval

    var id: Int { weekdayIndex * 24 + hour }

    init(
        weekdayIndex: Int,
        hour: Int,
        sessionCount: Int,
        wordCount: Int,
        audioDuration: TimeInterval
    ) {
        self.weekdayIndex = weekdayIndex
        self.hour = hour
        self.sessionCount = sessionCount
        self.wordCount = wordCount
        self.audioDuration = audioDuration
    }

    init(from source: VoiceHourlyActivityStats) {
        weekdayIndex = source.weekdayIndex
        hour = source.hour
        sessionCount = source.sessionCount
        wordCount = source.wordCount
        audioDuration = source.audioDuration
    }

    func voiceHourlyActivity() -> VoiceHourlyActivityStats {
        VoiceHourlyActivityStats(
            weekdayIndex: weekdayIndex,
            hour: hour,
            sessionCount: sessionCount,
            wordCount: wordCount,
            audioDuration: audioDuration
        )
    }

    static func fillMatrix(from source: [HomeHourlyActivityStats]) -> [HomeHourlyActivityStats] {
        var byHour: [Int: HomeHourlyActivityStats] = [:]
        source.forEach { bucket in
            byHour[bucket.id] = bucket
        }

        return (0..<7).flatMap { weekday in
            (0..<24).compactMap { hour in
                byHour[weekday * 24 + hour]
                    ?? HomeHourlyActivityStats(
                        weekdayIndex: weekday,
                        hour: hour,
                        sessionCount: 0,
                        wordCount: 0,
                        audioDuration: 0
                    )
            }
        }
    }

    static func zeroMatrix() -> [HomeHourlyActivityStats] {
        fillMatrix(from: [])
    }
}

private struct WeeklyHeroCard: View {
    let stats: HomeDashboardStats
    let theme: StatsTheme

    private var heroValue: String {
        if stats.hasWeekActivity {
            return "≈ \(HomeDashboardFormatting.savedTime(stats.weekEstimatedTimeSavedDuration))"
        }
        return "≈ 0 min"
    }

    private var heroSubtitle: String {
        let word = HomeDashboardFormatting.plural("word", count: stats.weekWordCount)
        let wpm = Int(VoiceTranscriptionUsageStats.manualTypingWordsPerMinute)
        return "Based on \(stats.weekWordCount.formatted()) \(word) at ~\(wpm) WPM"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            ParticleWaveBackground(theme: theme)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Weekly typing avoided")
                        .font(StatsTypography.panelLabel)
                        .tracking(StatsTypography.labelTracking)
                        .foregroundStyle(theme.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(stats.weekRangeLabel)
                        .font(StatsTypography.smallStrong)
                        .tracking(StatsTypography.smallTracking)
                        .foregroundStyle(theme.textTertiary)
                        .monospacedDigit()
                }

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 8) {
                    Text(heroValue)
                        .font(StatsTypography.heroValue)
                        .foregroundStyle(theme.heroText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .shadow(color: theme.heroGlow, radius: 24, x: 0, y: 8)
                        .monospacedDigit()
                        .accessibilityValue(heroValue)

                    Text(stats.hasWeekActivity ? "Typing avoided" : "No activity this week")
                        .font(StatsTypography.heroLabel)
                        .tracking(StatsTypography.labelTracking)
                        .foregroundStyle(theme.textPrimary)
                        .textCase(.uppercase)

                    Text(heroSubtitle)
                        .font(StatsTypography.heroSubtitle)
                        .foregroundStyle(theme.textTertiary.opacity(theme.isDark ? 0.86 : 0.75))
                        .frame(maxWidth: 420, alignment: .leading)
                        .accessibilityLabel("Typing avoidance estimate")
                }

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    Label("\(stats.weekSessionCount.formatted()) sessions", systemImage: "dot.radiowaves.left.and.right")
                    if let bestDay = stats.bestDay, bestDay.estimatedTimeSavedDuration > 0 {
                        Label("Best day \(stats.bestDayLabel(for: bestDay))", systemImage: "chart.bar.fill")
                    }
                }
                .font(StatsTypography.smallStrong)
                .foregroundStyle(theme.textSecondary)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.heroBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.heroBorder, lineWidth: 1)
                }
                .shadow(color: theme.heroGlow, radius: 28, x: 0, y: 14)
        )
    }
}

private struct ParticleWaveBackground: View {
    let theme: StatsTheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [theme.blue.opacity(theme.isDark ? 0.36 : 0.15), .clear],
                center: .init(x: 0.78, y: 0.42),
                startRadius: 20,
                endRadius: 240
            )

            Canvas { context, size in
                let columns = 18
                let rows = 9
                let cellWidth = size.width / CGFloat(columns)
                let cellHeight = size.height / CGFloat(rows)

                for row in 0..<rows {
                    for column in 0..<columns {
                        let x = CGFloat(column) * cellWidth + cellWidth * 0.5
                        let wave = sin((CGFloat(column) / 2.6) + CGFloat(row) * 0.72)
                        let y = CGFloat(row) * cellHeight + cellHeight * 0.48 + wave * 14
                        let distance = abs(x - size.width * 0.78) / max(1, size.width)
                        let opacity = max(theme.isDark ? 0.05 : 0.05, (theme.isDark ? 0.42 : 0.36) - distance)
                        let radius = max(1.4, 3.8 - CGFloat(row % 3) * 0.42)
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(theme.blue.opacity(opacity))
                        )
                    }
                }
            }
            .blendMode(theme.isDark ? .plusLighter : .normal)
            .opacity(theme.isDark ? 0.74 : 0.40)
        }
    }
}

private struct HomeMetricCard: View {
    private let metricIconBadgeSize: CGFloat = 32
    private let metricIconSize: CGFloat = 16
    private let metricIconCornerRadius: CGFloat = 9

    let title: String
    let value: String
    let caption: String
    let symbol: String
    let accent: Color
    let progress: Double
    let miniSegments: MetricMiniSegments?
    let secondaryValue: String?

    init(
        title: String,
        value: String,
        caption: String,
        symbol: String,
        accent: Color,
        progress: Double,
        miniSegments: MetricMiniSegments? = nil,
        secondaryValue: String? = nil
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.symbol = symbol
        self.accent = accent
        self.progress = max(0, min(1, progress))
        self.miniSegments = miniSegments
        self.secondaryValue = secondaryValue
    }

    @Environment(\.colorScheme) private var colorScheme

    private var theme: StatsTheme {
        StatsTheme.resolve(colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(accent)
                    .frame(width: metricIconSize, height: metricIconSize)
                    .frame(width: metricIconBadgeSize, height: metricIconBadgeSize)
                    .liquidGlassBadge(theme: theme, tint: accent, cornerRadius: metricIconCornerRadius)

                Text(title)
                    .font(StatsTypography.metricLabel)
                    .tracking(StatsTypography.metricLabelTracking)
                    .foregroundStyle(theme.textSecondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 0)
            }
            .accessibilityHidden(true)

            Text(value)
                .font(StatsTypography.metricValue)
                .foregroundStyle(theme.textPrimary)
                .monospacedDigit()
                .accessibilityLabel(value)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(caption)
                        .font(StatsTypography.small)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let secondaryValue {
                        Text(secondaryValue)
                            .font(StatsTypography.tiny)
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(theme.gridLine)
                        Capsule()
                            .fill(theme.isDark ? accent : accent.opacity(0.82))
                            .frame(width: max(8, proxy.size.width * CGFloat(progress)))
                    }
                }
                .frame(height: 5)

                if let miniSegments {
                    HStack(spacing: 4) {
                        ForEach(0..<miniSegments.total, id: \.self) { index in
                            Circle()
                                .fill(index < miniSegments.filled ? accent : theme.gridLine)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .statsCard(theme: theme)
    }
}

private struct MetricMiniSegments: Equatable {
    let filled: Int
    let total: Int

    init(filled: Int, total: Int) {
        self.filled = max(0, min(filled, total))
        self.total = max(0, total)
    }
}

private struct DailyTypingAvoidedChart: View {
    let model: DailyTypingAvoidedChartModel
    let theme: StatsTheme

    private let chartHeight: CGFloat = 166
    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    init(model: DailyTypingAvoidedChartModel, theme: StatsTheme) {
        self.model = model
        self.theme = theme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chartHeader
            chartBody
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsCard(theme: theme, emphasized: true)
    }

    private var chartHeader: some View {
        HStack {
            Text("Daily typing avoided")
                .font(StatsTypography.panelLabel)
                .tracking(StatsTypography.labelTracking)
                .foregroundStyle(theme.textPrimary)
                .textCase(.uppercase)
            Spacer()
            if let bestDayLabel = model.bestDayLabel {
                Text("Best: \(bestDayLabel)")
                    .font(StatsTypography.small)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .liquidGlassCapsule(theme: theme, tint: theme.blue)
            }
        }
    }

    private var chartBody: some View {
        HStack(alignment: .top, spacing: 12) {
            yAxisLabelColumn

            VStack(spacing: 8) {
                plotArea
                    .frame(height: chartHeight)
                    .accessibilityHidden(true)

                xAxisLabelsAndValues
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily typing avoided chart")
        .accessibilityValue(
            model.hasNoWeekActivity
                ? "No recorded sessions this week"
                : "Peak: \(model.bestDayLabel ?? "none") · Total \(HomeDashboardFormatting.savedTime(model.totalWeekSavedTime))"
        )
    }

    private var yAxisLabelColumn: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(model.yAxisValues.indices, id: \.self) { index in
                Text(model.yAxisValues[index].formatted(.number.precision(.fractionLength(0))))
                    .font(StatsTypography.tiny)
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 34, alignment: .trailing)
                    .offset(y: yAxisLabelOffset(for: index))
            }
        }
        .frame(width: 34, height: chartHeight, alignment: .topTrailing)
    }

    private var plotArea: some View {
        ZStack(alignment: .bottom) {
            gridLines

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(model.orderedDays) { day in
                    let isBest = day.weekdayIndex == model.bestDayIndex
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: isBest
                                        ? (theme.isDark ? [theme.purple, theme.blue] : [theme.blue, theme.purple.opacity(0.68)])
                                        : [theme.blue.opacity(theme.isDark ? 1.0 : 0.82), theme.blue.opacity(theme.isDark ? 0.42 : 0.28)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(
                                width: 28,
                                height: max(day.estimatedTimeSavedDuration > 0 ? 8 : 0, barHeight(for: day)),
                                alignment: .bottom
                            )
                            .shadow(
                                color: isBest ? theme.purple.opacity(theme.isDark ? 0.38 : 0.07) : .clear,
                                radius: theme.isDark ? 12 : 7,
                                x: 0,
                                y: theme.isDark ? 4 : 2
                            )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var gridLines: some View {
        ZStack(alignment: .top) {
            ForEach(0...5, id: \.self) { index in
                Rectangle()
                    .fill(theme.gridLine)
                    .frame(height: 1)
                    .offset(y: gridLineOffset(for: index))
            }
        }
        .frame(height: chartHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var xAxisLabelsAndValues: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(model.orderedDays) { day in
                    Text(dayLabel(for: day.weekdayIndex))
                        .font(StatsTypography.smallStrong)
                        .foregroundStyle(day.weekdayIndex == model.bestDayIndex ? theme.textPrimary : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 0) {
                ForEach(model.orderedDays) { day in
                    VStack(spacing: 3) {
                        Image(systemName: day.isActive ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .semibold, design: .default))
                            .foregroundStyle(day.isActive ? theme.green : theme.textTertiary)
                        Text(HomeDashboardFormatting.savedMinutes(day.estimatedTimeSavedDuration))
                            .font(StatsTypography.axis)
                            .foregroundStyle(day.isActive ? theme.textSecondary : theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func barHeight(for day: VoiceDailySavedTimeStats) -> CGFloat {
        let raw = day.estimatedTimeSavedDuration / 60
        guard model.maxYAxisValue > 0 else { return 0 }
        return CGFloat(raw / model.maxYAxisValue) * chartHeight
    }

    private func dayLabel(for index: Int) -> String {
        let offset = ((index % weekdayLabels.count) + weekdayLabels.count) % weekdayLabels.count
        return weekdayLabels[offset]
    }

    private func gridLineOffset(for index: Int) -> CGFloat {
        CGFloat(index) / 5 * (chartHeight - 1)
    }

    private func yAxisLabelOffset(for index: Int) -> CGFloat {
        guard model.yAxisValues.count > 1 else { return 0 }
        let labelHeight: CGFloat = 13
        let rawOffset = CGFloat(index) / CGFloat(model.yAxisValues.count - 1) * chartHeight
        return min(max(0, rawOffset - (labelHeight / 2)), chartHeight - labelHeight)
    }
}

private struct DailyTypingAvoidedChartModel: Equatable {
    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    let orderedDays: [VoiceDailySavedTimeStats]
    let maxYAxisValue: Double
    let yAxisValues: [Double]
    let hasNoWeekActivity: Bool
    let bestDayIndex: Int?
    let bestDayLabel: String?
    let totalWeekSavedTime: TimeInterval

    init(days: [VoiceDailySavedTimeStats], weekStartDate: Date) {
        var byWeekday: [Int: VoiceDailySavedTimeStats] = [:]
        byWeekday.reserveCapacity(days.count)

        for day in days {
            byWeekday[day.weekdayIndex] = day
        }

        let calendar = Calendar.current
        orderedDays = (0..<7).map { weekday in
            if let day = byWeekday[weekday] {
                return day
            }

            return HomeDashboardStats.makeWeeklyDay(
                date: calendar.date(byAdding: .day, value: weekday, to: weekStartDate) ?? weekStartDate,
                weekdayIndex: weekday,
                words: 0,
                sessions: 0,
                audio: 0,
                estimatedSeconds: 0
            )
        }

        let maxMinutes = max(1, orderedDays.map { $0.estimatedTimeSavedDuration / 60 }.max() ?? 0)
        let resolvedMaxYAxisValue = (maxMinutes / 10).rounded(.up) * 10
        maxYAxisValue = resolvedMaxYAxisValue
        yAxisValues = (0...5).map { Double(5 - $0) * (resolvedMaxYAxisValue / 5) }
        hasNoWeekActivity = orderedDays.allSatisfy { $0.estimatedTimeSavedDuration == 0 }
        totalWeekSavedTime = orderedDays.reduce(into: TimeInterval(0)) { $0 += $1.estimatedTimeSavedDuration }

        let bestDay =
            orderedDays
            .filter { $0.estimatedTimeSavedDuration > 0 }
            .max {
                if $0.estimatedTimeSavedDuration == $1.estimatedTimeSavedDuration {
                    return $0.date < $1.date
                }
                return $0.estimatedTimeSavedDuration < $1.estimatedTimeSavedDuration
            }

        bestDayIndex = bestDay?.weekdayIndex
        bestDayLabel = bestDay.map {
            Self.dayLabel(for: $0.weekdayIndex) + " (\(HomeDashboardFormatting.savedMinutes($0.estimatedTimeSavedDuration)))"
        }
    }

    private static func dayLabel(for index: Int) -> String {
        let offset = ((index % weekdayLabels.count) + weekdayLabels.count) % weekdayLabels.count
        return weekdayLabels[offset]
    }
}

private struct ActivityHeatmap: View {
    let model: ActivityHeatmapModel
    let theme: StatsTheme

    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let hourTickPositions: Set<Int> = [0, 4, 8, 12, 16, 20, 23]

    init(model: ActivityHeatmapModel, theme: StatsTheme) {
        self.model = model
        self.theme = theme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity Heatmap")
                    .font(StatsTypography.panelLabel)
                    .tracking(StatsTypography.labelTracking)
                    .foregroundStyle(theme.textPrimary)
                    .textCase(.uppercase)
                Spacer()
                Text("Words")
                    .font(StatsTypography.tiny)
                    .tracking(StatsTypography.smallTracking)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(theme.surfaceElevated, in: Capsule())
            }

            ActivityHeatmapGrid(
                model: model,
                theme: theme,
                dayLabels: dayLabels,
                hourTickPositions: hourTickPositions
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 7) {
                Text("Less")
                    .font(StatsTypography.tiny)
                    .foregroundStyle(theme.textTertiary)
                ForEach([0.0, 0.18, 0.42, 0.68, 1.0], id: \.self) { value in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(theme.heatmapColor(value: value))
                        .frame(width: 18, height: 8)
                }
                Text("More")
                    .font(StatsTypography.tiny)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsCard(theme: theme, emphasized: true)
        .help(model.summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap by day and hour")
        .accessibilityValue(model.summary)
    }

}

private struct ActivityHeatmapGrid: View {
    let model: ActivityHeatmapModel
    let theme: StatsTheme
    let dayLabels: [String]
    let hourTickPositions: Set<Int>

    private let dayLabelWidth: CGFloat = 34
    private let hourLabelHeight: CGFloat = 14
    private let cellGap: CGFloat = 4
    private let hourCount = 24
    private let weekdayCount = 7
    private let minimumCellSize: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let cellSize = cellSize(for: proxy.size)

            VStack(alignment: .leading, spacing: cellGap) {
                HStack(spacing: cellGap) {
                    Color.clear
                        .frame(width: dayLabelWidth, height: hourLabelHeight)
                        .accessibilityHidden(true)

                    ForEach(0..<hourCount, id: \.self) { hour in
                        Text(label(for: hour))
                            .font(StatsTypography.axis)
                            .foregroundStyle(hourTickPositions.contains(hour) ? theme.textTertiary : .clear)
                            .frame(width: cellSize, height: hourLabelHeight)
                    }
                }

                ForEach(dayLabels.indices, id: \.self) { weekday in
                    HStack(alignment: .center, spacing: cellGap) {
                        Text(dayLabels[weekday])
                            .font(StatsTypography.tiny)
                            .tracking(StatsTypography.smallTracking)
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: dayLabelWidth, alignment: .leading)

                        ForEach(0..<hourCount, id: \.self) { hour in
                            let current = model.cell(weekday: weekday, hour: hour)
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(theme.heatmapColor(value: current.value))
                                .frame(width: cellSize, height: cellSize)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(theme.heatmapCellBorder, lineWidth: 0.6)
                                }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func cellSize(for size: CGSize) -> CGFloat {
        let horizontalGaps = cellGap * CGFloat(hourCount)
        let verticalGaps = cellGap * CGFloat(weekdayCount)
        let availableCellWidth = (size.width - dayLabelWidth - horizontalGaps) / CGFloat(hourCount)
        let availableCellHeight = (size.height - hourLabelHeight - verticalGaps) / CGFloat(weekdayCount)
        return max(minimumCellSize, floor(min(availableCellWidth, availableCellHeight)))
    }

    private func label(for hour: Int) -> String {
        String(format: "%02d", hour)
    }
}

private struct ActivityHeatmapModel: Equatable {
    private static let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    let cells: [HeatmapCell]
    let summary: String

    init(hourlyActivity: [HomeHourlyActivityStats]) {
        let maxHeatmapValue = max(1, hourlyActivity.map(\.wordCount).max() ?? 1)
        var bucketsByID: [Int: HomeHourlyActivityStats] = [:]
        bucketsByID.reserveCapacity(hourlyActivity.count)

        for bucket in hourlyActivity {
            bucketsByID[bucket.id] = bucket
        }

        cells = (0..<7).flatMap { weekday in
            (0..<24).map { hour in
                let bucket = bucketsByID[(weekday * 24) + hour]
                let wordCount = bucket?.wordCount ?? 0
                return HeatmapCell(
                    dayIndex: weekday,
                    hour: hour,
                    value: Double(wordCount) / Double(maxHeatmapValue),
                    sessionCount: bucket?.sessionCount ?? 0,
                    wordCount: wordCount
                )
            }
        }

        if let busiestSlot = hourlyActivity.max(by: {
            if $0.wordCount == $1.wordCount {
                return ($0.weekdayIndex, $0.hour) < ($1.weekdayIndex, $1.hour)
            }
            return $0.wordCount < $1.wordCount
        }), busiestSlot.wordCount > 0 {
            summary =
                "Peak at \(Self.dayLabels[busiestSlot.weekdayIndex]) \(Self.hourLabelText(for: busiestSlot.hour)) · "
                + "\(busiestSlot.wordCount) words"
        } else {
            summary = "No weekly activity yet"
        }
    }

    func cell(weekday: Int, hour: Int) -> HeatmapCell {
        let index = (weekday * 24) + hour
        guard cells.indices.contains(index) else {
            return HeatmapCell(dayIndex: weekday, hour: hour, value: 0, sessionCount: 0, wordCount: 0)
        }
        return cells[index]
    }

    private static func hourLabelText(for hour: Int) -> String {
        "\(hour):00"
    }
}

private struct HeatmapCell: Identifiable, Equatable {
    let dayIndex: Int
    let hour: Int
    let value: Double
    let sessionCount: Int
    let wordCount: Int

    var id: Int { dayIndex * 24 + hour }
}

private struct MilestoneCard: View {
    let milestone: VoiceUsageMilestone?
    let theme: StatsTheme

    private var title: String {
        guard let milestone else {
            return "All milestones unlocked"
        }
        return milestone.title
    }

    private var valueText: String {
        guard let milestone else {
            return "Complete"
        }
        return "\(HomeDashboardFormatting.milestoneValue(milestone.currentValue, unit: milestone.unit)) / "
            + "\(HomeDashboardFormatting.milestoneValue(milestone.targetValue, unit: milestone.unit))"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            compactLayout
        }
        .padding(18)
        .statsCard(theme: theme, emphasized: true)
        .accessibilityLabel("Milestone progress")
        .accessibilityValue(valueText)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 18) {
            MilestoneBadge(theme: theme)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("Next milestone")
                    .font(StatsTypography.panelLabel)
                    .tracking(StatsTypography.labelTracking)
                    .foregroundStyle(theme.textSecondary)
                    .textCase(.uppercase)
                Text(title)
                    .font(.system(size: 21, weight: .bold, design: .default))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 24)

            VStack(alignment: .trailing, spacing: 10) {
                Text(valueText)
                    .font(StatsTypography.smallStrong)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
                    .accessibilityValue(valueText)

                SegmentedMilestoneProgress(milestone: milestone, theme: theme)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 240, alignment: .trailing)
            .liquidGlassRounded(theme: theme, tint: theme.blue, cornerRadius: 16)
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                MilestoneBadge(theme: theme)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Next milestone")
                        .font(StatsTypography.panelLabel)
                        .tracking(StatsTypography.labelTracking)
                        .foregroundStyle(theme.textSecondary)
                        .textCase(.uppercase)
                    Text(title)
                        .font(.system(size: 21, weight: .bold, design: .default))
                        .foregroundStyle(theme.textPrimary)
                }

                Spacer(minLength: 0)

                Text(valueText)
                    .font(StatsTypography.smallStrong)
                    .foregroundStyle(theme.textSecondary)
                    .monospacedDigit()
            }

            SegmentedMilestoneProgress(milestone: milestone, theme: theme)
        }
    }
}

private struct MilestoneBadge: View {
    let theme: StatsTheme

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.glassFill(tint: theme.orange))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.orange.opacity(theme.isDark ? 0.34 : 0.18),
                            Color.white.opacity(theme.isDark ? 0.06 : 0.58),
                            theme.orange.opacity(theme.isDark ? 0.10 : 0.04)
                        ],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 62
                    )
                )

            Circle()
                .stroke(theme.glassStroke(tint: theme.orange), lineWidth: 1)

            Circle()
                .inset(by: 8)
                .stroke(Color.white.opacity(theme.isDark ? 0.13 : 0.64), lineWidth: 1)

            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(theme.orange)
                .shadow(color: theme.orange.opacity(theme.isDark ? 0.28 : 0.06), radius: 8, x: 0, y: 3)
        }
        .frame(width: 60, height: 60)
        .shadow(color: theme.orange.opacity(theme.isDark ? 0.16 : 0.05), radius: 14, x: 0, y: 7)
    }
}

private struct SegmentedMilestoneProgress: View {
    let milestone: VoiceUsageMilestone?
    let theme: StatsTheme

    private var segmentCount: Int {
        guard let target = milestone?.targetValue, target > 0 else { return 1 }
        return min(target, 14)
    }

    private var filledCount: Int {
        guard let milestone else { return segmentCount }
        if milestone.targetValue <= segmentCount {
            return min(segmentCount, max(0, milestone.currentValue))
        }
        return Int((milestone.progress * Double(segmentCount)).rounded(.down))
    }

    private var segmentWidth: CGFloat {
        switch segmentCount {
        case 1...4:
            return 88
        case 5...7:
            return 42
        default:
            return 24
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(index < filledCount ? theme.blue : emptySegmentColor)
                    .frame(width: segmentWidth, height: 12)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(index < filledCount ? Color.clear : theme.border, lineWidth: 1)
                    }
            }

            Image(systemName: "flag.checkered")
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(theme.textTertiary)
                .frame(width: 18, height: 12)
        }
    }

    private var emptySegmentColor: Color {
        theme.emptyProgressSegment
    }
}

private typealias StatsTheme = VoicePenTheme

private struct StatsCardStyle: ViewModifier {
    let theme: StatsTheme
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [theme.surfaceElevated, theme.surface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        if emphasized {
                            LinearGradient(
                                colors: [theme.panelHighlight, .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(emphasized ? theme.emphasizedCardBorder : theme.border, lineWidth: 1)
            }
            .shadow(
                color: theme.cardShadow,
                radius: theme.isDark ? (emphasized ? 20 : 16) : (emphasized ? 15 : 12),
                x: 0,
                y: theme.isDark ? (emphasized ? 12 : 8) : (emphasized ? 8 : 5)
            )
    }
}

private struct LiquidGlassRoundedStyle: ViewModifier {
    let theme: StatsTheme
    let tint: Color
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape
                    .fill(theme.glassFill(tint: tint))
            }
            .overlay {
                shape
                    .stroke(theme.glassStroke(tint: tint), lineWidth: 1)
            }
            .shadow(
                color: theme.cardShadow.opacity(theme.isDark ? 0.80 : 0.70),
                radius: shadowRadius,
                x: 0,
                y: shadowYOffset
            )
    }
}

private extension View {
    func statsCard(theme: StatsTheme, emphasized: Bool = false) -> some View {
        modifier(StatsCardStyle(theme: theme, emphasized: emphasized))
    }

    func liquidGlassCapsule(theme: StatsTheme, tint: Color) -> some View {
        modifier(
            LiquidGlassRoundedStyle(
                theme: theme,
                tint: tint,
                cornerRadius: 22,
                shadowRadius: theme.isDark ? 14 : 10,
                shadowYOffset: theme.isDark ? 8 : 5
            )
        )
        .clipShape(Capsule())
    }

    func liquidGlassBadge(theme: StatsTheme, tint: Color, cornerRadius: CGFloat) -> some View {
        modifier(
            LiquidGlassRoundedStyle(
                theme: theme,
                tint: tint,
                cornerRadius: cornerRadius,
                shadowRadius: theme.isDark ? 8 : 5,
                shadowYOffset: theme.isDark ? 4 : 2
            )
        )
    }

    func liquidGlassRounded(theme: StatsTheme, tint: Color, cornerRadius: CGFloat) -> some View {
        modifier(
            LiquidGlassRoundedStyle(
                theme: theme,
                tint: tint,
                cornerRadius: cornerRadius,
                shadowRadius: theme.isDark ? 12 : 8,
                shadowYOffset: theme.isDark ? 6 : 4
            )
        )
    }
}

private enum HomeDashboardDateRangeFormatter {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static func weekRangeText(from start: Date, to end: Date) -> String {
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }
}

private enum HomeDashboardFormatting {
    static func plural(_ singular: String, count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    static func cardCount(_ count: Int) -> String {
        count.formatted()
    }

    static func wordCount(_ value: Int) -> String {
        "\(value.formatted())"
    }

    static func countWithUnit(_ value: Int, singular: String, plural: String? = nil) -> String {
        "\(value.formatted()) \(value == 1 ? singular : (plural ?? "\(singular)s"))"
    }

    static func compactClock(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        if seconds > 0 {
            return "\(seconds)s"
        }
        return "0m"
    }

    static func savedMinutes(_ duration: TimeInterval) -> String {
        let minutes = Int((duration / 60).rounded())
        guard minutes > 0 else { return "0m" }
        return "\(minutes.formatted()) min"
    }

    static func savedTime(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours) h"
        }
        return "\(hours)h \(remainder)m"
    }

    static func milestoneValue(_ value: Int, unit: String) -> String {
        if unit == "seconds" {
            return savedTime(TimeInterval(value))
        }
        let singularUnit: String
        switch unit {
        case "days":
            singularUnit = "day"
        case "sessions":
            singularUnit = "session"
        case "words":
            singularUnit = "word"
        default:
            singularUnit = unit
        }
        return countWithUnit(value, singular: singularUnit, plural: unit)
    }
}

private extension HomeDashboardStats {
    static func makeWeeklyDay(
        date: Date,
        weekdayIndex: Int,
        words: Int,
        sessions: Int,
        audio: TimeInterval,
        estimatedSeconds: TimeInterval
    ) -> VoiceDailySavedTimeStats {
        VoiceDailySavedTimeStats(
            date: date,
            weekdayIndex: weekdayIndex,
            wordCount: words,
            sessionCount: sessions,
            audioDuration: audio,
            estimatedTimeSavedDuration: estimatedSeconds
        )
    }

    static var previewPopulated: HomeDashboardStats {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let dailyWords = [120, 240, 40, 0, 190, 55, 35]
        let dailySessions = [1, 3, 1, 0, 2, 1, 1]
        let dailyAudio = [40, 92, 20, 0, 70, 25, 25]
        let dailySavedMinutes = [120, 200, 35, 0, 165, 45, 38]
        let daily = (0..<7).map {
            Self.makeWeeklyDay(
                date: calendar.date(byAdding: .day, value: $0, to: start) ?? start,
                weekdayIndex: $0,
                words: dailyWords[$0],
                sessions: dailySessions[$0],
                audio: Double(dailyAudio[$0]),
                estimatedSeconds: Double(dailySavedMinutes[$0]) * 60
            )
        }

        let heatmapWordsByHour: [[Int: Int]] = [
            [9: 35, 10: 45, 11: 40],
            [9: 65, 10: 90, 11: 85],
            [14: 22, 15: 18],
            [:],
            [13: 54, 14: 72, 15: 64],
            [16: 30, 17: 25],
            [11: 18, 12: 17]
        ]

        let heatmap: [HomeHourlyActivityStats] = heatmapWordsByHour.enumerated().flatMap { weekday, wordsByHour in
            wordsByHour.map { hour, wordCount in
                return HomeHourlyActivityStats(
                    weekdayIndex: weekday,
                    hour: hour,
                    sessionCount: max(1, Int((Double(wordCount) / 80.0).rounded(.up))),
                    wordCount: wordCount,
                    audioDuration: 0
                )
            }
        }
        let filledHeatmap = HomeHourlyActivityStats.fillMatrix(from: heatmap)

        return HomeDashboardStats(
            week: VoiceWeeklyUsageStats(
                startDate: start,
                days: daily,
                hourlyActivity: filledHeatmap.map { $0.voiceHourlyActivity() },
                wordCount: 680,
                sessionCount: 8,
                audioDuration: 235,
                estimatedTimeSavedDuration: (680.0 / VoiceTranscriptionUsageStats.manualTypingWordsPerMinute) * 60
            ),
            weekStartDate: start,
            nextMilestone: VoiceUsageMilestone(
                title: "1,000 words",
                currentValue: 680,
                targetValue: 1_000,
                unit: "words"
            ),
            currentStreakDayCount: 4,
            bestStreakDayCount: 6,
            hourlyActivity: filledHeatmap
        )
    }

    static var previewEmpty: HomeDashboardStats {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let emptyWeek: [VoiceDailySavedTimeStats] = (0..<7).map {
            Self.makeWeeklyDay(
                date: calendar.date(byAdding: .day, value: $0, to: start) ?? start,
                weekdayIndex: $0,
                words: 0,
                sessions: 0,
                audio: 0,
                estimatedSeconds: 0
            )
        }

        return HomeDashboardStats(
            week: VoiceWeeklyUsageStats(
                startDate: start,
                days: emptyWeek,
                hourlyActivity: HomeHourlyActivityStats.zeroMatrix().map { $0.voiceHourlyActivity() },
                wordCount: 0,
                sessionCount: 0,
                audioDuration: 0,
                estimatedTimeSavedDuration: 0
            ),
            weekStartDate: start,
            nextMilestone: VoiceUsageMilestone(
                title: "First dictation",
                currentValue: 0,
                targetValue: 1,
                unit: "session"
            ),
            currentStreakDayCount: 0,
            bestStreakDayCount: 0,
            hourlyActivity: HomeHourlyActivityStats.zeroMatrix()
        )
    }

    func bestDayLabel(for day: VoiceDailySavedTimeStats) -> String {
        let labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let index = min(max(day.weekdayIndex, 0), labels.count - 1)
        return labels[index]
    }
}

private struct HomeDashboardStatsPreviewHost: View {
    let stats: HomeDashboardStats
    @Environment(\.colorScheme) private var colorScheme
    private let state: AppState = .ready
    private let hint = "⌘."

    var body: some View {
        HomeDashboardView(
            stats: stats,
            appState: state,
            pushToTalkHint: hint,
            statusAction: HomeStatusAction(title: "Open Settings", destination: .config),
            performStatusAction: { _ in }
        )
        .environment(\.colorScheme, colorScheme)
    }
}

#Preview("Home Dashboard - Populated (Light)") {
    HomeDashboardStatsPreviewHost(stats: HomeDashboardStats.previewPopulated)
        .environment(\.colorScheme, .light)
}

#Preview("Home Dashboard - Empty (Light)") {
    HomeDashboardStatsPreviewHost(stats: HomeDashboardStats.previewEmpty)
        .environment(\.colorScheme, .light)
}

#Preview("Home Dashboard - Populated (Dark)") {
    HomeDashboardStatsPreviewHost(stats: HomeDashboardStats.previewPopulated)
        .environment(\.colorScheme, .dark)
}

#Preview("Home Dashboard - Empty (Dark)") {
    HomeDashboardStatsPreviewHost(stats: HomeDashboardStats.previewEmpty)
        .environment(\.colorScheme, .dark)
}
