import Foundation
import SwiftUI

struct HomeDashboardView: View {
    let stats: HomeDashboardStats
    let appState: AppState
    let pushToTalkHint: String
    let statusAction: HomeStatusAction?
    let performStatusAction: (VoicePenSettingsSection) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var activityRange: HomeActivityRange = .sevenDay

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
                HomeActivityCard(
                    range: $activityRange,
                    stats: stats,
                    theme: theme
                )
                .frame(height: analyticsRowHeight)
            }
        } else {
            HStack(alignment: .top, spacing: dashboardGap) {
                HomeActivityCard(
                    range: $activityRange,
                    stats: stats,
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

private enum HomeActivityRange: String, CaseIterable, Identifiable {
    case sevenDay = "7d"
    case twelveMonth = "12m"

    var id: String {
        rawValue
    }

    var title: String {
        rawValue
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
    static let activitySummaryLabel = Font.system(size: 13, weight: .semibold, design: .default)
    static let activitySummaryValue = Font.system(size: 17, weight: .semibold, design: .default)
    static let activitySummaryDetail = Font.system(size: 14, weight: .medium, design: .default)

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
    let activity7d: VoiceSevenDayActivityStats
    let activity12Month: VoiceTwelveMonthActivityStats

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
        activity7d = stats.activityWeek
        activity12Month = stats.activity12Month
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

    var activity7dRangeLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: activity7d.startDate) ?? activity7d.startDate
        return HomeDashboardDateRangeFormatter.weekRangeText(from: activity7d.startDate, to: end)
    }

    var activity12mRangeLabel: String {
        return HomeDashboardDateRangeFormatter.monthRangeText(from: activity12Month.startDate, to: activity12Month.endDate)
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

private struct HomeActivityCard: View {
    @Binding var range: HomeActivityRange
    let stats: HomeDashboardStats
    let theme: StatsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Text("Activity")
                    .font(StatsTypography.panelLabel)
                    .tracking(StatsTypography.labelTracking)
                    .foregroundStyle(theme.textPrimary)
                    .textCase(.uppercase)

                Spacer(minLength: 16)

                HStack(alignment: .center, spacing: 14) {
                    Text(rangeLabel)
                        .font(StatsTypography.small)
                        .foregroundStyle(theme.textTertiary.opacity(0.78))
                        .lineLimit(1)
                        .monospacedDigit()
                        .frame(minWidth: 120, alignment: .trailing)
                        .padding(.top, 1)

                    ActivityRangeSegmentedControl(
                        selection: $range,
                        theme: theme
                    )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Divider()
                .overlay(theme.gridLine)

            switch range {
            case .sevenDay:
                SevenDayActivityMode(model: stats.activity7d, theme: theme)
            case .twelveMonth:
                TwelveMonthActivityMode(model: stats.activity12Month, theme: theme)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .statsCard(theme: theme, emphasized: true)
    }

    private var rangeLabel: String {
        switch range {
        case .sevenDay:
            stats.activity7dRangeLabel
        case .twelveMonth:
            stats.activity12mRangeLabel
        }
    }
}

private struct ActivityRangeSegmentedControl: View {
    @Binding var selection: HomeActivityRange
    let theme: StatsTheme

    private let ranges: [HomeActivityRange] = [.sevenDay, .twelveMonth]
    private let segmentWidth: CGFloat = 48
    private let segmentHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ranges.indices, id: \.self) { index in
                let range = ranges[index]
                Button {
                    selection = range
                } label: {
                    Text(range.title)
                        .font(StatsTypography.smallStrong)
                        .foregroundStyle(selection == range ? Color.white : theme.textSecondary)
                        .monospacedDigit()
                        .frame(width: segmentWidth, height: segmentHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == range {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(theme.blue)
                    }
                }
                .overlay(alignment: .trailing) {
                    if index < ranges.count - 1 {
                        Rectangle()
                            .fill(theme.gridLine.opacity(selection == range ? 0 : 0.72))
                            .frame(width: 1, height: 14)
                    }
                }
                .accessibilityLabel(range.title)
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(theme.glassFill(tint: theme.blue))
                .opacity(theme.isDark ? 0.42 : 0.56)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(theme.glassStroke(tint: theme.blue), lineWidth: 1)
                .opacity(theme.isDark ? 0.42 : 0.52)
        }
        .fixedSize()
    }
}

private struct SevenDayActivityMode: View {
    let model: VoiceSevenDayActivityStats
    let theme: StatsTheme

    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private let labeledHours = [0, 4, 8, 12, 16, 20, 24]

    private func day(for index: Int) -> VoiceDailySavedTimeStats {
        guard index < model.days.count else {
            let fallbackDate =
                Calendar.current.date(
                    byAdding: .day,
                    value: index,
                    to: Calendar.current.startOfDay(for: model.startDate)
                ) ?? model.startDate
            return VoiceDailySavedTimeStats(
                date: fallbackDate,
                weekdayIndex: index,
                wordCount: 0,
                sessionCount: 0,
                audioDuration: 0,
                estimatedTimeSavedDuration: 0
            )
        }
        return model.days[index]
    }

    private func hourBucket(dayIndex: Int, hour: Int) -> VoiceHourlyActivityStats {
        let index = (dayIndex * 24) + hour
        guard model.hourlyActivity.indices.contains(index) else {
            return VoiceHourlyActivityStats(
                weekdayIndex: dayIndex,
                hour: hour,
                sessionCount: 0,
                wordCount: 0,
                audioDuration: 0
            )
        }
        return model.hourlyActivity[index]
    }

    var body: some View {
        ActivityModeContentLayout(
            theme: theme,
            chartTopPadding: ActivityCardLayout.sevenDayChartTopPadding,
            insights: [
                ActivitySummaryItem(
                    title: "Total",
                    value: "\(HomeDashboardFormatting.cardCount(model.totalWordCount)) words"
                ),
                ActivitySummaryItem(
                    title: "Best day",
                    value: bestDayValue,
                    detail: bestDayDetail
                ),
                ActivitySummaryItem(
                    title: "Peak",
                    value: peakValue,
                    detail: peakDetail
                )
            ]
        ) {
            GeometryReader { proxy in
                let metrics = SevenDayGridMetrics(width: proxy.size.width)
                let intensity = ActivityIntensity(for: theme)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: metrics.labelToGridSpacing) {
                        Color.clear
                            .frame(width: metrics.dayLabelWidth)

                        SevenDayHourAxis(
                            labeledHours: labeledHours,
                            metrics: metrics,
                            theme: theme
                        )
                    }
                    .frame(height: metrics.hourAxisHeight, alignment: .topLeading)

                    HStack(alignment: .top, spacing: metrics.labelToGridSpacing) {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                            ForEach(0..<weekdayLabels.count, id: \.self) { dayIndex in
                                Text(weekdayLabels[dayIndex])
                                    .font(StatsTypography.axis)
                                    .foregroundStyle(theme.textTertiary)
                                    .frame(width: metrics.dayLabelWidth, height: metrics.cellSize, alignment: .leading)
                            }
                        }

                        VStack(spacing: metrics.rowSpacing) {
                            ForEach(0..<weekdayLabels.count, id: \.self) { dayIndex in
                                let day = day(for: dayIndex)

                                HStack(spacing: metrics.cellSpacing) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        let bucket = hourBucket(dayIndex: dayIndex, hour: hour)
                                        RoundedRectangle(cornerRadius: metrics.cellCornerRadius, style: .continuous)
                                            .fill(
                                                intensity.color(
                                                    value: bucket.wordCount,
                                                    maxValue: model.maxHourlyWordCount
                                                )
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: metrics.cellCornerRadius, style: .continuous)
                                                    .stroke(intensity.borderColor, lineWidth: 1)
                                            }
                                            .frame(width: metrics.cellWidth, height: metrics.cellSize)
                                            .help(tooltip(day: day, hour: hour, wordCount: bucket.wordCount))
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, ActivityCardLayout.axisToGridSpacing)

                    ActivityLegend(theme: theme)
                        .frame(height: ActivityCardLayout.legendHeight, alignment: .leading)
                        .padding(.top, ActivityCardLayout.gridToLegendSpacing)
                        .padding(.leading, metrics.gridLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func tooltip(day: VoiceDailySavedTimeStats, hour: Int, wordCount: Int) -> String {
        "\(weekdayLabel(for: day.date)) \(String(format: "%02d", hour)):00 · \(HomeDashboardFormatting.cardCount(wordCount)) words"
    }

    private func weekdayLabel(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.weekday], from: date)
        let weekday = components.weekday ?? 2
        let index = ((weekday + 5) % 7 + 7) % 7
        return weekdayLabels[index]
    }

    private func peakRange(from startHour: Int) -> String {
        let endHour = min(startHour + 4, 24)
        return "\(String(format: "%02d", startHour)):00 - \(String(format: "%02d", endHour)):00"
    }

    private var bestDayValue: String {
        guard let bestDay = model.bestDay else { return "None" }
        return weekdayLabel(for: bestDay.date)
    }

    private var bestDayDetail: String? {
        guard let bestDay = model.bestDay else { return nil }
        return "\(HomeDashboardFormatting.cardCount(bestDay.wordCount)) words"
    }

    private var peakValue: String {
        guard let startHour = model.peakWindowStartHour else { return "None" }
        return peakRange(from: startHour)
    }

    private var peakDetail: String? {
        guard model.peakWindowStartHour != nil else { return nil }
        return "\(HomeDashboardFormatting.cardCount(model.peakWindowWordCount)) words"
    }
}

private struct TwelveMonthActivityMode: View {
    let model: VoiceTwelveMonthActivityStats
    let theme: StatsTheme

    private let dayTooltipFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    var body: some View {
        ActivityModeContentLayout(
            theme: theme,
            chartTopPadding: ActivityCardLayout.twelveMonthChartTopPadding,
            insights: [
                ActivitySummaryItem(
                    title: "Total",
                    value: "\(HomeDashboardFormatting.cardCount(model.totalWordCount)) words"
                ),
                ActivitySummaryItem(
                    title: "Best day",
                    value: bestDayValue,
                    detail: bestDayDetail
                ),
                ActivitySummaryItem(
                    title: "Active",
                    value: "\(HomeDashboardFormatting.cardCount(model.activeDayCount)) days",
                    detail: "\(HomeDashboardFormatting.cardCount(model.activeMonthCount)) months"
                )
            ]
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ActivityContributionGrid(
                    days: model.days,
                    maxWordCount: model.maxDailyWordCount,
                    theme: theme,
                    maximumCellSize: ActivityCardLayout.cellSize12m,
                    minimumCellSize: ActivityCardLayout.minimumCellSize12m,
                    cellSpacing: ActivityCardLayout.cellGap12m,
                    labelWidth: ActivityCardLayout.axisLabelWidth,
                    labelToGridSpacing: ActivityCardLayout.labelToGridSpacing,
                    cornerRadius: ActivityCardLayout.cellCornerRadius12m,
                    tooltipFormatter: dayTooltipFormatter
                )
                .frame(height: ActivityCardLayout.twelveMonthGridHeight, alignment: .topLeading)

                ActivityLegend(theme: theme)
                    .frame(height: ActivityCardLayout.legendHeight, alignment: .leading)
                    .padding(.top, ActivityCardLayout.gridToLegendSpacing)
                    .padding(.leading, ActivityCardLayout.legendLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var bestDayValue: String {
        guard let bestDay = model.bestDay else { return "None" }
        return dayTooltipFormatter.string(from: bestDay.date)
    }

    private var bestDayDetail: String? {
        guard let bestDay = model.bestDay else { return nil }
        return "\(HomeDashboardFormatting.cardCount(bestDay.wordCount)) words"
    }
}

private enum ActivityCardLayout {
    static let axisLabelWidth: CGFloat = 48
    static let contentRowHeight: CGFloat = 244
    static let legendHeight: CGFloat = 12
    static let chartToInsightSpacing: CGFloat = 10
    static let insightCardGap: CGFloat = 10
    static let insightRowHeight: CGFloat = 72
    static let sevenDayChartTopPadding: CGFloat = 0
    static let twelveMonthChartTopPadding: CGFloat = 0
    static let axisToGridSpacing: CGFloat = 12
    static let monthToGridSpacing: CGFloat = 12
    static let gridToLegendSpacing: CGFloat = 18
    static let labelToGridSpacing: CGFloat = 8
    static let cellSize7d: CGFloat = 12
    static let cellGap7d: CGFloat = 3
    static let cellCornerRadius7d: CGFloat = 3
    static let cellSize12m: CGFloat = 12
    static let minimumCellSize12m: CGFloat = 6
    static let cellGap12m: CGFloat = 3
    static let cellCornerRadius12m: CGFloat = 3
    static let twelveMonthGridHeight: CGFloat = 14 + monthToGridSpacing + (cellSize12m * 7) + (cellGap12m * 6)
    static let legendLeading: CGFloat = axisLabelWidth + labelToGridSpacing
}

private struct SevenDayGridMetrics {
    let dayLabelWidth: CGFloat = ActivityCardLayout.axisLabelWidth
    let cellSpacing: CGFloat = ActivityCardLayout.cellGap7d
    let rowSpacing: CGFloat = ActivityCardLayout.cellGap7d
    let labelToGridSpacing: CGFloat = ActivityCardLayout.labelToGridSpacing
    let cellWidth: CGFloat
    let cellSize: CGFloat
    let hourAxisHeight: CGFloat = 14
    let cellCornerRadius: CGFloat = ActivityCardLayout.cellCornerRadius7d

    init(width: CGFloat) {
        let gridGapsWidth = cellSpacing * 23
        let reservedWidth = dayLabelWidth + labelToGridSpacing + gridGapsWidth
        cellWidth = max(10, (width - reservedWidth) / 24)
        cellSize = min(ActivityCardLayout.cellSize7d, cellWidth)
    }

    var gridWidth: CGFloat {
        (cellWidth * 24) + (cellSpacing * 23)
    }

    var gridRowsHeight: CGFloat {
        (cellSize * 7) + (rowSpacing * 6)
    }

    var gridLeading: CGFloat {
        dayLabelWidth + labelToGridSpacing
    }
}

private struct SevenDayHourAxis: View {
    let labeledHours: [Int]
    let metrics: SevenDayGridMetrics
    let theme: StatsTheme

    var body: some View {
        HStack(spacing: metrics.cellSpacing) {
            ForEach(0..<24, id: \.self) { hour in
                if labeledHours.contains(hour) {
                    Text(String(format: "%02d", hour))
                        .font(StatsTypography.axis)
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: metrics.cellWidth, alignment: .leading)
                } else {
                    Color.clear
                        .frame(width: metrics.cellWidth, height: 1)
                }
            }
        }
        .frame(width: metrics.gridWidth, height: metrics.hourAxisHeight, alignment: .leading)
        .overlay(alignment: .trailing) {
            if labeledHours.contains(24) {
                Text("24")
                    .font(StatsTypography.axis)
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

private struct ActivityContributionGrid: View {
    let days: [VoiceDailySavedTimeStats]
    let maxWordCount: Int
    let theme: StatsTheme
    let maximumCellSize: CGFloat
    let minimumCellSize: CGFloat
    let cellSpacing: CGFloat
    let labelWidth: CGFloat
    let labelToGridSpacing: CGFloat
    let cornerRadius: CGFloat
    let tooltipFormatter: DateFormatter

    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    var body: some View {
        GeometryReader { proxy in
            let cells = contributionCells
            let columnCount = max(1, cells.count / 7)
            let topLabelHeight: CGFloat = 14
            let availableWidth = max(0, proxy.size.width - labelWidth - labelToGridSpacing)
            let availableCellWidth = (availableWidth - (cellSpacing * CGFloat(max(0, columnCount - 1)))) / CGFloat(columnCount)
            let cellWidth = max(minimumCellSize, availableCellWidth)
            let cellHeight = min(maximumCellSize, max(minimumCellSize, availableCellWidth))
            let gridWidth = (CGFloat(columnCount) * cellWidth) + (CGFloat(max(0, columnCount - 1)) * cellSpacing)
            let markers = monthMarkers(cells: cells)
            let intensity = ActivityIntensity(for: theme)

            VStack(alignment: .leading, spacing: ActivityCardLayout.monthToGridSpacing) {
                HStack(spacing: labelToGridSpacing) {
                    Color.clear
                        .frame(width: labelWidth)

                    HStack(spacing: cellSpacing) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            if let marker = markers.first(where: { $0.column == column }) {
                                Text(marker.label)
                                    .font(StatsTypography.axis)
                                    .foregroundStyle(theme.textTertiary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: cellWidth, alignment: .leading)
                            } else {
                                Color.clear
                                    .frame(width: cellWidth, height: 1)
                            }
                        }
                    }
                    .frame(width: gridWidth, height: topLabelHeight, alignment: .leading)
                }

                HStack(alignment: .top, spacing: labelToGridSpacing) {
                    VStack(alignment: .leading, spacing: cellSpacing) {
                        ForEach(weekdayLabels, id: \.self) { label in
                            Text(label)
                                .font(StatsTypography.axis)
                                .foregroundStyle(theme.textTertiary)
                                .frame(width: labelWidth, height: cellHeight, alignment: .leading)
                        }
                    }

                    HStack(alignment: .top, spacing: cellSpacing) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            VStack(spacing: cellSpacing) {
                                ForEach(0..<7, id: \.self) { row in
                                    let index = (column * 7) + row
                                    if cells.indices.contains(index), let day = cells[index] {
                                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                            .fill(intensity.color(value: day.wordCount, maxValue: maxWordCount))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                                    .stroke(intensity.borderColor, lineWidth: 1)
                                            }
                                            .frame(width: cellWidth, height: cellHeight)
                                            .help("\(tooltipFormatter.string(from: day.date)) · \(HomeDashboardFormatting.cardCount(day.wordCount)) words")
                                    } else {
                                        Color.clear
                                            .frame(width: cellWidth, height: cellHeight)
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: gridWidth, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var contributionCells: [VoiceDailySavedTimeStats?] {
        guard let firstDay = days.first else { return Array(repeating: nil, count: 7) }

        var items: [VoiceDailySavedTimeStats?] = Array(repeating: nil, count: firstDay.weekdayIndex)
        items.append(contentsOf: days)

        let remainder = items.count % 7
        if remainder != 0 {
            items.append(contentsOf: Array(repeating: nil, count: 7 - remainder))
        }

        return items
    }

    private func monthMarkers(cells: [VoiceDailySavedTimeStats?]) -> [ContributionMonthMarker] {
        var markers: [ContributionMonthMarker] = []
        var previousMonthKey: Int?
        let calendar = Calendar.current

        for index in cells.indices {
            guard let day = cells[index] else { continue }
            let components = calendar.dateComponents([.year, .month], from: day.date)
            let month = components.month ?? 0
            let year = components.year ?? 0
            let key = (year * 12) + month

            if key != previousMonthKey {
                markers.append(
                    ContributionMonthMarker(
                        column: index / 7,
                        label: monthFormatter.string(from: day.date)
                    )
                )
                previousMonthKey = key
            }
        }

        return markers
    }
}

private struct ContributionMonthMarker: Identifiable {
    let column: Int
    let label: String

    var id: String {
        "\(column)-\(label)"
    }
}

private struct ActivitySummaryItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String?

    init(title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }
}

private struct ActivityModeContentLayout<Chart: View>: View {
    let theme: StatsTheme
    let chartTopPadding: CGFloat
    let items: [ActivitySummaryItem]
    let chart: Chart

    init(
        theme: StatsTheme,
        chartTopPadding: CGFloat,
        insights: [ActivitySummaryItem],
        @ViewBuilder chart: () -> Chart
    ) {
        self.theme = theme
        self.chartTopPadding = chartTopPadding
        items = insights
        self.chart = chart()
    }

    var body: some View {
        GeometryReader { proxy in
            let chartHeight = max(
                0,
                ActivityCardLayout.contentRowHeight
                    - chartTopPadding
                    - ActivityCardLayout.chartToInsightSpacing
                    - ActivityCardLayout.insightRowHeight
            )

            VStack(alignment: .leading, spacing: ActivityCardLayout.chartToInsightSpacing) {
                chart
                    .frame(width: proxy.size.width, height: chartHeight, alignment: .topLeading)
                    .padding(.top, chartTopPadding)

                ActivityInsightRow(items: items, theme: theme)
                    .frame(width: proxy.size.width, height: ActivityCardLayout.insightRowHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: ActivityCardLayout.contentRowHeight)
    }
}

private struct ActivityInsightRow: View {
    let items: [ActivitySummaryItem]
    let theme: StatsTheme

    var body: some View {
        HStack(alignment: .top, spacing: ActivityCardLayout.insightCardGap) {
            ForEach(items.indices, id: \.self) { index in
                ActivityInsightBlock(item: items[index], theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }
}

private struct ActivityInsightBlock: View {
    let item: ActivitySummaryItem
    let theme: StatsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(StatsTypography.activitySummaryLabel)
                .foregroundStyle(theme.textTertiary.opacity(0.92))
                .textCase(.uppercase)

            Text(item.value)
                .font(StatsTypography.activitySummaryValue)
                .foregroundStyle(theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
                .monospacedDigit()

            if let detail = item.detail {
                Text(detail)
                    .font(StatsTypography.activitySummaryDetail)
                    .foregroundStyle(theme.textSecondary.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.glassFill(tint: theme.blue))
                .opacity(theme.isDark ? 0.40 : 0.58)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.glassStroke(tint: theme.blue), lineWidth: 1)
                .opacity(theme.isDark ? 0.36 : 0.48)
        }
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(theme.isDark ? 0.05 : 0.30), lineWidth: 1)
        }
    }
}

private struct ActivityLegend: View {
    let theme: StatsTheme

    var body: some View {
        let intensity = ActivityIntensity(for: theme)

        HStack(spacing: 5) {
            Text("Less")
                .font(StatsTypography.axis)
                .foregroundStyle(theme.textTertiary)

            ForEach(1...5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(intensity.color(level: level))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(intensity.borderColor, lineWidth: 1)
                    }
                    .frame(width: 14, height: 10)
            }

            Text("More")
                .font(StatsTypography.axis)
                .foregroundStyle(theme.textTertiary)
        }
    }
}

private struct ActivityIntensity {
    let theme: StatsTheme

    init(for theme: StatsTheme) {
        self.theme = theme
    }

    func normalizedValue(_ value: Int, maxValue: Int) -> Double {
        guard maxValue > 0 else { return 0 }
        guard value > 0 else { return 0 }
        return max(0, min(1, Double(value) / Double(maxValue)))
    }

    func color(value: Int, maxValue: Int) -> Color {
        color(level: level(value: value, maxValue: maxValue))
    }

    func color(level: Int) -> Color {
        let boundedLevel = max(0, min(5, level))
        if boundedLevel == 0 {
            return theme.isDark
                ? Color.white.opacity(0.045)
                : Color(red: 0.935, green: 0.945, blue: 0.958)
        }

        if theme.isDark {
            switch boundedLevel {
            case 1:
                return Color(red: 0.15, green: 0.22, blue: 0.40)
            case 2:
                return Color(red: 0.16, green: 0.27, blue: 0.52)
            case 3:
                return Color(red: 0.22, green: 0.36, blue: 0.72)
            case 4:
                return theme.blue.opacity(0.84)
            default:
                return Color(red: 0.54, green: 0.56, blue: 1.00)
            }
        }

        switch boundedLevel {
        case 1:
            return Color(red: 0.75, green: 0.82, blue: 0.99)
        case 2:
            return Color(red: 0.66, green: 0.74, blue: 0.98)
        case 3:
            return Color(red: 0.50, green: 0.61, blue: 0.96)
        case 4:
            return theme.blue.opacity(0.86)
        default:
            return theme.blue
        }
    }

    var borderColor: Color {
        theme.isDark ? Color.white.opacity(0.055) : Color.white.opacity(0.78)
    }

    private func level(value: Int, maxValue: Int) -> Int {
        guard value > 0, maxValue > 0 else { return 0 }
        let ratio = normalizedValue(value, maxValue: maxValue)
        return max(1, min(5, Int((ratio * 5).rounded(.up))))
    }
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
        let now = calendar.startOfDay(for: Date())
        var entries: [VoiceHistoryEntry] = []
        let weeklyWordsByDay: [Int] = [120, 95, 0, 40, 190, 55, 35]

        for dayOffset in 0..<7 {
            if weeklyWordsByDay[dayOffset] > 0 {
                entries.append(
                    sampleHistoryEntry(
                        createdAt: calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now,
                        duration: 18 + Double(dayOffset),
                        recognizedWordCount: weeklyWordsByDay[dayOffset]
                    )
                )
            }
        }

        for dayOffset in stride(from: 0, through: 29, by: 4) {
            if dayOffset == 0 { continue }
            entries.append(
                sampleHistoryEntry(
                    createdAt: calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now,
                    duration: 40,
                    recognizedWordCount: 70 + dayOffset
                )
            )
        }

        for monthOffset in stride(from: -11, through: 0, by: 1) {
            let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: now) ?? now
            entries.append(
                sampleHistoryEntry(
                    createdAt: monthDate,
                    duration: 24,
                    recognizedWordCount: 500 + (monthOffset * -10),
                    status: .insertAttempted
                )
            )
        }

        return HomeDashboardStats(stats: VoiceTranscriptionUsageStats(entries: entries, now: Date(), calendar: calendar))
    }

    static var previewEmpty: HomeDashboardStats {
        return HomeDashboardStats(stats: .init())
    }

    static var previewActivityLayout: HomeDashboardStats {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 14, hour: 12)) ?? Date()
        var entries: [VoiceHistoryEntry] = []

        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? now
        }

        let weeklyActivity: [(Date, Int)] = [
            (date(2026, 6, 8, 9), 180),
            (date(2026, 6, 9, 13), 520),
            (date(2026, 6, 9, 14), 470),
            (date(2026, 6, 9, 15), 640),
            (date(2026, 6, 9, 16), 201),
            (date(2026, 6, 10, 0), 260),
            (date(2026, 6, 10, 12), 420),
            (date(2026, 6, 10, 14), 390),
            (date(2026, 6, 10, 15), 371),
            (date(2026, 6, 12, 20), 3)
        ]

        entries.append(
            contentsOf: weeklyActivity.map { createdAt, wordCount in
                sampleHistoryEntry(
                    createdAt: createdAt,
                    duration: 24,
                    recognizedWordCount: wordCount
                )
            }
        )

        let monthlyActivity: [(Date, Int)] = [
            (date(2025, 7, 8, 10), 120),
            (date(2025, 8, 12, 11), 90),
            (date(2025, 9, 16, 12), 150),
            (date(2025, 10, 20, 13), 80),
            (date(2025, 11, 24, 14), 110),
            (date(2025, 12, 28, 15), 170),
            (date(2026, 1, 6, 10), 130),
            (date(2026, 2, 10, 11), 95),
            (date(2026, 3, 9, 12), 160),
            (date(2026, 4, 13, 13), 140),
            (date(2026, 5, 18, 14), 220)
        ]

        entries.append(
            contentsOf: monthlyActivity.map { createdAt, wordCount in
                sampleHistoryEntry(
                    createdAt: createdAt,
                    duration: 18,
                    recognizedWordCount: wordCount
                )
            }
        )

        return HomeDashboardStats(
            stats: VoiceTranscriptionUsageStats(
                entries: entries,
                now: now,
                calendar: calendar
            )
        )
    }

    private static func sampleHistoryEntry(
        createdAt: Date,
        duration: TimeInterval,
        recognizedWordCount: Int,
        status: VoiceHistoryStatus = .insertAttempted
    ) -> VoiceHistoryEntry {
        VoiceHistoryEntry(
            id: UUID(),
            createdAt: createdAt,
            duration: duration,
            rawText: "",
            finalText: "preview",
            status: status,
            errorMessage: nil,
            timings: nil,
            recognizedWordCount: recognizedWordCount
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

private struct HomeActivityCardPreviewHost: View {
    let initialRange: HomeActivityRange
    let colorScheme: ColorScheme
    @State private var range: HomeActivityRange

    init(initialRange: HomeActivityRange, colorScheme: ColorScheme) {
        self.initialRange = initialRange
        self.colorScheme = colorScheme
        _range = State(initialValue: initialRange)
    }

    var body: some View {
        let theme = StatsTheme.resolve(colorScheme)

        HomeActivityCard(
            range: $range,
            stats: .previewActivityLayout,
            theme: theme
        )
        .frame(width: 1_020, height: 320)
        .padding(24)
        .background(theme.background)
        .environment(\.colorScheme, colorScheme)
    }
}

#Preview("Activity Card - 7d") {
    HomeActivityCardPreviewHost(initialRange: .sevenDay, colorScheme: .dark)
}

#Preview("Activity Card - 12m") {
    HomeActivityCardPreviewHost(initialRange: .twelveMonth, colorScheme: .dark)
}

#Preview("Activity Card - 7d Light") {
    HomeActivityCardPreviewHost(initialRange: .sevenDay, colorScheme: .light)
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
