import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VoicePenMainWindow: View {
    @ObservedObject var controller: AppController
    @State private var selectedSection: VoicePenSettingsSection? = .general

    private let primaryActivityBarSections: [VoicePenSettingsSection] = [
        .general,
        .meetings,
        .history
    ]

    private var settingsActivityBarSections: [VoicePenSettingsSection] {
        var sections: [VoicePenSettingsSection] = [
            .dictionary,
            .model,
            .config
        ]
        if VoicePenConfig.modesFeatureEnabled {
            sections.append(.modes)
        }
        if VoicePenConfig.aiFeatureEnabled {
            sections.append(.ai)
        }
        sections.append(contentsOf: [
            .about
        ])
        return sections
    }

    var body: some View {
        HStack(spacing: 0) {
            VoicePenActivityBar(
                selectedSection: $selectedSection,
                primarySections: primaryActivityBarSections,
                settingsSections: settingsActivityBarSections,
                systemImage: systemImage(for:)
            )

            Divider()

            NavigationStack {
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
                    .navigationTitle("VoicePen")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MeetingRecordingPanel(controller: controller)
        }
        .background {
            ActivityBarNavigationShortcutMonitor(selectSection: { section in
                selectedSection = section
            })
            .frame(width: 0, height: 0)

            MeetingRecordingShortcutMonitor(toggleRecording: toggleMeetingRecording)
                .frame(width: 0, height: 0)
        }
        .frame(minWidth: 920, minHeight: 560)
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
                openSection: { section in
                    selectedSection = section
                }
            )
        case .model:
            ModelSettingsView(controller: controller, settingsStore: controller.settingsStore)
        case .modes:
            ModesSettingsView(controller: controller, settingsStore: controller.settingsStore)
        case .ai:
            AISettingsView(controller: controller)
        case .config:
            ConfigSettingsView(controller: controller, settingsStore: controller.settingsStore)
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
            AboutView(
                controller: controller,
                historyStore: controller.historyStore
            )
        }
    }

    @discardableResult
    private func toggleMeetingRecording() -> Bool {
        if controller.appState.isMeetingCaptureActive {
            controller.stopMeetingRecording()
            return true
        }

        guard controller.appState.canStartMeetingRecording else {
            return false
        }

        controller.startMeetingRecording()
        return true
    }
}

private struct ActivityBarNavigationShortcutMonitor: NSViewRepresentable {
    let selectSection: (VoicePenSettingsSection) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.selectSection = selectSection
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectSection: selectSection)
    }

    final class Coordinator {
        private static let sectionByKeyCode: [UInt16: VoicePenSettingsSection] = [
            18: .general,
            19: .meetings,
            20: .history,
            83: .general,
            84: .meetings,
            85: .history
        ]

        var selectSection: (VoicePenSettingsSection) -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(selectSection: @escaping (VoicePenSettingsSection) -> Void) {
            self.selectSection = selectSection
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            view = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                Self.isCommandOnlyShortcut(event),
                let section = Self.sectionByKeyCode[event.keyCode],
                let window = view?.window,
                window.isKeyWindow
            else {
                return event
            }

            if let eventWindow = event.window, eventWindow !== window {
                return event
            }

            selectSection(section)
            return nil
        }

        private static func isCommandOnlyShortcut(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let disallowedFlags: NSEvent.ModifierFlags = [.control, .option, .shift]
            return flags.contains(.command) && flags.intersection(disallowedFlags).isEmpty
        }
    }
}

private struct VoicePenActivityBar: View {
    @Binding var selectedSection: VoicePenSettingsSection?

    let primarySections: [VoicePenSettingsSection]
    let settingsSections: [VoicePenSettingsSection]
    let systemImage: (VoicePenSettingsSection) -> String

    var body: some View {
        VStack(spacing: 0) {
            activityButtons(primarySections)

            activityDivider

            activityButtons(settingsSections)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var activityDivider: some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    @ViewBuilder
    private func activityButtons(_ sections: [VoicePenSettingsSection]) -> some View {
        ForEach(sections) { section in
            VoicePenActivityBarButton(
                section: section,
                systemImage: systemImage(section),
                isSelected: selectedSection == section
            ) {
                selectedSection = section
            }
        }
    }
}

private struct VoicePenActivityBarButton: View {
    let section: VoicePenSettingsSection
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        if isHovered {
            return Color.primary.opacity(0.08)
        }
        return .clear
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 24)
                }

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
                    .frame(width: 36, height: 36)
                    .padding(.leading, 8)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .padding(6)
                    .frame(width: 52, height: 40)
            }
            .frame(width: 52, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityValue(isSelected ? "Selected" : "")
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
    var color: Color = .red
    @State private var isDimmed = false

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(color)
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
    @State private var focusedEntry: MeetingHistoryEntry?
    @State private var searchText = ""

    private var filteredEntries: [MeetingHistoryEntry] {
        MeetingHistoryFilter(query: searchText)
            .filteredEntries(from: searchableEntries)
    }

    private var searchableEntries: [MeetingHistoryEntry] {
        guard let focusedEntry else {
            return meetingHistoryStore.entries
        }
        return meetingHistoryStore.entries.map { entry in
            entry.id == focusedEntry.id ? focusedEntry : entry
        }
    }

    private var selectedSummaryEntry: MeetingHistoryEntry? {
        guard let selectedID else {
            return filteredEntries.first
        }
        return filteredEntries.first { $0.id == selectedID } ?? filteredEntries.first
    }

    var body: some View {
        TranscriptWorkspaceView(
            selectedID: $selectedID,
            searchText: $searchText,
            entries: filteredEntries,
            hasSourceEntries: !meetingHistoryStore.entries.isEmpty,
            entryDate: \.createdAt,
            searchPlaceholder: "Search meetings",
            emptyTitle: "No meetings yet",
            emptySystemImage: "person.2.wave.2",
            emptyDescription: "Finished meeting transcripts will appear here.",
            noMatchesTitle: "No meetings found",
            noMatchesSystemImage: "magnifyingglass",
            noMatchesDescription: "Try another search query."
        ) {
            meetingRecordingControls
        } rowContent: { entry in
            MeetingRowView(
                entry: entry,
                retryAction: { controller.retryMeetingProcessing(entry) },
                copyAction: { controller.copyMeetingTranscript(entry) },
                deleteAction: { entryPendingDeletion = entry }
            )
        } centerContent: { entry in
            MeetingTranscriptWorkspace(
                entry: focusedEntry(for: entry),
                copyAction: { controller.copyMeetingTranscript($0) }
            )
        } sidebarContent: { entry in
            MeetingMetadataSection(
                controller: controller,
                entry: focusedEntry(for: entry),
                deleteAction: { entryPendingDeletion = $0 }
            )
        }
        .onAppear {
            selectedID = selectedID ?? filteredEntries.first?.id
        }
        .onChange(of: meetingHistoryStore.entries) { _, _ in
            focusedEntry = nil
        }
        .onChange(of: searchText) { _, _ in
            if !filteredEntries.contains(where: { $0.id == focusedEntry?.id }) {
                focusedEntry = nil
            }
        }
        .onChange(of: selectedID) { _, newSelectedID in
            if focusedEntry?.id != newSelectedID {
                focusedEntry = nil
            }
        }
        .task(id: selectedID) {
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

    private var canUseMeetingRecordingPrimaryAction: Bool {
        controller.appState.isMeetingCaptureActive || canStartMeeting
    }

    @ViewBuilder
    private var meetingRecordingControls: some View {
        HStack(spacing: 8) {
            if controller.appState.isMeetingCaptureActive {
                Button(role: .destructive) {
                    controller.cancelMeetingRecording()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderless)
                .help("Cancel Meeting Recording")
                .accessibilityLabel("Cancel Meeting Recording")
                .pointingHandCursor()
            }

            Button {
                toggleMeetingRecording()
            } label: {
                HStack(spacing: 8) {
                    if controller.appState.isMeetingCaptureActive {
                        RecordingPulseIcon(systemName: "stop.fill", color: .white)
                        Text("Stop")
                    } else {
                        Image(systemName: "record.circle")
                        Text("Start new recording")
                    }
                }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(meetingRecordingPrimaryButtonColor)
            }
            .opacity(canUseMeetingRecordingPrimaryAction ? 1 : 0.7)
            .disabled(!canUseMeetingRecordingPrimaryAction)
            .help(meetingRecordingPrimaryActionLabel)
            .accessibilityLabel(meetingRecordingPrimaryActionLabel)
            .pointingHandCursor(isEnabled: canUseMeetingRecordingPrimaryAction)
        }
    }

    private var meetingRecordingPrimaryActionLabel: String {
        controller.appState.isMeetingCaptureActive ? "Stop Meeting Recording" : "Start Meeting Recording"
    }

    private var meetingRecordingPrimaryButtonColor: Color {
        if controller.appState.isMeetingCaptureActive {
            return .red
        }
        return canStartMeeting ? Color.accentColor : Color.accentColor.opacity(0.45)
    }

    @discardableResult
    private func toggleMeetingRecording() -> Bool {
        if controller.appState.isMeetingCaptureActive {
            controller.stopMeetingRecording()
            return true
        }

        guard canStartMeeting else {
            return false
        }

        controller.startMeetingRecording()
        return true
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

    private func focusedEntry(for entry: MeetingHistoryEntry?) -> MeetingHistoryEntry? {
        guard let entry else { return nil }
        return focusedEntry?.id == entry.id ? focusedEntry : entry
    }
}

private struct MeetingRecordingShortcutMonitor: NSViewRepresentable {
    let toggleRecording: () -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.toggleRecording = toggleRecording
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(toggleRecording: toggleRecording)
    }

    final class Coordinator {
        private static let recordingKeyCode: UInt16 = 15

        var toggleRecording: () -> Bool
        private weak var view: NSView?
        private var monitor: Any?

        init(toggleRecording: @escaping () -> Bool) {
            self.toggleRecording = toggleRecording
        }

        func attach(to view: NSView) {
            self.view = view
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            view = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                event.keyCode == Self.recordingKeyCode,
                !event.isARepeat,
                Self.isCommandOnlyShortcut(event),
                let window = view?.window,
                window.isKeyWindow
            else {
                return event
            }

            if let eventWindow = event.window, eventWindow !== window {
                return event
            }

            return toggleRecording() ? nil : event
        }

        private static func isCommandOnlyShortcut(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let disallowedFlags: NSEvent.ModifierFlags = [.control, .option, .shift]
            return flags.contains(.command) && flags.intersection(disallowedFlags).isEmpty
        }
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

                Text("\(entry.createdAt.formatted(date: .omitted, time: .shortened)) · \(MeetingDurationFormatter.historyText(entry.duration))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(entry.previewText)
                .font(.system(size: 13))
                .lineLimit(2)
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

private struct MeetingTranscriptWorkspace: View {
    let entry: MeetingHistoryEntry?
    let copyAction: (MeetingHistoryEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                transcriptWorkspace(for: entry)
            } else {
                ContentUnavailableView(
                    "Select a meeting",
                    systemImage: "text.bubble",
                    description: Text("Saved meeting transcripts will appear here.")
                )
            }
        }
    }

    private func transcriptWorkspace(for entry: MeetingHistoryEntry) -> some View {
        TranscriptTextWorkspace(
            title: entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()),
            subtitle: detailSubtitle(for: entry),
            text: displayText(for: entry),
            selectionResetID: entry.id,
            copyAction: {
                copyAction(entry)
            },
            isSecondaryText: entry.transcriptText.trimmed.isEmpty,
            isCopyDisabled: entry.transcriptText.trimmed.isEmpty
        )
    }

    private func detailSubtitle(for entry: MeetingHistoryEntry) -> String {
        "\(entry.status.title) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(MeetingDurationFormatter.historyText(entry.duration))"
    }

    private func displayText(for entry: MeetingHistoryEntry) -> String {
        let transcriptText = entry.transcriptText.trimmed
        if !transcriptText.isEmpty {
            return entry.transcriptText
        }
        if let errorMessage = entry.errorMessage, !errorMessage.trimmed.isEmpty {
            return errorMessage
        }
        return "No transcript"
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

private extension View {
    func pointingHandCursor(isEnabled: Bool = true) -> some View {
        modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                let shouldHover = hovering && isEnabled
                guard shouldHover != isHovering else {
                    return
                }
                isHovering = shouldHover
                if shouldHover {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .onDisappear {
                guard isHovering else {
                    return
                }
                NSCursor.pop()
                isHovering = false
            }
    }
}

private struct MeetingMetadataSection: View {
    @ObservedObject var controller: AppController
    let entry: MeetingHistoryEntry?
    let deleteAction: (MeetingHistoryEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                VStack(spacing: 0) {
                    ScrollView {
                        metadataContent(for: entry)
                            .padding(16)
                    }
                    .frame(maxHeight: .infinity)
                    .scrollIndicators(.automatic)

                    Divider()

                    deleteRecordingButton(for: entry)
                }
            } else {
                ContentUnavailableView(
                    "No meeting selected",
                    systemImage: "sidebar.right",
                    description: Text("Metadata appears after selecting a meeting.")
                )
            }
        }
    }

    private func metadataContent(for entry: MeetingHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if entry.recoveryAudio != nil {
                TranscriptSidebarSection("Actions") {
                    retryButton(for: entry)
                }
            }

            TranscriptSidebarSection("Status") {
                TranscriptMetadataValue(entry.status.title)
            }

            TranscriptSidebarSection("Recording") {
                TranscriptMetadataValue(entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
            }

            TranscriptSidebarSection("Duration") {
                TranscriptMetadataValue(MeetingDurationFormatter.historyText(entry.duration))
            }

            TranscriptSidebarSection("Audio sources") {
                TranscriptMetadataGrid(rows: audioSourceRows(for: entry))
            }

            TranscriptSidebarSection("Processing") {
                TranscriptMetadataGrid(rows: processingRows(for: entry))
            }

            TranscriptSidebarSection("Speakers detected") {
                TranscriptMetadataValue(speakerCountText(for: entry))
            }

            if let recoveryAudio = entry.recoveryAudio {
                TranscriptSidebarSection(recoveryAudioStatusTitle(for: recoveryAudio)) {
                    Text(recoveryAudioStatusMessage(for: recoveryAudio))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let errorMessage = entry.errorMessage, !errorMessage.trimmed.isEmpty {
                TranscriptSidebarSection("Processing error") {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func retryButton(for entry: MeetingHistoryEntry) -> some View {
        Button {
            controller.retryMeetingProcessing(entry)
        } label: {
            Label("Retry Processing", systemImage: "arrow.clockwise")
        }
        .disabled(!isRecoveryAudioAvailable(entry))
        .help("Retry Processing")
        .accessibilityLabel("Retry Processing")
    }

    private func deleteRecordingButton(for entry: MeetingHistoryEntry) -> some View {
        Button(role: .destructive) {
            deleteAction(entry)
        } label: {
            Label("Delete recording", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .help("Delete recording")
        .accessibilityLabel("Delete recording")
        .pointingHandCursor()
    }

    private func audioSourceRows(for entry: MeetingHistoryEntry) -> [(label: String, value: String)] {
        [
            ("Microphone", entry.sourceFlags.microphoneCaptured ? "Captured" : "Not captured"),
            ("System audio", entry.sourceFlags.systemAudioCaptured ? "Captured" : "Not captured")
        ]
    }

    private func processingRows(for entry: MeetingHistoryEntry) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("ASR model", decodedByText(for: entry))
        ]

        if entry.sourceFlags.partial {
            rows.append(("Incomplete", "Yes"))
        }
        if let appVersionText = entry.modelMetadata?.visibleAppVersion {
            rows.append(("App version", appVersionText))
        }
        if let timecodesStatusText = timecodesStatusText(for: entry) {
            rows.append(("Timecodes", timecodesStatusText))
        }
        rows.append(("Processing time", processingTimeText(for: entry)))
        return rows
    }

    private func decodedByText(for entry: MeetingHistoryEntry) -> String {
        entry.modelMetadata?.displayName ?? "Unknown"
    }

    private func timecodesStatusText(for entry: MeetingHistoryEntry) -> String? {
        if transcriptContainsTimecode(in: entry) {
            return nil
        }
        return "Not present"
    }

    private func transcriptContainsTimecode(in entry: MeetingHistoryEntry) -> Bool {
        return entry.transcriptText
            .split(separator: "\n")
            .contains { line in
                line.hasPrefix("[") && line.contains(" - ") && line.contains("]")
            }
    }

    private func processingTimeText(for entry: MeetingHistoryEntry) -> String {
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

    private func speakerCountText(for entry: MeetingHistoryEntry) -> String {
        entry.speakerCount.map(String.init) ?? "—"
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

private struct HistoryView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    @State private var selectedID: VoiceHistoryEntry.ID?
    @State private var entryPendingDeletion: VoiceHistoryEntry?
    @State private var searchText = ""

    private var filteredEntries: [VoiceHistoryEntry] {
        VoiceHistoryFilter(query: searchText)
            .filteredEntries(from: historyStore.entries)
    }

    var body: some View {
        TranscriptWorkspaceView(
            selectedID: $selectedID,
            searchText: $searchText,
            entries: filteredEntries,
            hasSourceEntries: !historyStore.entries.isEmpty,
            entryDate: \.createdAt,
            searchPlaceholder: "Search sessions",
            emptyTitle: "No voice sessions yet",
            emptySystemImage: "mic",
            emptyDescription: "Finished dictations will appear here.",
            noMatchesTitle: "No matching sessions",
            noMatchesSystemImage: "magnifyingglass",
            noMatchesDescription: "Try another search."
        ) {
            EmptyView()
        } rowContent: { entry in
            HistoryRowView(
                entry: entry,
                copyAction: {
                    copyHistoryEntry(entry)
                },
                deleteAction: {
                    entryPendingDeletion = entry
                }
            )
        } centerContent: { entry in
            SessionTranscriptWorkspace(
                entry: entry,
                copyAction: {
                    copyHistoryEntry($0)
                }
            )
        } sidebarContent: { entry in
            SessionMetadataSection(
                entry: entry,
                insertAction: {
                    insertHistoryEntry($0)
                },
                deleteAction: {
                    entryPendingDeletion = $0
                }
            )
        }
        .onAppear {
            selectedID = selectedID ?? filteredEntries.first?.id
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

    private func copyHistoryEntry(_ entry: VoiceHistoryEntry) {
        guard !entry.finalText.trimmed.isEmpty else { return }
        controller.copyToClipboard(entry.finalText)
    }

    private func insertHistoryEntry(_ entry: VoiceHistoryEntry) {
        guard !entry.finalText.trimmed.isEmpty else { return }
        controller.insertText(entry.finalText)
    }
}

private struct HistoryRowView: View {
    let entry: VoiceHistoryEntry
    let copyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                statusIndicator

                Spacer()

                Text(rowMetadata)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(entry.previewText)
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
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
    }

    private var hasCopyableText: Bool {
        !entry.finalText.trimmed.isEmpty
    }

    private var rowMetadata: String {
        var parts = [
            entry.createdAt.formatted(date: .omitted, time: .shortened)
        ]
        if let duration = entry.duration {
            parts.append(MeetingDurationFormatter.historyText(duration))
        }
        return parts.joined(separator: " · ")
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
}

private struct SessionTranscriptWorkspace: View {
    let entry: VoiceHistoryEntry?
    let copyAction: (VoiceHistoryEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                TranscriptTextWorkspace(
                    title: entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()),
                    subtitle: detailSubtitle(for: entry),
                    text: displayText(for: entry),
                    selectionResetID: entry.id,
                    copyAction: {
                        copyAction(entry)
                    },
                    isSecondaryText: entry.finalText.trimmed.isEmpty,
                    isCopyDisabled: entry.finalText.trimmed.isEmpty
                )
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

    private func displayText(for entry: VoiceHistoryEntry) -> String {
        let finalText = entry.finalText.trimmed
        if !finalText.isEmpty {
            return entry.finalText
        }
        if let errorMessage = entry.errorMessage, !errorMessage.trimmed.isEmpty {
            return errorMessage
        }
        return entry.status.title
    }
}

private struct SessionMetadataSection: View {
    let entry: VoiceHistoryEntry?
    let insertAction: (VoiceHistoryEntry) -> Void
    let deleteAction: (VoiceHistoryEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                VStack(spacing: 0) {
                    ScrollView {
                        metadataContent(for: entry)
                            .padding(16)
                    }
                    .frame(maxHeight: .infinity)
                    .scrollIndicators(.automatic)

                    Divider()

                    deleteSessionButton(for: entry)
                }
            } else {
                ContentUnavailableView(
                    "No session selected",
                    systemImage: "sidebar.right",
                    description: Text("Metadata appears after selecting a session.")
                )
            }
        }
    }

    private func metadataContent(for entry: VoiceHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            TranscriptSidebarSection("Actions") {
                insertAgainButton(for: entry)
            }

            TranscriptSidebarSection("Status") {
                TranscriptMetadataValue(entry.status.title)
            }

            TranscriptSidebarSection("Recording") {
                TranscriptMetadataValue(entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
            }

            if let duration = entry.duration {
                TranscriptSidebarSection("Duration") {
                    TranscriptMetadataValue(String(format: "%.1fs", duration))
                }
            }

            if entry.modelMetadata != nil {
                TranscriptSidebarSection("Processing") {
                    TranscriptMetadataGrid(rows: processingRows(for: entry))
                }
            }

            if let timings = entry.timings, !timingRows(timings).isEmpty {
                TranscriptSidebarSection("Timings") {
                    TranscriptMetadataGrid(rows: timingRows(timings))
                }
            }

            if !entry.diagnosticNotes.isEmpty {
                TranscriptSidebarSection("Diagnostics") {
                    Text(entry.diagnosticNotes.joined(separator: "\n"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let errorMessage = entry.errorMessage, !errorMessage.trimmed.isEmpty {
                TranscriptSidebarSection("Error") {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func insertAgainButton(for entry: VoiceHistoryEntry) -> some View {
        Button {
            insertAction(entry)
        } label: {
            Label("Insert Again", systemImage: "arrow.clockwise")
        }
        .disabled(entry.finalText.trimmed.isEmpty)
        .help("Insert Again")
        .accessibilityLabel("Insert Again")
    }

    private func deleteSessionButton(for entry: VoiceHistoryEntry) -> some View {
        Button(role: .destructive) {
            deleteAction(entry)
        } label: {
            Label("Delete session", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .help("Delete session")
        .accessibilityLabel("Delete session")
        .pointingHandCursor()
    }

    private func processingRows(for entry: VoiceHistoryEntry) -> [(label: String, value: String)] {
        var rows = [("Decoded by", entry.modelMetadata?.displayName ?? "Unknown")]
        if let appVersionText = entry.modelMetadata?.visibleAppVersion {
            rows.append(("App version", appVersionText))
        }
        return rows
    }

    private func timingRows(_ timings: VoicePipelineTimings) -> [(label: String, value: String)] {
        [
            ("Recording", timings.recording),
            ("Preprocessing", timings.preprocessing),
            ("Transcription", timings.transcription),
            ("Normalization", timings.normalization),
            ("Insertion", timings.insertion)
        ]
        .compactMap { row in
            guard let duration = row.1 else { return nil }
            return (row.0, format(duration))
        }
    }

    private func format(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }

        return String(format: "%.2f s", duration)
    }
}
