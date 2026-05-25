import Foundation
import KeyboardShortcuts
import SwiftUI

enum VoicePenSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case model
    case modes
    case ai
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
        case .ai:
            return "AI"
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
            return "arrow.down.circle"
        case .modes:
            return "terminal"
        case .ai:
            return "sparkles"
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

struct AboutView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore

    private let linkedInURL = URL(string: "https://www.linkedin.com/in/khokhlachev/")!

    private var historyStorageCaption: String {
        historyStore.storageStats.formattedDiskUsageSize
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.red.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("VoicePen")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))

                            Text("Offline push-to-talk dictation for macOS")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text("Made by Sergey Khokhlachev.")
                        .font(.system(size: 14, weight: .medium))

                    Text("VoicePen works locally on your Mac, does not send your voice or text to cloud services, and has 0 analytics.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: linkedInURL) {
                        Label("Sergey Khokhlachev on LinkedIn", systemImage: "link")
                    }
                }
                .padding(.vertical, 10)
            } footer: {
                Text("Model downloads happen only after confirmation. Transcription runs locally with installed models.")
            }

            Section {
                LabeledContent("Status", value: controller.appState.menuTitle)
                LabeledContent("Privacy", value: "Offline only, 0 analytics")
                LabeledContent("Storage", value: historyStorageCaption)
                LabeledContent("Database", value: controller.historyURL.path)
            } header: {
                Text("App")
            } footer: {
                Text("VoicePen records only while the push-to-talk shortcut is held. Audio and text stay on this Mac.")
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    let openSection: (VoicePenSettingsSection) -> Void

    private var stats: VoiceTranscriptionUsageStats {
        VoiceTranscriptionUsageStats(entries: historyStore.entries)
    }

    private var pushToTalkHint: String {
        controller.settingsStore.hotkeyPreference.menuBarHint()
    }

    private var statusAction: HomeStatusAction? {
        switch controller.appState {
        case .missingMicrophonePermission, .missingAccessibilityPermission, .missingSystemAudioPermission:
            return HomeStatusAction(title: "Open Settings", destination: .config)
        case .missingModel:
            return HomeStatusAction(title: "Open Models", destination: .model)
        default:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HomeStatusStrip(
                    appState: controller.appState,
                    pushToTalkHint: pushToTalkHint,
                    action: statusAction,
                    performAction: openSection
                )

                HomeThisWeekCard(stats: stats)
            }
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HomeStatusAction {
    let title: String
    let destination: VoicePenSettingsSection
}

private struct HomeStatusStrip: View {
    let appState: AppState
    let pushToTalkHint: String
    let action: HomeStatusAction?
    let performAction: (VoicePenSettingsSection) -> Void

    private var level: HomeStatusLevel {
        switch appState {
        case .ready:
            return .ready
        case .missingMicrophonePermission, .error:
            return .notReady
        case .starting, .recording, .transcribing, .meetingRecording, .meetingProcessing,
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let action {
                Button(action.title) {
                    performAction(action.destination)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
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

private struct HomeThisWeekCard: View {
    let stats: VoiceTranscriptionUsageStats

    private var week: VoiceWeeklyUsageStats {
        stats.week
    }

    private var summaryLineOne: String {
        "\(week.wordCount.formatted()) \(HomeFormatting.plural("word", count: week.wordCount)) transcribed · \(week.sessionCount.formatted()) \(HomeFormatting.plural("session", count: week.sessionCount))"
    }

    private var summaryLineTwo: String {
        "\(HomeFormatting.compactDuration(week.audioDuration)) spoken audio · Current streak \(stats.currentStreakDayCount.formatted()) \(HomeFormatting.plural("day", count: stats.currentStreakDayCount))"
    }

    private var bestSavedTimeText: String {
        guard let day = week.bestSavedTimeDay, day.estimatedTimeSavedDuration > 0 else {
            return "No typing avoided"
        }
        return "\(HomeFormatting.savedMinutes(day.estimatedTimeSavedDuration)) avoided"
    }

    private var hasWeekActivity: Bool {
        week.sessionCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("This week")
                .font(.system(size: 18, weight: .semibold))

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 42) {
                    metricsColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    DailySavedTimeChart(days: week.days)
                        .frame(width: 440)
                }

                VStack(alignment: .leading, spacing: 28) {
                    metricsColumn
                    DailySavedTimeChart(days: week.days)
                }
            }

            Divider()

            HomeMilestoneProgress(milestone: stats.nextMilestone)
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    private var metricsColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                if hasWeekActivity {
                    Text("≈ \(HomeFormatting.savedTimeMetric(week.estimatedTimeSavedDuration)) typing avoided")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)

                    Text("Based on recognized words at ~\(Int(VoiceTranscriptionUsageStats.manualTypingWordsPerMinute)) WPM")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                } else {
                    Text("No activity this week yet")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("Use push-to-talk to start building the habit.")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HomeMetricLine(
                    systemImage: "doc.text",
                    text: summaryLineOne
                )
                HomeMetricLine(
                    systemImage: "clock",
                    text: summaryLineTwo
                )
            }

            Divider()

            HStack(spacing: 18) {
                HomeHabitMetric(
                    systemImage: "calendar",
                    tint: .accentColor,
                    title: "\(week.activeDayCount.formatted()) active \(HomeFormatting.plural("day", count: week.activeDayCount))",
                    caption: "this week"
                )
                HomeHabitDivider()
                HomeHabitMetric(
                    systemImage: "trophy",
                    tint: .green,
                    title: "Best day this week",
                    caption: bestSavedTimeText
                )
                HomeHabitDivider()
                HomeHabitMetric(
                    systemImage: "flame",
                    tint: .orange,
                    title: "Best streak",
                    caption: "\(stats.bestStreakDayCount.formatted()) \(HomeFormatting.plural("day", count: stats.bestStreakDayCount)) all time"
                )
            }
        }
    }
}

private struct HomeMetricLine: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
        }
    }
}

private struct HomeHabitMetric: View {
    let systemImage: String
    let tint: Color
    let title: String
    let caption: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeHabitDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(width: 1, height: 34)
    }
}

private struct DailySavedTimeChart: View {
    let days: [VoiceDailySavedTimeStats]

    private let chartHeight: CGFloat = 172
    private let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    private var maxMinutes: Double {
        let dailyMax = days.map { $0.estimatedTimeSavedDuration / 60 }.max() ?? 0
        return max(10, ceil(dailyMax / 2) * 2)
    }

    private var yAxisLabels: [Int] {
        let step = maxMinutes / 5
        return (0...5).reversed().map { Int((Double($0) * step).rounded()) }
    }

    private var hasActivity: Bool {
        days.contains { $0.isActive }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Daily typing avoided")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                HelpTipButton(
                    title: "Daily typing avoided",
                    text: "Estimated typing time avoided each day, based on transcribed words at ~\(Int(VoiceTranscriptionUsageStats.manualTypingWordsPerMinute)) WPM.",
                    systemImage: "info.circle"
                )
            }

            if hasActivity {
                chartContent
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No activity this week")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: chartHeight + 74)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
        }
    }

    private var chartContent: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .trailing) {
                Text("min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 20, alignment: .top)

                VStack(alignment: .trailing) {
                    ForEach(yAxisLabels, id: \.self) { value in
                        Text(value.formatted())
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if value != yAxisLabels.last {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(height: chartHeight)
            }
            .frame(width: 34)

            VStack(spacing: 10) {
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        ForEach(0..<6, id: \.self) { index in
                            Rectangle()
                                .fill(Color(nsColor: .separatorColor).opacity(0.35))
                                .frame(height: 1)
                            if index < 5 {
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    HStack(alignment: .bottom, spacing: 16) {
                        ForEach(days) { day in
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor,
                                            Color.accentColor.opacity(0.34)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: 32, height: barHeight(for: day))
                                .opacity(day.estimatedTimeSavedDuration > 0 ? 1 : 0)
                                .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                    }
                }
                .frame(height: chartHeight)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.65))
                        .frame(width: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor).opacity(0.65))
                        .frame(height: 1)
                }

                HStack(spacing: 16) {
                    ForEach(days) { day in
                        Text(dayLabel(for: day))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 16) {
                    ForEach(days) { day in
                        if day.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.green)
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("·")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    private func barHeight(for day: VoiceDailySavedTimeStats) -> CGFloat {
        guard maxMinutes > 0 else { return 0 }
        let minutes = day.estimatedTimeSavedDuration / 60
        return CGFloat(minutes / maxMinutes) * chartHeight
    }

    private func dayLabel(for day: VoiceDailySavedTimeStats) -> String {
        let index = min(max(day.weekdayIndex, 0), dayLabels.count - 1)
        return dayLabels[index]
    }
}

private struct HomeMilestoneProgress: View {
    let milestone: VoiceUsageMilestone?

    private var progress: Double {
        milestone?.progress ?? 1
    }

    private var title: String {
        guard let milestone else {
            return "All-time milestones unlocked"
        }
        return "All-time milestone: \(milestone.title)"
    }

    private var value: String {
        guard let milestone else {
            return "Complete"
        }
        let percent = Int((milestone.progress * 100).rounded())
        return
            "\(HomeFormatting.milestoneValue(milestone.currentValue, unit: milestone.unit)) / \(HomeFormatting.milestoneValue(milestone.targetValue, unit: milestone.unit)) (\(percent)%)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, proxy.size.width * CGFloat(progress)))
                }
            }
            .frame(height: 11)
            .accessibilityValue(value)
        }
    }
}

private enum HomeFormatting {
    static func plural(_ singular: String, count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }

    static func savedTimeMetric(_ duration: TimeInterval) -> String {
        guard duration >= 60 else {
            return duration > 0 ? "<1 minute" : "0 minutes"
        }

        let totalMinutes = max(1, Int((duration / 60).rounded()))
        if totalMinutes < 60 {
            return "\(totalMinutes.formatted()) \(plural("minute", count: totalMinutes))"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard minutes > 0 else {
            return "\(hours.formatted()) \(plural("hour", count: hours))"
        }
        return "\(hours.formatted())h \(minutes)m"
    }

    static func savedMinutes(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int((duration / 60).rounded()))
        return "\(minutes.formatted()) min"
    }

    static func compactDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return seconds > 0 ? "\(seconds)s" : "0m"
    }

    static func milestoneValue(_ value: Int, unit: String) -> String {
        guard unit == "seconds" else {
            return "\(value.formatted()) \(unit)"
        }
        return compactDuration(TimeInterval(value))
    }
}

private struct ShortcutLimitNotice: View {
    var body: some View {
        Text("Some shortcuts are reserved by macOS or app menus. Try Control or Command with a letter.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ModesSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var saveError: String?
    private let modesDescription =
        "Choose how VoicePen handles dictation in the active app. Connect an AI provider first for full supported command parsing."

    private var currentConfig: UserConfig {
        controller.userConfigLoadResult.config
    }

    private var developerModeSelection: Binding<DeveloperMode> {
        Binding(
            get: { settingsStore.developerModeOverride ?? .auto },
            set: { controller.updateDeveloperModeOverride($0) }
        )
    }

    private var parserEnabled: Binding<Bool> {
        Binding(
            get: { currentConfig.developer.intentParser.enabled },
            set: { newValue in
                persistDeveloperIntentParserSettings { config in
                    config.enabled = newValue
                }
            }
        )
    }

    private var confidenceThreshold: Binding<Double> {
        Binding(
            get: { currentConfig.developer.intentParser.confidenceThreshold },
            set: { newValue in
                persistDeveloperIntentParserSettings { config in
                    config.confidenceThreshold = newValue
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Text(modesDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("Current mode", selection: developerModeSelection) {
                    ForEach(DeveloperMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Mode")
            }

            ForEach(DeveloperMode.allCases) { mode in
                Section {
                    modeSectionContent(for: mode)
                } header: {
                    Text(mode.displayName)
                }
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Status")
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }

    @ViewBuilder
    private func modeSectionContent(for mode: DeveloperMode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode.userDescription)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)

        if mode == .developer {
            Divider()
            developerCommandParsingControls
        }
    }

    private var developerCommandParsingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Use AI for supported developer commands", isOn: parserEnabled)

            LabeledContent("Confidence threshold") {
                HStack(spacing: 10) {
                    Slider(value: confidenceThreshold, in: 0...1, step: 0.05)
                        .frame(width: 220)
                    Text(currentConfig.developer.intentParser.confidenceThreshold.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
            }

            Text("AI provider settings only connect the model. This switch decides whether developer contexts may use AI for short supported command phrases.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func persistDeveloperIntentParserSettings(_ update: (inout DeveloperIntentParserConfig) -> Void) {
        do {
            try controller.updateDeveloperIntentParserSettings(update)
            saveError = nil
        } catch {
            saveError = "Mode settings could not be saved: \(error.localizedDescription)"
        }
    }
}

struct AISettingsView: View {
    @ObservedObject var controller: AppController
    @State private var saveError: String?
    @State private var ollamaAvailability: OllamaAvailabilityViewState = .checking

    private var currentConfig: UserConfig {
        controller.userConfigLoadResult.config
    }

    private var ollamaAvailabilityTaskID: String {
        "\(currentConfig.llm.provider.rawValue)|\(currentConfig.llm.ollama.baseURL)"
    }

    private var provider: Binding<LLMProvider> {
        Binding(
            get: { currentConfig.llm.provider },
            set: { newValue in
                persistAIProviderSelection(newValue)
            }
        )
    }

    private var ollamaBaseURL: Binding<String> {
        Binding(
            get: { currentConfig.llm.ollama.baseURL },
            set: { newValue in
                persistAISettings { config in
                    config.ollama.baseURL = newValue
                }
            }
        )
    }

    private var ollamaModel: Binding<String> {
        Binding(
            get: { currentConfig.llm.ollama.model },
            set: { newValue in
                persistAISettings { config in
                    config.ollama.model = newValue
                }
            }
        )
    }

    private var openRouterBaseURL: Binding<String> {
        Binding(
            get: { currentConfig.llm.openrouter.baseURL },
            set: { newValue in
                persistAISettings { config in
                    config.openrouter.baseURL = newValue
                }
            }
        )
    }

    private var openRouterModel: Binding<String> {
        Binding(
            get: { currentConfig.llm.openrouter.model },
            set: { newValue in
                persistAISettings { config in
                    config.openrouter.model = newValue
                }
            }
        )
    }

    private var openRouterAPIKey: Binding<String> {
        Binding(
            get: { currentConfig.llm.openrouter.apiKey },
            set: { newValue in
                persistAISettings { config in
                    config.openrouter.apiKey = newValue
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: provider) {
                    Text("Ollama").tag(LLMProvider.ollama)
                    Text("OpenRouter").tag(LLMProvider.openrouter)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("AI Provider")
            } footer: {
                Text("Provider settings prepare VoicePen to use structured AI features. They do not send dictation anywhere by themselves.")
            }

            if currentConfig.llm.provider == .ollama {
                Section {
                    OllamaAvailabilityRow(status: ollamaAvailability) {
                        Task {
                            await refreshOllamaAvailability(debounce: false)
                        }
                    }
                    TextField("Base URL", text: ollamaBaseURL)
                    TextField("Model", text: ollamaModel)
                } header: {
                    Text("Ollama")
                } footer: {
                    Text("Advanced Ollama options are edited in TOML config.")
                }
            } else {
                Section {
                    TextField("Base URL", text: openRouterBaseURL)
                    TextField("Model", text: openRouterModel)
                    SecureField("API key", text: openRouterAPIKey)
                } header: {
                    Text("OpenRouter")
                } footer: {
                    Text("Advanced provider options are edited in TOML config.")
                }
            }

            if let saveError {
                Section {
                    Text(saveError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Status")
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .task(id: ollamaAvailabilityTaskID) {
            await refreshOllamaAvailability(debounce: true)
        }
    }

    private func persistAISettings(_ update: (inout LLMConfig) -> Void) {
        do {
            try controller.updateLLMSettings(update)
            saveError = nil
        } catch {
            saveError = "AI settings could not be saved: \(error.localizedDescription)"
        }
    }

    private func persistAIProviderSelection(_ provider: LLMProvider) {
        Task { @MainActor in
            await Task.yield()
            persistAISettings { config in
                config.provider = provider
            }
        }
    }

    @MainActor
    private func refreshOllamaAvailability(debounce: Bool) async {
        guard currentConfig.llm.provider == .ollama else {
            ollamaAvailability = .checking
            return
        }

        let ollamaConfig = currentConfig.llm.ollama
        ollamaAvailability = .checking

        if debounce {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
        }

        let timeoutSeconds = min(max(ollamaConfig.timeoutSeconds, 0.5), 2)
        let result = await OllamaAvailabilityClient().check(
            baseURL: ollamaConfig.baseURL,
            timeoutSeconds: timeoutSeconds
        )
        guard !Task.isCancelled else { return }

        ollamaAvailability = OllamaAvailabilityViewState(result)
    }
}

private struct OllamaAvailabilityRow: View {
    let status: OllamaAvailabilityViewState
    let refresh: () -> Void

    var body: some View {
        HStack {
            Label(status.title, systemImage: status.systemImage)
                .foregroundStyle(status.color)

            Spacer()

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Check Ollama availability")
            .accessibilityLabel("Check Ollama availability")
        }
    }
}

private enum OllamaAvailabilityViewState: Equatable {
    case checking
    case available
    case unavailable(String)

    init(_ availability: OllamaAvailability) {
        switch availability {
        case .available:
            self = .available
        case let .unavailable(message):
            self = .unavailable(message)
        }
    }

    var title: String {
        switch self {
        case .checking:
            return "Checking Ollama"
        case .available:
            return "Ollama available"
        case .unavailable:
            return "Ollama unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .checking:
            return "clock"
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .checking:
            return .secondary
        case .available:
            return .green
        case .unavailable:
            return .red
        }
    }
}

struct ConfigSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var isConfigReloaded = false
    @State private var configReloadFeedbackTask: Task<Void, Never>?

    private var hotkeyPreference: Binding<HotkeyPreference> {
        Binding(
            get: { settingsStore.hotkeyPreference },
            set: { controller.updateHotkeyPreference($0) }
        )
    }

    private var holdDuration: Binding<Double> {
        Binding(
            get: { settingsStore.hotkeyHoldDuration },
            set: { controller.updateHotkeyHoldDuration($0) }
        )
    }

    private var boostDictationInputGain: Binding<Bool> {
        Binding(
            get: { settingsStore.boostDictationInputGain },
            set: { controller.updateBoostDictationInputGain($0) }
        )
    }

    private var meetingVoiceLevelingEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.meetingVoiceLevelingEnabled },
            set: { controller.updateMeetingVoiceLevelingEnabled($0) }
        )
    }

    private var saveDictationAudioEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.saveDictationAudioEnabled },
            set: { controller.updateSaveDictationAudioEnabled($0) }
        )
    }

    private var saveMeetingAudioEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.saveMeetingAudioEnabled },
            set: { controller.updateSaveMeetingAudioEnabled($0) }
        )
    }

    private var savedAudioStorageLimitGB: Binding<Double> {
        Binding(
            get: { Double(settingsStore.savedAudioStorageLimitGB) },
            set: { controller.updateSavedAudioStorageLimitGB(Int($0.rounded())) }
        )
    }

    private var meetingTranscriptTimecodesEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.meetingTranscriptTimecodesEnabled },
            set: { controller.updateMeetingTranscriptTimecodesEnabled($0) }
        )
    }

    private var meetingDiarizationEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.meetingDiarizationEnabled },
            set: { controller.updateMeetingDiarizationEnabled($0) }
        )
    }

    private var meetingSystemAudioSourceMode: Binding<MeetingSystemAudioSourceMode> {
        Binding(
            get: { settingsStore.meetingSystemAudioSourceMode },
            set: scheduleMeetingSystemAudioSourceModeUpdate
        )
    }

    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { settingsStore.openAtLogin },
            set: { controller.updateOpenAtLogin($0) }
        )
    }

    private var appAppearanceMode: Binding<AppAppearanceMode> {
        Binding(
            get: { settingsStore.appAppearanceMode },
            set: { controller.updateAppAppearanceMode($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open VoicePen at login", isOn: openAtLogin)
            } header: {
                Text("Launch")
            }

            Section {
                Picker("Theme", selection: appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            PermissionsSettingsSection(controller: controller)

            Section {
                Picker("Push-to-talk hotkey", selection: hotkeyPreference) {
                    ForEach(HotkeyPreference.allCases) { preference in
                        Text(preference.displayName)
                            .tag(preference)
                    }
                }
                .pickerStyle(.menu)

                if settingsStore.hotkeyPreference == .custom {
                    LabeledContent {
                        KeyboardShortcuts.Recorder(for: .voicePenPushToTalk) { _ in
                            Task { @MainActor in
                                controller.customHotkeyDidChange()
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Custom shortcut")
                            ShortcutLimitNotice()
                        }
                    }
                }

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(
                            value: holdDuration,
                            in: VoicePenConfig.minimumHotkeyHoldDuration...VoicePenConfig.maximumHotkeyHoldDuration,
                            step: 0.05
                        )
                        .frame(width: 220)
                        Text(settingsStore.hotkeyHoldDuration, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Hold duration")
                        HelpTipButton(
                            title: "Hold duration",
                            text: "Recording starts only after the selected shortcut is held for the configured duration. Release it to transcribe and insert text."
                        )
                    }
                }
            } header: {
                Text("Shortcut")
            }

            Section {
                Toggle("Boost microphone level during dictation", isOn: boostDictationInputGain)
                Toggle("Meeting voice leveling", isOn: meetingVoiceLevelingEnabled)
                Picker("System Audio Source", selection: meetingSystemAudioSourceMode) {
                    ForEach(MeetingSystemAudioSourceMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if settingsStore.meetingSystemAudioSourceMode != .all {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Selected apps")
                            Spacer()
                            Button {
                                controller.chooseMeetingSystemAudioApp()
                            } label: {
                                Label("Add Apps", systemImage: "plus")
                            }
                        }

                        if settingsStore.meetingAudioAppSelections.isEmpty {
                            Text("No apps selected")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(settingsStore.meetingAudioAppSelections) { app in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(app.displayName)
                                        Text(app.bundleIdentifier)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button {
                                        controller.removeMeetingSystemAudioApp(
                                            bundleIdentifier: app.bundleIdentifier
                                        )
                                    } label: {
                                        Label("Remove App", systemImage: "minus.circle")
                                    }
                                    .labelStyle(.iconOnly)
                                    .help("Remove App")
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Audio")
            } footer: {
                Text(
                    "VoicePen uses the macOS default microphone. Dictation can temporarily raise supported input levels while recording. Meeting audio can use system dynamics and peak limiting before local transcription; if processing is unavailable, VoicePen continues with ordinary audio. Meeting system audio can capture all apps, only selected apps, or all apps except selected apps."
                )
            }

            Section {
                Toggle("Save dictation recordings", isOn: saveDictationAudioEnabled)
                Toggle("Save meeting recordings", isOn: saveMeetingAudioEnabled)

                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(
                            value: savedAudioStorageLimitGB,
                            in: Double(VoicePenConfig.minimumSavedAudioStorageLimitGB)...Double(VoicePenConfig.maximumSavedAudioStorageLimitGB),
                            step: 1
                        )
                        .frame(width: 220)
                        Text("\(settingsStore.savedAudioStorageLimitGB) GB")
                            .monospacedDigit()
                            .frame(width: 54, alignment: .trailing)
                    }
                } label: {
                    Text("Storage limit")
                }

                Button {
                    controller.openSavedRecordingsFolder()
                } label: {
                    Label("Open Recordings Folder", systemImage: "folder")
                }
            } header: {
                Text("Saved recordings")
            } footer: {
                Text(
                    "When enabled, VoicePen copies local audio files into Application Support so you can open or copy them later. Saving audio never changes transcription or history behavior."
                )
            }

            Section {
                Toggle(isOn: meetingTranscriptTimecodesEnabled) {
                    configSettingLabel(
                        "Meeting transcript timecodes",
                        help: "Adds meeting-relative timecodes to the transcript."
                    )
                }

                Toggle(isOn: meetingDiarizationEnabled) {
                    configSettingLabel(
                        "Meeting diarization",
                        help: "Adds experimental offline speaker labels for Meeting Mode with a separate local diarization model."
                    )
                }
            } header: {
                Text("Meeting features")
            }

            Section {
                LabeledContent("Path", value: controller.userConfigURL.path)
                LabeledContent(
                    "Status",
                    value: controller.userConfigLoadResult.diagnosticNotes.isEmpty ? "Loaded" : "Using last valid config"
                )

                HStack {
                    Button {
                        controller.reloadUserConfig()
                        showConfigReloadedFeedback()
                    } label: {
                        ZStack {
                            Label("Reload Config", systemImage: "arrow.clockwise")
                                .opacity(isConfigReloaded ? 0 : 1)
                            Label("Reloaded", systemImage: "checkmark")
                                .opacity(isConfigReloaded ? 1 : 0)
                        }
                        .accessibilityHidden(true)
                    }
                    .foregroundStyle(isConfigReloaded ? .green : .primary)
                    .help(isConfigReloaded ? "Config reloaded" : "Reload Config")
                    .accessibilityLabel(isConfigReloaded ? "Config reloaded" : "Reload Config")

                    Button {
                        controller.openUserConfigFile()
                    } label: {
                        Label("Open Config File", systemImage: "doc.text")
                    }
                }
            } header: {
                Text("Config file")
            } footer: {
                Text("Dictation reloads this TOML file automatically. Reload Config refreshes settings displays and environment values immediately.")
            }

            if !controller.userConfigLoadResult.diagnosticNotes.isEmpty {
                Section {
                    ForEach(controller.userConfigLoadResult.diagnosticNotes, id: \.self) { note in
                        Text(note)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Diagnostics")
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                controller.reloadUserConfig()
            }
        }
        .onDisappear {
            configReloadFeedbackTask?.cancel()
        }
    }

    private func scheduleMeetingSystemAudioSourceModeUpdate(_ mode: MeetingSystemAudioSourceMode) {
        Task { @MainActor in
            await Task.yield()
            controller.updateMeetingSystemAudioSourceMode(mode)
        }
    }

    private func showConfigReloadedFeedback() {
        isConfigReloaded = true
        configReloadFeedbackTask?.cancel()
        configReloadFeedbackTask = Task {
            try? await Task.sleep(for: VoicePenConfig.historyCopyFeedbackDuration)
            await MainActor.run {
                isConfigReloaded = false
            }
        }
    }

    private func configSettingLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            HelpTipButton(title: title, text: help)
        }
    }
}

private struct PermissionsSettingsSection: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Section {
            LabeledContent("Microphone", value: controller.microphonePermissionTitle)
            LabeledContent("System Audio", value: controller.systemAudioPermissionTitle)
            LabeledContent("Text insertion", value: controller.accessibilityPermissionTitle)
            LabeledContent("Bundle ID", value: controller.runningBundleIdentifier)
            LabeledContent("Running app", value: controller.runningAppPath)

            HStack {
                Button {
                    controller.requestMicrophonePermission()
                } label: {
                    Label("Request Microphone", systemImage: "mic")
                }

                Button {
                    controller.requestSystemAudioRecordingPermission()
                } label: {
                    Label("Open System Audio Settings", systemImage: "waveform")
                }

                Button {
                    controller.requestAccessibilityPermission()
                } label: {
                    Label("Open Accessibility Settings", systemImage: "hand.raised")
                }

                Button {
                    controller.refreshPermissionState()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text(
                "Text insertion uses macOS Accessibility permission for Cmd-V. VoicePen works offline, has 0 analytics, and sends no voice data anywhere."
            )
        }
    }
}

struct ModelSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settingsStore: AppSettingsStore
    @State private var showingDownloadConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingDiarizationDownloadConfirmation = false
    @State private var showingDiarizationDeleteConfirmation = false

    private var languageSelection: Binding<String> {
        Binding(
            get: { settingsStore.transcriptionLanguage },
            set: { controller.updateTranscriptionLanguage($0) }
        )
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { settingsStore.selectedModelId },
            set: { controller.updateSelectedModelId($0) }
        )
    }

    private var speechPreprocessingSelection: Binding<SpeechPreprocessingMode> {
        Binding(
            get: { settingsStore.speechPreprocessingMode },
            set: { controller.updateSpeechPreprocessingMode($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: modelSelection) {
                    ForEach(controller.modelManifest.compatibleModels) { model in
                        Text(model.displayName)
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("Model ID", value: controller.selectedModel.id)
                LabeledContent("Languages", value: controller.selectedModel.languageSupportLabel)
                LabeledContent("Backend", value: controller.selectedModel.sourceKind)
                LabeledContent("Version", value: controller.selectedModel.version)
                LabeledContent("Size", value: controller.selectedModel.sizeLabel)
                LabeledContent("Status", value: controller.isModelInstalled ? "Installed" : "Missing")
                LabeledContent("Acceleration", value: controller.modelAccelerationStatus.accelerationSummary)
                LabeledContent(controller.modelAccelerationStatus.model.displayName) {
                    artifactStatusLabel(controller.modelAccelerationStatus.model)
                }
                ForEach(controller.modelAccelerationStatus.companionArtifacts) { artifact in
                    LabeledContent(artifact.displayName) {
                        artifactStatusLabel(artifact)
                    }
                }
                LabeledContent("Install path", value: controller.userModelDirectory.path)

                if controller.isDownloadingModel {
                    modelDownloadProgressView
                }

                HStack {
                    if controller.isDownloadingModel {
                        Button(role: .cancel) {
                            controller.cancelModelDownload()
                        } label: {
                            Label("Cancel Download", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            showingDownloadConfirmation = true
                        } label: {
                            Label("Download Model", systemImage: "arrow.down.circle")
                        }
                        .disabled(controller.isModelInstalled)
                    }

                    Button {
                        controller.openModelFolder()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }

                    CopyButton(
                        title: "Copy Diagnostics",
                        systemImage: "stethoscope",
                        presentation: .label
                    ) {
                        controller.copyModelDiagnostics()
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Files", systemImage: "trash")
                    }
                    .disabled(controller.isDownloadingModel || !controller.hasDownloadedModelFiles)
                }
            }

            Section {
                Picker(selection: languageSelection) {
                    ForEach(AppSettingsStore.supportedLanguages) { language in
                        Text(language.displayName)
                            .tag(language.code)
                    }
                } label: {
                    recognitionSettingLabel(
                        "Primary language",
                        help: "Auto-detect is recommended for multilingual dictation. Choosing one language can be faster and more predictable when you know what you will speak."
                    )
                }
                .pickerStyle(.menu)

                Picker(selection: speechPreprocessingSelection) {
                    ForEach(SpeechPreprocessingMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                } label: {
                    recognitionSettingLabel(
                        "Speech preprocessing",
                        help: "Slower preprocessing can help with fast speech, but it increases transcription time."
                    )
                }
                .pickerStyle(.menu)
            } header: {
                Text("Recognition")
            }

            Section {
                LabeledContent("Status", value: controller.meetingDiarizationModelStatusTitle)
                LabeledContent("Install path", value: controller.meetingDiarizationModelDirectory.path)

                if controller.isDownloadingMeetingDiarizationModel {
                    meetingDiarizationModelDownloadProgressView
                }

                HStack {
                    if controller.isDownloadingMeetingDiarizationModel {
                        Button(role: .cancel) {
                            controller.cancelMeetingDiarizationModelDownload()
                        } label: {
                            Label("Cancel Download", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            showingDiarizationDownloadConfirmation = true
                        } label: {
                            Label("Download Model", systemImage: "arrow.down.circle")
                        }
                        .disabled(controller.isMeetingDiarizationModelInstalled)
                    }

                    Button(role: .destructive) {
                        showingDiarizationDeleteConfirmation = true
                    } label: {
                        Label("Delete Files", systemImage: "trash")
                    }
                    .disabled(
                        controller.isDownloadingMeetingDiarizationModel
                            || !controller.isMeetingDiarizationModelInstalled
                    )
                }
            } header: {
                Text("Meeting diarization")
            }

        }
        .formStyle(.grouped)
        .padding(18)
        .alert("Download transcription model?", isPresented: $showingDownloadConfirmation) {
            Button("Download") {
                controller.downloadModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("VoicePen will download \(controller.selectedModel.displayName) to Application Support.")
        }
        .alert("Delete downloaded model files?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                controller.deleteDownloadedModelFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("VoicePen will remove downloaded files for \(controller.selectedModel.displayName). Bundled app resources will not be deleted.")
        }
        .alert("Download meeting diarization model?", isPresented: $showingDiarizationDownloadConfirmation) {
            Button("Download") {
                controller.downloadMeetingDiarizationModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("VoicePen will download local VAD and speaker embedding files for Meeting Mode.")
        }
        .alert("Delete meeting diarization model files?", isPresented: $showingDiarizationDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                controller.deleteMeetingDiarizationModelFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("VoicePen will remove downloaded Meeting diarization files. Transcription models are not affected.")
        }
    }

    private func recognitionSettingLabel(_ title: String, help: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            HelpTipButton(title: title, text: help)
        }
    }

    @ViewBuilder
    private var modelDownloadProgressView: some View {
        if let progress = controller.modelDownloadProgress {
            ProgressView(value: progress, total: 1.0) {
                Text(controller.appState.menuTitle)
            }
            .progressViewStyle(.linear)
        } else {
            ProgressView {
                Text(controller.appState.menuTitle)
            }
            .progressViewStyle(.linear)
        }
    }

    @ViewBuilder
    private var meetingDiarizationModelDownloadProgressView: some View {
        if let progress = controller.meetingDiarizationModelDownloadProgress {
            ProgressView(value: progress, total: 1.0) {
                Text("Downloading Meeting diarization model")
            }
            .progressViewStyle(.linear)
        } else {
            ProgressView("Downloading Meeting diarization model")
        }
    }

    private func artifactStatusLabel(_ status: ModelArtifactStatus) -> some View {
        Label(
            status.isPresent ? "OK" : "Missing",
            systemImage: status.isPresent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(status.isPresent ? .green : .orange)
    }
}

private struct HelpTipButton: View {
    let title: String
    let text: String
    let systemImage: String
    @State private var isShowingHelp = false

    init(title: String, text: String, systemImage: String = "questionmark.circle") {
        self.title = title
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) help")
        .accessibilityHint(text)
        .onHover { isHovering in
            isShowingHelp = isHovering
        }
        .popover(isPresented: $isShowingHelp, arrowEdge: .trailing) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(width: 280, alignment: .leading)
        }
    }
}
