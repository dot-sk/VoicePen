import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VoicePenMainWindow: View {
    @ObservedObject var controller: AppController
    @State private var selectedSection: VoicePenSettingsSection? = .general
    private var sidebarSections: [VoicePenSettingsSection] {
        var sections: [VoicePenSettingsSection] = [
            .general,
            .meetings,
            .history
        ]
        if VoicePenConfig.modesFeatureEnabled {
            sections.append(.modes)
        }
        if VoicePenConfig.aiFeatureEnabled {
            sections.append(.ai)
        }
        sections.append(contentsOf: [
            .dictionary,
            .model,
            .config,
            .permissions,
            .about
        ])
        return sections
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: controller.menuBarSystemImage)
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
                    ForEach(sidebarSections) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: systemImage(for: section))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollIndicators(.automatic)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MeetingRecordingPanel(controller: controller)
        }
        .frame(minWidth: 860, minHeight: 560)
    }

    private func systemImage(for section: VoicePenSettingsSection) -> String {
        guard section == .meetings, controller.appState.showsMeetingRecordingPanel else {
            return section.systemImage
        }

        return controller.menuBarSystemImage
    }

    @ViewBuilder
    private func detailView(for section: VoicePenSettingsSection) -> some View {
        switch section {
        case .general:
            GeneralSettingsView(
                controller: controller,
                historyStore: controller.historyStore,
                settingsStore: controller.settingsStore
            )
        case .permissions:
            PermissionsSettingsView(controller: controller)
        case .model:
            ModelSettingsView(controller: controller, settingsStore: controller.settingsStore)
        case .modes:
            ModesSettingsView(controller: controller, settingsStore: controller.settingsStore)
        case .ai:
            AISettingsView(controller: controller)
        case .config:
            ConfigSettingsView(controller: controller)
        case .dictionary:
            DictionaryEditorView(controller: controller, dictionaryStore: controller.dictionaryStore)
        case .meetings:
            if let meetingHistoryStore = controller.meetingHistoryStore {
                MeetingsView(controller: controller, meetingHistoryStore: meetingHistoryStore)
            } else {
                ContentUnavailableView(
                    "Meetings unavailable",
                    systemImage: "person.2.wave.2",
                    description: Text("Meeting recording is not configured in this build.")
                )
            }
        case .history:
            HistoryView(controller: controller, historyStore: controller.historyStore)
        case .about:
            AboutView()
        }
    }
}

private struct DictionaryEditorView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var dictionaryStore: DictionaryStore
    @State private var selectedID: String?
    @State private var isCreatingNewEntry = false
    @State private var draft = TermEntryDraft()
    @State private var message: String?
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var reviewPreset = DictionaryReviewPromptPreset.dictionaryImprovement
    @State private var historyReviewLimit = HistoryReviewLimit.defaultValue
    @State private var pendingImportPreview: PendingDictionaryImportPreview?

    private var selectedEntry: TermEntry? {
        guard !isCreatingNewEntry else { return nil }
        guard let selectedID else { return filteredEntries.first }
        return filteredEntries.first { $0.id == selectedID } ?? filteredEntries.first
    }

    private var filteredEntries: [TermEntry] {
        DictionaryEntryFilter(query: searchText)
            .filteredEntries(from: dictionaryStore.entries)
    }

    var body: some View {
        VStack(spacing: 0) {
            DictionaryReviewPanel(
                reviewPreset: $reviewPreset,
                historyReviewLimit: $historyReviewLimit,
                message: message,
                copyReviewPrompt: copyReviewPrompt,
                importFromClipboard: importDictionaryCSVFromClipboard,
                importFromFile: importDictionaryCSV
            )

            Divider()

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

                    if !dictionaryStore.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Search terms", text: $searchText)
                                .textFieldStyle(.roundedBorder)

                            Text(dictionaryCountText)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }

                    if dictionaryStore.entries.isEmpty {
                        ContentUnavailableView(
                            "No dictionary terms",
                            systemImage: "text.book.closed",
                            description: Text("Add terms or import a CSV file.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "No matching terms",
                            systemImage: "magnifyingglass",
                            description: Text("Try another search.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $selectedID) {
                            ForEach(filteredEntries) { entry in
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
                        .scrollIndicators(.automatic)
                    }
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
                .frame(minWidth: 340, idealWidth: 420)
            }
        }
        .onAppear {
            if selectedID == nil {
                selectedID = filteredEntries.first?.id
            }
            loadSelectedEntry()
        }
        .onChange(of: selectedID) { _, _ in
            if selectedID != nil {
                isCreatingNewEntry = false
            }
            loadSelectedEntry()
        }
        .onChange(of: dictionaryStore.entries) { _, entries in
            guard !isCreatingNewEntry else { return }
            guard !entries.contains(where: { $0.id == selectedID }) else {
                ensureSelectedEntryIsVisible()
                return
            }
            selectedID = filteredEntries.first?.id
            loadSelectedEntry()
        }
        .onChange(of: searchText) { _, _ in
            ensureSelectedEntryIsVisible()
        }
        .alert("Delete dictionary term?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(draft.canonical.isEmpty ? "this term" : draft.canonical) from the local dictionary.")
        }
        .sheet(item: $pendingImportPreview) { pending in
            DictionaryImportPreviewSheet(
                preview: pending.preview,
                confirmAction: {
                    confirmImportPreview(pending.preview)
                },
                cancelAction: {
                    cancelImportPreview()
                }
            )
        }
        .onExitCommand {
            cancelImportState()
        }
    }

    private func loadSelectedEntry() {
        guard let selectedEntry else {
            draft = TermEntryDraft()
            return
        }
        draft = TermEntryDraft(entry: selectedEntry)
    }

    private var dictionaryCountText: String {
        if searchText.trimmed.isEmpty {
            return "\(dictionaryStore.entries.count) terms"
        }

        return "\(filteredEntries.count) of \(dictionaryStore.entries.count) terms"
    }

    private func ensureSelectedEntryIsVisible() {
        guard !isCreatingNewEntry else { return }
        guard !filteredEntries.contains(where: { $0.id == selectedID }) else { return }
        selectedID = filteredEntries.first?.id
        loadSelectedEntry()
    }

    private func createNewEntry() {
        isCreatingNewEntry = true
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
            isCreatingNewEntry = false
            selectedID = entry.id
            message = "Saved"
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteDraft() {
        do {
            try dictionaryStore.deleteEntry(id: draft.id)
            isCreatingNewEntry = false
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
            pendingImportPreview = PendingDictionaryImportPreview(
                preview: try controller.prepareDictionaryImportPreview(
                    fileURL: url,
                    historyLimit: historyReviewLimit
                )
            )
        } catch {
            message = error.localizedDescription
        }
    }

    private func importDictionaryCSVFromClipboard() {
        pendingImportPreview = nil
        do {
            pendingImportPreview = PendingDictionaryImportPreview(
                preview: try controller.prepareDictionaryImportPreviewFromClipboard(
                    historyLimit: historyReviewLimit
                )
            )
        } catch {
            pendingImportPreview = nil
            message = error.localizedDescription
        }
    }

    private func copyReviewPrompt() {
        controller.copyDictionaryReviewPrompt(
            preset: reviewPreset,
            historyLimit: historyReviewLimit
        )
        message = "Review prompt copied"
    }

    private func confirmImportPreview(_ preview: DictionaryImportPreview) {
        do {
            try controller.confirmDictionaryImportPreview(preview)
            selectedID = preview.postImportEntries.first?.id ?? dictionaryStore.entries.first?.id
            pendingImportPreview = nil
            message = "Imported \(preview.importedEntryCount) terms"
        } catch {
            message = error.localizedDescription
        }
    }

    private func cancelImportPreview() {
        pendingImportPreview = nil
        message = "Import canceled"
    }

    private func cancelImportState() {
        if pendingImportPreview != nil {
            cancelImportPreview()
        } else {
            message = nil
        }
    }
}

private struct DictionaryReviewPanel: View {
    @Binding var reviewPreset: DictionaryReviewPromptPreset
    @Binding var historyReviewLimit: HistoryReviewLimit
    let message: String?
    let copyReviewPrompt: () -> Void
    let importFromClipboard: () -> Void
    let importFromFile: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Review with GPT", systemImage: "sparkles")
                        .font(.headline)

                    Text("Use recent history and the current dictionary to ask for better CSV entries.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preset")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("Prompt preset", selection: $reviewPreset) {
                        ForEach(DictionaryReviewPromptPreset.allCases) { preset in
                            Text(preset.title)
                                .tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .frame(minWidth: 170, idealWidth: 190, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("History entries")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Picker("History entries", selection: $historyReviewLimit) {
                        ForEach(HistoryReviewLimit.allCases) { limit in
                            Text("\(limit.rawValue)")
                                .tag(limit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                .frame(width: 170, alignment: .leading)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                CopyButton(
                    title: "Copy Review Prompt",
                    presentation: .prominentLabel
                ) {
                    copyReviewPrompt()
                }

                Button {
                    importFromClipboard()
                } label: {
                    Label("Clipboard", systemImage: "clipboard")
                }

                Button {
                    importFromFile()
                } label: {
                    Label("File", systemImage: "square.and.arrow.down")
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("The prompt is copied locally and may include recent transcription history. VoicePen does not send it anywhere.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text("CSV format: canonical, variants. Separate variants with semicolons, or put each variant in its own column.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Text(message ?? " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(height: 18, alignment: .leading)
                .opacity(message == nil ? 0 : 1)
        }
        .padding(18)
    }
}

private struct PendingDictionaryImportPreview: Identifiable {
    let id = UUID()
    let preview: DictionaryImportPreview
}

private struct DictionaryImportPreviewSheet: View {
    let preview: DictionaryImportPreview
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Dictionary Import")
                        .font(.title3.weight(.semibold))

                    Text(summaryText)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    cancelAction()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close without importing")
            }

            ImportedTermsPreview(entries: preview.importedEntries)

            if preview.examples.isEmpty {
                ContentUnavailableView(
                    "No recent sessions would change",
                    systemImage: "checkmark.circle",
                    description: Text("These terms are valid. Importing will update the dictionary, but the reviewed history does not show any text changes.")
                )
                .frame(minHeight: 180)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(preview.examples, id: \.historyEntryID) { example in
                            DictionaryImportPreviewExampleView(example: example)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 260)
                .scrollIndicators(.automatic)
            }

            HStack {
                Button {
                    cancelAction()
                } label: {
                    Label("Back to Dictionary", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    confirmAction()
                } label: {
                    Label(importButtonTitle, systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 420)
        .onExitCommand {
            cancelAction()
        }
    }

    private var summaryText: String {
        "\(preview.importedEntryCount) terms ready. \(preview.affectedEntryCount) reviewed sessions would change."
    }

    private var importButtonTitle: String {
        preview.importedEntryCount == 1 ? "Import 1 Term" : "Import \(preview.importedEntryCount) Terms"
    }
}

private struct ImportedTermsPreview: View {
    let entries: [TermEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terms to import")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(entries.prefix(5)) { entry in
                    GridRow {
                        Text(entry.canonical)
                            .font(.system(size: 12, weight: .semibold))
                        Text(entry.variants.joined(separator: "; "))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if entries.count > 5 {
                Text("+ \(entries.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DictionaryImportPreviewExampleView: View {
    let example: DictionaryImportPreviewExample

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(example.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)

            diffText
                .font(.system(.body, design: .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureGroup("Raw transcript") {
                Text(example.rawText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
        }
    }

    private var diffText: Text {
        example.diff.enumerated().reduce(Text("")) { partial, element in
            let suffix = element.offset == example.diff.count - 1 ? "" : " "
            let token = element.element
            let text = Text(token.text + suffix)

            switch token.change {
            case .unchanged:
                return partial + text.foregroundStyle(.primary)
            case .removed:
                return partial + text.foregroundStyle(.red).strikethrough()
            case .inserted:
                return partial + text.foregroundStyle(.green)
            }
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

private struct MeetingRecordingPanel: View {
    @ObservedObject var controller: AppController

    var body: some View {
        if showsPanel {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    if controller.appState == .meetingRecording {
                        RecordingPulseDot()
                    }

                    Label(formatDuration(controller.meetingElapsedTime), systemImage: "record.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }

                if controller.appState == .meetingRecording {
                    Label(meetingLimitText, systemImage: "timer")
                }

                if controller.appState == .meetingProcessing {
                    if let progress = controller.meetingProcessingProgress,
                        progress.totalChunks > 1
                    {
                        ProgressView(value: progress.fraction, total: 1.0)
                            .controlSize(.small)
                            .frame(width: 72)
                        Label("Processing \(progress.percent)%", systemImage: "waveform")
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Label("Processing Transcript", systemImage: "waveform")
                    }
                } else {
                    Label(controller.meetingSourceStatus.microphone.title, systemImage: "mic")
                    Label(controller.meetingSourceStatus.systemAudio.title, systemImage: "waveform")
                }

                Spacer()
            }
            .font(.system(size: 12))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private var showsPanel: Bool {
        controller.appState.showsMeetingRecordingPanel
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var meetingLimitText: String {
        let minutes = Int((VoicePenConfig.meetingMaximumRecordingDuration / 60).rounded())
        return "Limit \(minutes) min"
    }
}

private struct RecordingPulseDot: View {
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 8, height: 8)
            .opacity(isDimmed ? 0.35 : 1)
            .scaleEffect(isDimmed ? 0.75 : 1.1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDimmed)
            .onAppear {
                isDimmed = true
            }
            .accessibilityHidden(true)
    }
}

private struct RecordingPulseIcon: View {
    let systemName: String
    @State private var isDimmed = false

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(.red)
            .opacity(isDimmed ? 0.45 : 1)
            .scaleEffect(isDimmed ? 0.92 : 1.08)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isDimmed)
            .onAppear {
                isDimmed = true
            }
    }
}

private struct MeetingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var meetingHistoryStore: MeetingHistoryStore
    @State private var selectedID: MeetingHistoryEntry.ID?
    @State private var entryPendingDeletion: MeetingHistoryEntry?
    @State private var listRenderVersion = 0
    @State private var focusedEntry: MeetingHistoryEntry?

    private var selectedSummaryEntry: MeetingHistoryEntry? {
        guard let selectedID else {
            return meetingHistoryStore.entries.first
        }
        return meetingHistoryStore.entries.first { $0.id == selectedID } ?? meetingHistoryStore.entries.first
    }

    private var selectedEntry: MeetingHistoryEntry? {
        guard let selectedSummaryEntry else { return nil }
        return focusedEntry?.id == selectedSummaryEntry.id ? focusedEntry : selectedSummaryEntry
    }

    private var entryIDs: [MeetingHistoryEntry.ID] {
        meetingHistoryStore.entries.map(\.id)
    }

    private var dayGroups: [HistoryDayGroup<MeetingHistoryEntry>] {
        HistoryDayGroups(
            entries: meetingHistoryStore.entries,
            now: Date(),
            date: \.createdAt
        ).groups
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Meetings")
                        .font(.headline)

                    Spacer()

                    meetingRecordingControls
                }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

                if meetingHistoryStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No meetings yet",
                        systemImage: "person.2.wave.2",
                        description: Text("Finished meeting transcripts will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(dayGroups, id: \.day) { group in
                                Section {
                                    ForEach(group.entries) { entry in
                                        MeetingRowView(
                                            entry: entry,
                                            retryAction: { controller.retryMeetingProcessing(entry) },
                                            copyAction: { controller.copyMeetingTranscript(entry) },
                                            deleteAction: { entryPendingDeletion = entry }
                                        )
                                        .historyListRowStyle(isSelected: selectedID == entry.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedID = entry.id
                                        }
                                    }
                                } header: {
                                    HistoryDaySectionHeader(title: group.title)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .id(listRenderVersion)
                    .scrollIndicators(.automatic)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)

            Divider()

            MeetingDetailView(controller: controller, entry: selectedEntry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            selectedID = selectedID ?? meetingHistoryStore.entries.first?.id
        }
        .onChange(of: meetingHistoryStore.entries) { _, _ in
            if !meetingHistoryStore.entries.contains(where: { $0.id == selectedID }) {
                selectedID = meetingHistoryStore.entries.first?.id
            }
            focusedEntry = nil
        }
        .onChange(of: entryIDs) { _, _ in
            listRenderVersion += 1
        }
        .task(id: selectedSummaryEntry?.id) {
            await Task.yield()
            loadFocusedEntry()
        }
        .alert("Delete meeting?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let entryPendingDeletion {
                    controller.deleteMeetingEntry(id: entryPendingDeletion.id)
                }
                entryPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                entryPendingDeletion = nil
            }
        } message: {
            Text("This removes only the selected meeting transcript.")
        }
    }

    private var canStartMeeting: Bool {
        controller.appState.canStartMeetingRecording
    }

    @ViewBuilder
    private var meetingRecordingControls: some View {
        if controller.appState.isMeetingCaptureActive {
            Button(role: .destructive) {
                controller.cancelMeetingRecording()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Cancel Meeting Recording")
            .accessibilityLabel("Cancel Meeting Recording")

            Button {
                controller.stopMeetingRecording()
            } label: {
                HStack(spacing: 5) {
                    RecordingPulseIcon(systemName: "stop.fill")
                    Text("Stop")
                }
            }
            .accessibilityLabel("Stop")
        } else {
            Button {
                controller.startMeetingRecording()
            } label: {
                Label("Start", systemImage: "record.circle")
            }
            .disabled(!canStartMeeting)
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

    private func loadFocusedEntry() {
        guard let selectedSummaryEntry else {
            focusedEntry = nil
            return
        }

        do {
            focusedEntry = try meetingHistoryStore.loadEntry(id: selectedSummaryEntry.id) ?? selectedSummaryEntry
        } catch {
            focusedEntry = selectedSummaryEntry
        }
    }
}

private struct HistoryDaySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.background)
    }
}

private struct HistoryListRowStyle: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            }
            .padding(.horizontal, 6)
    }
}

private extension View {
    func historyListRowStyle(isSelected: Bool) -> some View {
        modifier(HistoryListRowStyle(isSelected: isSelected))
    }
}

private struct MeetingRowView: View {
    let entry: MeetingHistoryEntry
    let retryAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(statusTitle, systemImage: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)

                Spacer()

                Text(entry.createdAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(entry.previewText)
                .font(.system(size: 13))
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(entry.createdAt, style: .date)
                Text(MeetingDurationFormatter.historyText(entry.duration))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .contextMenu {
            if entry.recoveryAudio != nil {
                Button {
                    retryAction()
                } label: {
                    Label("Retry Processing", systemImage: "arrow.clockwise")
                }
                .disabled(!isRecoveryAudioAvailable)
            }

            Button {
                copyAction()
            } label: {
                Label("Copy Transcript", systemImage: "doc.on.doc")
            }
            .disabled(entry.transcriptText.trimmed.isEmpty)

            Button(role: .destructive) {
                deleteAction()
            } label: {
                Label("Delete Meeting", systemImage: "trash")
            }
        }
    }

    private var statusTitle: String {
        entry.status.title
    }

    private var statusIcon: String {
        switch entry.status {
        case .completed:
            return "checkmark.circle"
        case .partial:
            return "exclamationmark.triangle"
        case .failed:
            return "xmark.octagon"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed:
            return .green
        case .partial:
            return .yellow
        case .failed:
            return .red
        }
    }

    private var isRecoveryAudioAvailable: Bool {
        guard let recoveryAudio = entry.recoveryAudio else {
            return false
        }
        return recoveryAudio.isAvailableForRetry()
    }
}

private struct MeetingDetailView: View {
    @ObservedObject var controller: AppController
    let entry: MeetingHistoryEntry?

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

                        if entry.recoveryAudio != nil {
                            Button {
                                controller.retryMeetingProcessing(entry)
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .disabled(!isRecoveryAudioAvailable(entry))
                            .help("Retry Processing")
                            .accessibilityLabel("Retry Processing")
                        }

                    }

                    if let recoveryAudio = entry.recoveryAudio {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recoveryAudioStatusTitle(for: recoveryAudio))
                                .font(.subheadline.weight(.semibold))
                            Text(recoveryAudioStatusMessage(for: recoveryAudio))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    if let errorMessage = entry.errorMessage {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Processing error")
                                .font(.subheadline.weight(.semibold))
                            Text(errorMessage)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    HistoryTextSection(
                        title: "Full transcript",
                        text: entry.transcriptText,
                        isResizable: true,
                        copyAction: {
                            controller.copyMeetingTranscript(entry)
                        }
                    )

                    MeetingMetadataSection(controller: controller, entry: entry)

                    Spacer(minLength: 0)
                }
                .padding(20)
            } else {
                ContentUnavailableView(
                    "Select a meeting",
                    systemImage: "text.bubble",
                    description: Text("Saved meeting transcripts will appear here.")
                )
            }
        }
    }

    private func detailSubtitle(for entry: MeetingHistoryEntry) -> String {
        "\(entry.status.title) · \(MeetingDurationFormatter.historyText(entry.duration))"
    }

    private func isRecoveryAudioAvailable(_ entry: MeetingHistoryEntry) -> Bool {
        guard let recoveryAudio = entry.recoveryAudio else {
            return false
        }
        return recoveryAudio.isAvailableForRetry()
    }

    private func recoveryAudioStatusTitle(for recoveryAudio: MeetingRecoveryAudioManifest) -> String {
        !recoveryAudio.isAvailableForRetry()
            ? "Audio unavailable"
            : "Audio saved locally for retry"
    }

    private func recoveryAudioStatusMessage(for recoveryAudio: MeetingRecoveryAudioManifest) -> String {
        if recoveryAudio.isExpired(at: Date()) {
            return "The 7-day retry window has expired."
        }

        if !recoveryAudio.hasAvailableAudio() {
            return "The saved audio files are missing."
        }

        return "Retry is available until \(recoveryAudio.expiresAt.formatted(date: .abbreviated, time: .shortened))."
    }
}

private enum MeetingDurationFormatter {
    static func historyText(_ duration: TimeInterval) -> String {
        let seconds = max(0, duration)
        if seconds < 60 {
            return "\(displayedSeconds(seconds)) sec"
        }
        return String(format: "%.1f min", seconds / 60)
    }

    private static func displayedSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds > 0 else {
            return 0
        }
        return max(1, Int(seconds.rounded()))
    }
}

private struct MeetingMetadataSection: View {
    @ObservedObject var controller: AppController
    let entry: MeetingHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Processing")
                .font(.subheadline.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(metadataRows, id: \.label) { row in
                    metadataRow(row.label, row.value)
                }
            }
            .font(.system(size: 12))
        }
    }

    private var metadataRows: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Microphone", entry.sourceFlags.microphoneCaptured ? "Captured" : "Not captured"),
            ("System audio", entry.sourceFlags.systemAudioCaptured ? "Captured" : "Not captured"),
            ("Incomplete", entry.sourceFlags.partial ? "Yes" : "No"),
            ("Decoded by", decodedByText)
        ]

        if let appVersionText {
            rows.append(("App version", appVersionText))
        }
        if let timecodesStatusText {
            rows.append(("Timecodes", timecodesStatusText))
        }
        rows.append(("Processing time", processingTimeText))
        return rows
    }

    private var decodedByText: String {
        entry.modelMetadata?.displayName ?? "Unknown"
    }

    private var appVersionText: String? {
        guard let rawAppVersion = entry.modelMetadata?.appVersion else {
            return nil
        }
        let appVersion = rawAppVersion.trimmed
        return !appVersion.isEmpty && appVersion != "Unknown" ? appVersion : nil
    }

    private var timecodesStatusText: String? {
        if transcriptContainsTimecode {
            return nil
        }
        return "Not present"
    }

    private var transcriptContainsTimecode: Bool {
        entry.transcriptText
            .split(separator: "\n")
            .contains { line in
                line.hasPrefix("[") && line.contains(" - ") && line.contains("]")
            }
    }

    private var processingTimeText: String {
        let total = [
            entry.timings?.preprocessing,
            entry.timings?.transcription
        ]
        .compactMap { $0 }
        .reduce(0, +)

        guard total > 0 else {
            return "Unknown"
        }

        if total < 1 {
            return "\(Int((total * 1_000).rounded())) ms"
        }

        return String(format: "%.2f s", total)
    }

    private func formattedDuration(_ duration: TimeInterval?) -> String? {
        guard let duration, duration > 0 else {
            return nil
        }

        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }

        return String(format: "%.2f s", duration)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    @State private var selectedID: VoiceHistoryEntry.ID?
    @State private var showingClearConfirmation = false
    @State private var entryPendingDeletion: VoiceHistoryEntry?
    @State private var searchText = ""
    @State private var copiedEntryID: VoiceHistoryEntry.ID?
    @State private var copyFeedbackResetTask: Task<Void, Never>?

    private let copyFeedbackDuration = VoicePenConfig.historyCopyFeedbackDuration

    private var selectedEntry: VoiceHistoryEntry? {
        guard let selectedID else {
            return filteredEntries.first
        }
        return filteredEntries.first { $0.id == selectedID } ?? filteredEntries.first
    }

    private var filteredEntries: [VoiceHistoryEntry] {
        VoiceHistoryFilter(query: searchText)
            .filteredEntries(from: historyStore.entries)
    }

    private var dayGroups: [HistoryDayGroup<VoiceHistoryEntry>] {
        HistoryDayGroups(
            entries: filteredEntries,
            now: Date(),
            date: \.createdAt
        ).groups
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Sessions")
                        .font(.headline)

                    Spacer()

                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(historyStore.entries.isEmpty)
                }
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

                if !historyStore.entries.isEmpty {
                    VStack(spacing: 8) {
                        TextField("Search history", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                if historyStore.entries.isEmpty {
                    ContentUnavailableView(
                        "No voice sessions yet",
                        systemImage: "mic",
                        description: Text("Finished dictations will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No matching sessions",
                        systemImage: "magnifyingglass",
                        description: Text("Try another search.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(dayGroups, id: \.day) { group in
                                Section {
                                    historyRows(group.entries)
                                } header: {
                                    HistoryDaySectionHeader(title: group.title)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.automatic)
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
            selectedID = selectedID ?? filteredEntries.first?.id
        }
        .onChange(of: historyStore.entries) { _, _ in
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: searchText) { _, _ in
            ensureSelectedEntryIsVisible()
        }
        .onDisappear {
            copyFeedbackResetTask?.cancel()
        }
        .alert("Are you sure?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) {
                controller.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved transcription history from VoicePen.")
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

    @ViewBuilder
    private func historyRows(_ entries: [VoiceHistoryEntry]) -> some View {
        ForEach(entries) { entry in
            HistoryRowView(
                entry: entry,
                isCopyConfirmed: copiedEntryID == entry.id,
                selectAction: {
                    selectedID = entry.id
                },
                copyAction: {
                    copyHistoryEntry(entry)
                },
                deleteAction: {
                    entryPendingDeletion = entry
                }
            )
            .historyListRowStyle(isSelected: selectedID == entry.id)
        }
    }

    private func copyHistoryEntry(_ entry: VoiceHistoryEntry) {
        guard !entry.bestText.trimmed.isEmpty else { return }
        controller.copyToClipboard(entry.bestText)
        copiedEntryID = entry.id

        copyFeedbackResetTask?.cancel()
        copyFeedbackResetTask = Task {
            try? await Task.sleep(for: copyFeedbackDuration)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if copiedEntryID == entry.id {
                    copiedEntryID = nil
                }
            }
        }
    }

    private func ensureSelectedEntryIsVisible() {
        guard !filteredEntries.contains(where: { $0.id == selectedID }) else { return }
        selectedID = filteredEntries.first?.id
    }
}

private struct HistoryRowView: View {
    let entry: VoiceHistoryEntry
    let isCopyConfirmed: Bool
    let selectAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusIndicator

                Spacer()

                Text(entry.createdAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Button(action: copyAction) {
                    Image(systemName: isCopyConfirmed ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isCopyConfirmed ? .green : .secondary)
                .opacity((isHovered || isCopyConfirmed) && hasCopyableText ? 1 : 0)
                .disabled(!hasCopyableText)
                .allowsHitTesting(isHovered || isCopyConfirmed)
                .help(isCopyConfirmed ? "Copied" : "Copy text")
                .animation(.snappy(duration: 0.15), value: isCopyConfirmed)

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
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
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    selectAction()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard hasCopyableText else { return }
                    copyAction()
                }
        )
        .contextMenu {
            if hasCopyableText {
                Button {
                    copyAction()
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }

            Button(role: .destructive) {
                deleteAction()
            } label: {
                Label("Delete Session", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("Copy Text")) {
            guard hasCopyableText else { return }
            copyAction()
        }
        .accessibilityAction(named: Text("Delete Session")) {
            deleteAction()
        }
        .onHover { isHovered = $0 }
    }

    private var hasCopyableText: Bool {
        !entry.bestText.trimmed.isEmpty
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

    @ViewBuilder
    private var statusIndicator: some View {
        switch entry.status {
        case .insertAttempted:
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .help(entry.status.title)
        case .empty, .failed:
            Label(statusReason, systemImage: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
    }

    private var statusReason: String {
        guard entry.status == .failed else {
            return entry.status.title
        }

        let errorMessage = entry.errorMessage?.trimmed ?? ""
        return errorMessage.isEmpty ? entry.status.title : errorMessage
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.1fs", duration)
    }
}

private struct HistoryDetailView: View {
    @ObservedObject var controller: AppController
    let entry: VoiceHistoryEntry?
    @State private var expandedRawTranscriptEntryIDs: Set<VoiceHistoryEntry.ID> = []

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
                            controller.insertText(entry.bestText)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(entry.bestText.trimmed.isEmpty)
                        .help("Insert Again")
                        .accessibilityLabel("Insert Again")
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

                    if !entry.diagnosticNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Diagnostics")
                                .font(.subheadline.weight(.semibold))
                            Text(entry.diagnosticNotes.joined(separator: "\n"))
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

                    HistoryRawTranscriptDisclosure(
                        isExpanded: rawTranscriptExpansionBinding(for: entry.id),
                        text: entry.rawText,
                        copyAction: {
                            controller.copyToClipboard(entry.rawText)
                        }
                    )

                    HistoryProcessingMetadataSection(entry: entry)

                    HistoryTimingsSection(timings: entry.timings)

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

    private func rawTranscriptExpansionBinding(for entryID: VoiceHistoryEntry.ID) -> Binding<Bool> {
        Binding(
            get: {
                expandedRawTranscriptEntryIDs.contains(entryID)
            },
            set: { isExpanded in
                var expandedEntryIDs = expandedRawTranscriptEntryIDs
                if isExpanded {
                    expandedEntryIDs.insert(entryID)
                } else {
                    expandedEntryIDs.remove(entryID)
                }
                expandedRawTranscriptEntryIDs = expandedEntryIDs
            }
        )
    }
}

private struct HistoryProcessingMetadataSection: View {
    let entry: VoiceHistoryEntry

    var body: some View {
        if entry.modelMetadata != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Processing")
                    .font(.subheadline.weight(.semibold))

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(metadataRows, id: \.label) { row in
                        metadataRow(row.label, row.value)
                    }
                }
                .font(.system(size: 12))
            }
        }
    }

    private var metadataRows: [(label: String, value: String)] {
        var rows = [("Decoded by", entry.modelMetadata?.displayName ?? "Unknown")]
        if let appVersionText {
            rows.append(("App version", appVersionText))
        }
        return rows
    }

    private var appVersionText: String? {
        guard let rawAppVersion = entry.modelMetadata?.appVersion else {
            return nil
        }
        let appVersion = rawAppVersion.trimmed
        return !appVersion.isEmpty && appVersion != "Unknown" ? appVersion : nil
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct HistoryTimingsSection: View {
    let timings: VoicePipelineTimings?

    var body: some View {
        if timings != nil, !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Timings")
                    .font(.subheadline.weight(.semibold))

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(rows, id: \.name) { row in
                        GridRow {
                            Text(row.name)
                                .foregroundStyle(.secondary)
                            Text(format(row.duration))
                                .monospacedDigit()
                        }
                    }
                }
                .font(.system(size: 12))
            }
        }
    }

    private var rows: [(name: String, duration: TimeInterval)] {
        [
            ("Recording", timings?.recording),
            ("Preprocessing", timings?.preprocessing),
            ("Transcription", timings?.transcription),
            ("Normalization", timings?.normalization),
            ("Insertion", timings?.insertion)
        ]
        .compactMap { row in
            guard let duration = row.1 else { return nil }
            return (row.0, duration)
        }
    }

    private func format(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }

        return String(format: "%.2f s", duration)
    }
}

private struct HistoryTextSection: View {
    private static let defaultTextHeight: CGFloat = 160
    private static let minimumTextHeight: CGFloat = 96
    private static let maximumTextHeight: CGFloat = 520

    let title: String
    let text: String
    var isResizable = false
    let copyAction: () -> Void
    @State private var textHeight = Self.defaultTextHeight
    @State private var resizeStartHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                CopyButton(isDisabled: trimmedText.isEmpty, action: copyAction)
            }

            textBox
                .frame(
                    minHeight: Self.minimumTextHeight,
                    maxHeight: isResizable ? nil : Self.defaultTextHeight
                )
                .frame(height: isResizable ? textHeight : nil)
        }
    }

    private var textBox: some View {
        ScrollView {
            Text(displayText)
                .font(.system(.body, design: .default))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .padding(.bottom, isResizable ? 12 : 0)
        }
        .scrollIndicators(.automatic)
        .background(.background)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if isResizable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(-45))
                    .padding(8)
                    .contentShape(Rectangle())
                    .help("Resize")
                    .accessibilityLabel("Resize transcript area")
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if resizeStartHeight == nil {
                                    resizeStartHeight = textHeight
                                }

                                let startHeight = resizeStartHeight ?? textHeight
                                textHeight = clampedTextHeight(startHeight + value.translation.height)
                            }
                            .onEnded { _ in
                                resizeStartHeight = nil
                            }
                    )
            }
        }
    }

    private func clampedTextHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, Self.minimumTextHeight), Self.maximumTextHeight)
    }

    private var displayText: String {
        trimmedText.isEmpty ? "No text" : text
    }

    private var trimmedText: String {
        text.trimmed
    }

}

private struct HistoryRawTranscriptDisclosure: View {
    let isExpanded: Binding<Bool>
    let text: String
    let copyAction: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()

                    CopyButton(isDisabled: trimmedText.isEmpty, action: copyAction)
                }

                ScrollView {
                    Text(displayText)
                        .font(.system(.body, design: .default))
                        .foregroundStyle(trimmedText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(minHeight: 96, maxHeight: 160)
                .scrollIndicators(.automatic)
                .background(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.secondary.opacity(0.22), lineWidth: 1)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Raw transcript")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    private var displayText: String {
        trimmedText.isEmpty ? "No text" : text
    }

    private var trimmedText: String {
        text.trimmed
    }

}
