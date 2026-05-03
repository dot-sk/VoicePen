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
        case .about:
            AboutView()
        }
    }
}

private struct DictionaryEditorView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var dictionaryStore: DictionaryStore
    @State private var selectedID: String?
    @State private var draft = TermEntryDraft()
    @State private var message: String?
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var reviewPreset = DictionaryReviewPromptPreset.dictionaryImprovement
    @State private var historyReviewLimit = HistoryReviewLimit.defaultValue
    @State private var pendingImportPreview: PendingDictionaryImportPreview?

    private var selectedEntry: TermEntry? {
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
            loadSelectedEntry()
        }
        .onChange(of: dictionaryStore.entries) { _, entries in
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
                    pendingImportPreview = nil
                    message = "Import canceled"
                }
            )
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
        guard !filteredEntries.contains(where: { $0.id == selectedID }) else { return }
        selectedID = filteredEntries.first?.id
        loadSelectedEntry()
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
        do {
            pendingImportPreview = PendingDictionaryImportPreview(
                preview: try controller.prepareDictionaryImportPreviewFromClipboard(
                    historyLimit: historyReviewLimit
                )
            )
        } catch {
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
                Button {
                    copyReviewPrompt()
                } label: {
                    Label("Copy Review Prompt", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

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

            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

private struct HistoryView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    @State private var selectedID: VoiceHistoryEntry.ID?
    @State private var showingClearConfirmation = false
    @State private var entryPendingDeletion: VoiceHistoryEntry?
    @State private var searchText = ""
    @State private var statusFilter = HistoryStatusFilter.all
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
        VoiceHistoryFilter(
            query: searchText,
            status: statusFilter.status
        )
        .filteredEntries(from: historyStore.entries)
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

                if !historyStore.entries.isEmpty {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Label(historyStore.storageStats.formattedTextPayloadSize, systemImage: "internaldrive")
                                .foregroundStyle(.secondary)

                            Text("history text")
                                .foregroundStyle(.secondary)

                            Spacer()
                        }
                        .font(.caption)

                        TextField("Search history", text: $searchText)
                            .textFieldStyle(.roundedBorder)

                        Picker("Status", selection: $statusFilter) {
                            ForEach(HistoryStatusFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
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
                        description: Text("Try another search or status filter.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedID) {
                        ForEach(filteredEntries) { entry in
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
            selectedID = selectedID ?? filteredEntries.first?.id
        }
        .onChange(of: historyStore.entries) { _, _ in
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: searchText) { _, _ in
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: statusFilter) { _, _ in
            ensureSelectedEntryIsVisible()
        }
        .onDisappear {
            copyFeedbackResetTask?.cancel()
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
        let entries = filteredEntries
        for index in offsets {
            guard entries.indices.contains(index) else { continue }
            controller.deleteHistoryEntry(id: entries[index].id)
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

private enum HistoryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case insertAttempted
    case empty
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .insertAttempted:
            return VoiceHistoryStatus.insertAttempted.title
        case .empty:
            return VoiceHistoryStatus.empty.title
        case .failed:
            return VoiceHistoryStatus.failed.title
        }
    }

    var status: VoiceHistoryStatus? {
        switch self {
        case .all:
            return nil
        case .insertAttempted:
            return .insertAttempted
        case .empty:
            return .empty
        case .failed:
            return .failed
        }
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
                .opacity((isHovered || isCopyConfirmed) && !entry.bestText.trimmed.isEmpty ? 1 : 0)
                .disabled((!isHovered && !isCopyConfirmed) || entry.bestText.trimmed.isEmpty)
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
        .simultaneousGesture(
            TapGesture()
                .onEnded { _ in
                    selectAction()
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    guard !entry.bestText.trimmed.isEmpty else { return }
                    copyAction()
                }
        )
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
                            Label("Insert Again", systemImage: "arrowshape.turn.up.forward")
                        }
                        .disabled(entry.bestText.trimmed.isEmpty)

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

                    HistoryRawTranscriptDisclosure(
                        text: entry.rawText,
                        copyAction: {
                            controller.copyToClipboard(entry.rawText)
                        }
                    )

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

private struct HistoryRawTranscriptDisclosure: View {
    let text: String
    let copyAction: () -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
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
                        .foregroundStyle(trimmedText.isEmpty ? .secondary : .primary)
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
            .padding(.top, 8)
        } label: {
            Text("Raw transcript")
                .font(.subheadline.weight(.semibold))
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
