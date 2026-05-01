import KeyboardShortcuts
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VoicePenMainWindow: View {
    @ObservedObject var controller: AppController
    @State private var selectedSection: VoicePenSettingsSection? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("VoicePen")
                                .font(.system(size: 14, weight: .semibold))

                            Text(controller.appState.menuTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section("Settings") {
                    ForEach(VoicePenSettingsSection.allCases) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("VoicePen")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            if let selectedSection {
                detailView(for: selectedSection)
                    .navigationTitle(selectedSection.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a section",
                    systemImage: "sidebar.left",
                    description: Text("VoicePen settings will appear here.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 560)
    }

    @ViewBuilder
    private func detailView(for section: VoicePenSettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(controller: controller, historyStore: controller.historyStore)
        case .permissions:
            PermissionsSettingsView(controller: controller)
        case .model:
            ModelSettingsView(controller: controller, settingsStore: controller.settingsStore)
        case .shortcuts:
            ShortcutsSettingsView(controller: controller, settingsStore: controller.settingsStore)
        case .dictionary:
            DictionaryEditorView(controller: controller, dictionaryStore: controller.dictionaryStore)
        case .history:
            HistoryView(controller: controller, historyStore: controller.historyStore)
        }
    }
}

private enum VoicePenSettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case permissions
    case model
    case shortcuts
    case dictionary
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .permissions:
            return "Permissions"
        case .model:
            return "Model"
        case .shortcuts:
            return "Shortcuts"
        case .dictionary:
            return "Dictionary"
        case .history:
            return "History"
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
        case .shortcuts:
            return "keyboard"
        case .dictionary:
            return "text.book.closed"
        case .history:
            return "clock.arrow.circlepath"
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore

    private var stats: VoiceTranscriptionUsageStats {
        historyStore.usageStats
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stats.clockText)
                        .font(.system(size: 52, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text("Transcribed audio time")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }

            Section {
                LabeledContent("Status", value: controller.appState.menuTitle)
                LabeledContent("Privacy", value: "Offline only, 0 analytics")
                LabeledContent("History database", value: controller.historyURL.path)
                Toggle("Open VoicePen at login", isOn: Binding(
                    get: { controller.settingsStore.openAtLogin },
                    set: { controller.updateOpenAtLogin($0) }
                ))
            } header: {
                Text("App")
            } footer: {
                Text("VoicePen records only while the push-to-talk shortcut is held. Audio and text stay on this Mac.")
            }

            Section {
                LabeledContent("Sessions counted", value: "\(stats.transcribedSessionCount)")
            } header: {
                Text("Usage")
            } footer: {
                Text("Only completed transcriptions with non-empty text are counted. Failed and empty sessions are ignored.")
            }
        }
        .formStyle(.grouped)
        .padding(18)
    }
}

private struct ShortcutsSettingsView: View {
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
                        KeyboardShortcuts.Recorder(for: .voicePenPushToTalk)
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

private struct PermissionsSettingsView: View {
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

private struct ModelSettingsView: View {
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
                Text("Auto-detect is recommended for multilingual dictation. Use Russian or English only when you want to force Whisper into that language. Slower preprocessing can help with fast speech, but it increases transcription time.")
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

private struct DictionaryEditorView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var dictionaryStore: DictionaryStore
    @State private var selectedID: String?
    @State private var draft = TermEntryDraft()
    @State private var message: String?
    @State private var showingDeleteConfirmation = false

    private var selectedEntry: TermEntry? {
        guard let selectedID else { return dictionaryStore.entries.first }
        return dictionaryStore.entries.first { $0.id == selectedID } ?? dictionaryStore.entries.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Terms")
                        .font(.headline)

                    Spacer()

                    Button {
                        createNewEntry()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }

                    Button {
                        importDictionaryCSV()
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }
                }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

                List(selection: $selectedID) {
                    ForEach(dictionaryStore.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.canonical)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)

                            Text("\(entry.variants.count) variants")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(entry.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)

            Divider()

            Form {
                Section {
                    TextField("Canonical", text: $draft.canonical)
                } header: {
                    Text("Term")
                }

                Section {
                    DictionaryListEditor(title: "Variants", text: $draft.variantsText)
                } footer: {
                    Text("Use one value per line. These are all forms VoicePen should replace with the canonical term.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Large dictionaries can slow down every transcription.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline.weight(.semibold))

                        Text("As a rule of thumb: up to 100 terms is small, 100-500 is usually fine, 500+ can become noticeable, and 1,000+ should be split or trimmed.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Text("Current dictionary: \(dictionaryStore.entries.count) terms.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Performance")
                }

                Section {
                    Button {
                        importDictionaryCSV()
                    } label: {
                        Label("Import CSV or Text File", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("CSV format: canonical, variants. Separate variants with semicolons, or put each variant in its own column.")
                }

                Section {
                    HStack {
                        Button {
                            saveDraft()
                        } label: {
                            Label("Save Term", systemImage: "square.and.arrow.down")
                        }
                        .disabled(!draft.isValid)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(draft.id.isEmpty || !dictionaryStore.entries.contains { $0.id == draft.id })

                        Spacer()

                        Button {
                            controller.openDictionaryFile()
                        } label: {
                            Label("Reveal Database", systemImage: "folder")
                        }
                    }

                    if let message {
                        Text(message)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(18)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = dictionaryStore.entries.first?.id
            }
            loadSelectedEntry()
        }
        .onChange(of: selectedID) { _, _ in
            loadSelectedEntry()
        }
        .onChange(of: dictionaryStore.entries) { _, entries in
            guard !entries.contains(where: { $0.id == selectedID }) else { return }
            selectedID = entries.first?.id
            loadSelectedEntry()
        }
        .alert("Delete dictionary term?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(draft.canonical.isEmpty ? "this term" : draft.canonical) from the local dictionary.")
        }
    }

    private func loadSelectedEntry() {
        guard let selectedEntry else {
            draft = TermEntryDraft()
            return
        }
        draft = TermEntryDraft(entry: selectedEntry)
    }

    private func createNewEntry() {
        selectedID = nil
        draft = TermEntryDraft(
            id: UUID().uuidString,
            canonical: "",
            variantsText: ""
        )
        message = nil
    }

    private func saveDraft() {
        do {
            let entry = draft.makeEntry()
            try dictionaryStore.upsertEntry(entry)
            selectedID = entry.id
            message = "Saved"
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteDraft() {
        do {
            try dictionaryStore.deleteEntry(id: draft.id)
            selectedID = dictionaryStore.entries.first?.id
            message = "Deleted"
        } catch {
            message = error.localizedDescription
        }
    }

    private func importDictionaryCSV() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let entries = try DictionaryCSVImporter.parse(fileURL: url)
            try dictionaryStore.importEntries(entries)
            selectedID = entries.first?.id ?? dictionaryStore.entries.first?.id
            message = "Imported \(entries.count) terms"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct DictionaryListEditor: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextEditor(text: $text)
                .font(.system(.body, design: .default))
                .frame(minHeight: 58, maxHeight: 86)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.22), lineWidth: 1)
                }
        }
    }
}

private struct TermEntryDraft: Equatable {
    var id = ""
    var canonical = ""
    var variantsText = ""

    init() {}

    init(
        id: String,
        canonical: String,
        variantsText: String
    ) {
        self.id = id
        self.canonical = canonical
        self.variantsText = variantsText
    }

    init(entry: TermEntry) {
        id = entry.id
        canonical = entry.canonical
        variantsText = entry.variants.joined(separator: "\n")
    }

    var isValid: Bool {
        !canonical.trimmed.isEmpty
    }

    func makeEntry() -> TermEntry {
        return TermEntry(
            id: id.trimmed.isEmpty ? UUID().uuidString : id.trimmed,
            canonical: canonical.trimmed,
            variants: split(variantsText)
        )
    }

    private func split(_ value: String) -> [String] {
        value
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
    }
}

private struct HistoryView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    @State private var selectedID: VoiceHistoryEntry.ID?
    @State private var showingClearConfirmation = false
    @State private var entryPendingDeletion: VoiceHistoryEntry?

    private var selectedEntry: VoiceHistoryEntry? {
        guard let selectedID else {
            return historyStore.entries.first
        }
        return historyStore.entries.first { $0.id == selectedID } ?? historyStore.entries.first
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sessions")
                        .font(.headline)

                    Spacer()

                    Button {
                        controller.openHistoryFile()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }

                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(historyStore.entries.isEmpty)
                }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

                if historyStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No voice sessions yet",
                        systemImage: "mic",
                        description: Text("Finished dictations will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedID) {
                        ForEach(historyStore.entries) { entry in
                            HistoryRowView(
                                entry: entry,
                                deleteAction: {
                                    entryPendingDeletion = entry
                                }
                            )
                                .tag(entry.id)
                        }
                        .onDelete { offsets in
                            deleteEntries(at: offsets)
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            Divider()

            HistoryDetailView(
                controller: controller,
                entry: selectedEntry
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedID = selectedID ?? historyStore.entries.first?.id
        }
        .onChange(of: historyStore.entries) { _, entries in
            guard !entries.contains(where: { $0.id == selectedID }) else { return }
            selectedID = entries.first?.id
        }
        .alert("Clear voice history?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                controller.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes saved transcription history from VoicePen.")
        }
        .alert("Delete voice session?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let entryPendingDeletion {
                    controller.deleteHistoryEntry(id: entryPendingDeletion.id)
                }
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            Text("This removes only the selected saved transcription.")
        }
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { entryPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    entryPendingDeletion = nil
                }
            }
        )
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            guard historyStore.entries.indices.contains(index) else { continue }
            controller.deleteHistoryEntry(id: historyStore.entries[index].id)
        }
    }
}

private struct HistoryRowView: View {
    let entry: VoiceHistoryEntry
    let deleteAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Label(entry.status.title, systemImage: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)

                Spacer()

                Text(entry.createdAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .disabled(!isHovered)
                .help("Delete session")
            }

            Text(entry.previewText)
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(entry.createdAt, style: .date)

                if let duration = entry.duration {
                    Text(formatDuration(duration))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var iconName: String {
        switch entry.status {
        case .insertAttempted:
            return "checkmark.circle"
        case .empty:
            return "circle.dashed"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .insertAttempted:
            return .green
        case .empty:
            return .secondary
        case .failed:
            return .yellow
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", duration)
    }
}

private struct HistoryDetailView: View {
    @ObservedObject var controller: AppController
    let entry: VoiceHistoryEntry?

    var body: some View {
        Group {
            if let entry {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                                .font(.headline)

                            Text(detailSubtitle(for: entry))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            controller.copyToClipboard(entry.bestText)
                        } label: {
                            Label("Copy Best Text", systemImage: "doc.on.doc")
                        }
                        .disabled(entry.bestText.trimmed.isEmpty)
                    }

                    if let errorMessage = entry.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Error")
                                .font(.subheadline.weight(.semibold))
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    HistoryTextSection(
                        title: "Final text",
                        text: entry.finalText,
                        copyAction: {
                            controller.copyToClipboard(entry.finalText)
                        }
                    )

                    HistoryTextSection(
                        title: "Raw transcript",
                        text: entry.rawText,
                        copyAction: {
                            controller.copyToClipboard(entry.rawText)
                        }
                    )

                    Spacer(minLength: 0)
                }
                .padding(20)
            } else {
                ContentUnavailableView(
                    "Select a session",
                    systemImage: "text.bubble",
                    description: Text("Saved dictation text will appear here.")
                )
            }
        }
    }

    private func detailSubtitle(for entry: VoiceHistoryEntry) -> String {
        if let duration = entry.duration {
            return "\(entry.status.title) · \(String(format: "%.1fs", duration))"
        }
        return entry.status.title
    }
}

private struct HistoryTextSection: View {
    let title: String
    let text: String
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    copyAction()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(trimmedText.isEmpty)
            }

            ScrollView {
                Text(displayText)
                    .font(.system(.body, design: .default))
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 96, maxHeight: 160)
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.secondary.opacity(0.22), lineWidth: 1)
            }
        }
    }

    private var displayText: String {
        trimmedText.isEmpty ? "No text" : text
    }

    private var trimmedText: String {
        text.trimmed
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
