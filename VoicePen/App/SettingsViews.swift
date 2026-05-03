import Foundation
import KeyboardShortcuts
import SwiftUI

enum VoicePenSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case permissions
    case model
    case modes
    case shortcuts
    case dictionary
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
        case .shortcuts:
            return "Shortcuts"
        case .dictionary:
            return "Dictionary"
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
        case .shortcuts:
            return "keyboard"
        case .dictionary:
            return "text.book.closed"
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

                    Text("VoicePen is free. It works locally on your Mac, does not send your voice or text to cloud services, and has 0 analytics.")
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

    private var stats: VoiceTranscriptionUsageStats {
        VoiceTranscriptionUsageStats(entries: historyStore.entries)
    }

    private var transcribedAudioCaption: String {
        let sessionWord = stats.transcribedSessionCount == 1 ? "session" : "sessions"
        return "Transcribed audio time in \(stats.transcribedSessionCount) \(sessionWord)"
    }

    private var estimatedTimeSavedCaption: String {
        "Estimated versus typing the recognized text at \(Int(VoiceTranscriptionUsageStats.manualTypingWordsPerMinute)) WPM"
    }

    private var historyStorageCaption: String {
        "\(historyStore.storageStats.formattedTextPayloadSize) text, \(historyStore.storageStats.formattedDatabaseFileSize) database"
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

    private var milestoneText: String {
        guard let nextMilestone = stats.nextMilestone else {
            return "All milestones unlocked"
        }
        return "Next: \(nextMilestone.title)"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stats.readableDurationText)
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text(transcribedAudioCaption)
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
                            value: stats.milestoneSummaryText,
                            caption: milestoneText
                        )
                    }

                    ProgressView(value: stats.nextMilestone?.progress ?? 1)
                        .tint(.accentColor)
                        .help(milestoneText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }

            Section {
                LabeledContent("Status", value: controller.appState.menuTitle)
                LabeledContent("Privacy", value: "Offline only, 0 analytics")
                LabeledContent("History storage", value: historyStorageCaption)
                LabeledContent("History database", value: controller.historyURL.path)
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

struct ModesSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settingsStore: AppSettingsStore
    private let modesDescription =
        "Modes tell VoicePen how to handle dictated text in different apps. Auto chooses the mode from the active app; Plain keeps dictation simple; Writing Code improves technical text; Terminal can turn configured phrases into commands. For example, in Terminal \"show git status\" becomes \"git status --short --branch\"."

    private var developerModeSelection: Binding<DeveloperMode> {
        Binding(
            get: { settingsStore.developerModeOverride ?? .auto },
            set: { controller.updateDeveloperModeOverride($0) }
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

                LabeledContent("Config file", value: controller.userConfigURL.path)

                Button {
                    controller.openUserConfigFile()
                } label: {
                    Label("Open Config File", systemImage: "doc.text")
                }
            } header: {
                Text("Mode")
            }

            Section {
                ForEach(DeveloperMode.allCases) { mode in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.displayName)
                            .font(.headline)
                        Text(mode.userDescription)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            } header: {
                Text("What Each Mode Does")
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settingsStore: AppSettingsStore

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

    var body: some View {
        Form {
            Section {
                Picker("Push-to-talk hotkey", selection: hotkeyPreference) {
                    ForEach(HotkeyPreference.allCases) { preference in
                        Text(preference.displayName)
                            .tag(preference)
                    }
                }
                .pickerStyle(.menu)

                if settingsStore.hotkeyPreference == .custom {
                    LabeledContent("Custom shortcut") {
                        KeyboardShortcuts.Recorder(for: .voicePenPushToTalk) { _ in
                            Task { @MainActor in
                                controller.customHotkeyDidChange()
                            }
                        }
                        .controlSize(.small)
                    }
                }

                LabeledContent("Hold duration") {
                    HStack(spacing: 10) {
                        Slider(value: holdDuration, in: 0.1...2.0, step: 0.05)
                            .frame(width: 220)
                        Text(settingsStore.hotkeyHoldDuration, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Recording starts only after the selected shortcut is held for the configured duration. Release it to transcribe and insert text.")
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

struct PermissionsSettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section {
                LabeledContent("Microphone", value: controller.microphonePermissionTitle)
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
                    ProgressView(
                        value: controller.modelDownloadProgress,
                        total: 1.0
                    ) {
                        Text(controller.appState.menuTitle)
                    }
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

                    Button {
                        controller.copyModelDiagnostics()
                    } label: {
                        Label("Copy Diagnostics", systemImage: "stethoscope")
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
                Picker("Primary language", selection: languageSelection) {
                    ForEach(AppSettingsStore.supportedLanguages) { language in
                        Text(language.displayName)
                            .tag(language.code)
                    }
                }
                .pickerStyle(.menu)

                Picker("Speech preprocessing", selection: speechPreprocessingSelection) {
                    ForEach(SpeechPreprocessingMode.allCases) { mode in
                        Text(mode.displayName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Recognition")
            } footer: {
                Text(
                    "Auto-detect is recommended for multilingual dictation. Use Russian or English only when you want to force Whisper into that language. Slower preprocessing can help with fast speech, but it increases transcription time."
                )
            }

            Section {
                Text(controller.selectedModel.description)
                    .foregroundStyle(.secondary)

                Text("Models are downloaded only after confirmation and then used locally for transcription.")
                    .foregroundStyle(.secondary)
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
    }

    private func artifactStatusLabel(_ status: ModelArtifactStatus) -> some View {
        Label(
            status.isPresent ? "OK" : "Missing",
            systemImage: status.isPresent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(status.isPresent ? .green : .orange)
    }
}
