import Foundation
import KeyboardShortcuts
import SwiftUI

enum VoicePenSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case permissions
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
            return "General"
        case .permissions:
            return "Permissions"
        case .model:
            return "Model"
        case .modes:
            return "Modes"
        case .ai:
            return "AI"
        case .config:
            return "Config"
        case .dictionary:
            return "Dictionary"
        case .meetings:
            return "Meetings"
        case .history:
            return "History"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .permissions:
            return "hand.raised"
        case .model:
            return "arrow.down.circle"
        case .modes:
            return "terminal"
        case .ai:
            return "sparkles"
        case .config:
            return "doc.text"
        case .dictionary:
            return "text.book.closed"
        case .meetings:
            return "person.2.wave.2"
        case .history:
            return "clock.arrow.circlepath"
        case .about:
            return "info.circle"
        }
    }
}

struct AboutView: View {
    private let linkedInURL = URL(string: "https://www.linkedin.com/in/khokhlachev/")!

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
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    @ObservedObject var settingsStore: AppSettingsStore

    private var stats: VoiceTranscriptionUsageStats {
        VoiceTranscriptionUsageStats(entries: historyStore.entries)
    }

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

    private var transcribedTotalCaption: String {
        let word = stats.totalWordCount == 1 ? "word" : "words"
        let sessionWord = stats.transcribedSessionCount == 1 ? "session" : "sessions"
        return "Transcribed \(stats.totalWordCount.formatted()) \(word) in \(stats.transcribedSessionCount.formatted()) \(sessionWord)"
    }

    private var estimatedTimeSavedCaption: String {
        "Estimated versus typing the recognized text at \(Int(VoiceTranscriptionUsageStats.manualTypingWordsPerMinute)) WPM"
    }

    private var historyStorageCaption: String {
        historyStore.storageStats.formattedDiskUsageSize
    }

    private var todayWordsText: String {
        "\(stats.todayWordCount.formatted()) \(stats.todayWordCount == 1 ? "word" : "words") today"
    }

    private var streakText: String {
        "\(stats.currentStreakDayCount.formatted()) \(stats.currentStreakDayCount == 1 ? "day" : "days")"
    }

    private var bestDayText: String {
        guard let bestDay = stats.bestDay else { return "No best day yet" }
        return "\(bestDay.wordCount.formatted()) \(bestDay.wordCount == 1 ? "word" : "words") on \(bestDay.date.formatted(date: .abbreviated, time: .omitted))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stats.readableDurationText)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text(transcribedTotalCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text("≈ \(stats.readableEstimatedTimeSavedText) saved")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.top, 6)

                    Text(estimatedTimeSavedCaption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 6)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), alignment: .leading),
                            GridItem(.flexible(), alignment: .leading)
                        ],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        UsageStatView(
                            title: "Streak",
                            value: streakText,
                            caption: "Active dictation days"
                        )
                        UsageStatView(
                            title: "Today",
                            value: todayWordsText,
                            caption: "Final recognized text"
                        )
                        UsageStatView(
                            title: "Best Day",
                            value: bestDayText,
                            caption: "Most dictated words"
                        )
                        UsageStatView(
                            title: "Milestones",
                            value: stats.reachedMilestoneText,
                            caption: stats.nextMilestoneText
                        )
                    }

                    ProgressView(value: stats.nextMilestone?.progress ?? 1)
                        .tint(.accentColor)
                        .help(stats.nextMilestoneText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }

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
                LabeledContent("Status", value: controller.appState.menuTitle)
                LabeledContent("Privacy", value: "Offline only, 0 analytics")
                LabeledContent("Storage", value: historyStorageCaption)
                LabeledContent("Database", value: controller.historyURL.path)
                Toggle(
                    "Open VoicePen at login",
                    isOn: Binding(
                        get: { controller.settingsStore.openAtLogin },
                        set: { controller.updateOpenAtLogin($0) }
                    ))
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

private struct UsageStatView: View {
    let title: String
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        Form {
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

struct PermissionsSettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
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
            } footer: {
                Text("Text insertion uses macOS Accessibility permission for Cmd-V. VoicePen works offline, has 0 analytics, and sends no voice data anywhere.")
            }
        }
        .formStyle(.grouped)
        .padding(18)
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
    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
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
