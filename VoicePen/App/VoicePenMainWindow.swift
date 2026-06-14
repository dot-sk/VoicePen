import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct VoicePenMainWindow: View {
    @ObservedObject var controller: AppController
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSection: VoicePenSettingsSection? = .general
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private let primarySidebarSections: [VoicePenSettingsSection] = [
        .general,
        .meetings,
        .history
    ]

    private var settingsSidebarSections: [VoicePenSettingsSection] {
        var sections: [VoicePenSettingsSection] = [
            .dictionary,
            .model
        ]
        if VoicePenConfig.modesFeatureEnabled {
            sections.append(.modes)
        }
        sections.append(contentsOf: [
            .about
        ])
        return sections
    }

    private var theme: VoicePenTheme {
        VoicePenTheme.resolve(colorScheme)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VoicePenIconSidebar(
                selectedSection: $selectedSection,
                primarySections: primarySidebarSections,
                settingsSections: settingsSidebarSections,
                bottomSections: [.config],
                systemImage: systemImage(for:)
            )
            .navigationSplitViewColumnWidth(min: 72, ideal: 72, max: 72)
        } detail: {
            NavigationStack {
                Group {
                    if let selectedSection {
                        detailView(for: selectedSection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Select a section",
                            systemImage: "sidebar.left",
                            description: Text("VoicePen settings will appear here.")
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selectedSection?.title ?? "VoicePen")
            }
        }
        .environment(\.voicePenTheme, theme)
        .background(theme.background)
        .tint(theme.blue)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MeetingRecordingPanel(controller: controller)
        }
        .background {
            MainWindowCloseLifecycleBridge()
                .frame(width: 0, height: 0)

            SidebarNavigationShortcutMonitor(selectSection: { section in
                selectedSection = section
            })
            .frame(width: 0, height: 0)

            MeetingRecordingShortcutMonitor(toggleRecording: toggleMeetingRecording)
                .frame(width: 0, height: 0)
        }
        .onAppear {
            applyNavigationRequest(controller.mainWindowNavigationRequest)
        }
        .onChange(of: controller.mainWindowNavigationRequest) { _, request in
            applyNavigationRequest(request)
        }
        .onChange(of: columnVisibility) { _, visibility in
            if visibility != .all {
                columnVisibility = .all
            }
        }
        .frame(minWidth: 920, minHeight: 560)
    }

    private struct MainWindowCloseLifecycleBridge: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            MainWindowCloseLifecycleView(coordinator: context.coordinator)
        }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.bind(to: view.window)
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            coordinator.detach()
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        final class MainWindowCloseLifecycleView: NSView {
            private let coordinator: Coordinator

            init(coordinator: Coordinator) {
                self.coordinator = coordinator
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) {
                nil
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                coordinator.bind(to: window)
            }
        }

        final class Coordinator {
            private weak var observedWindow: NSWindow?
            private var closeObserver: NSObjectProtocol?

            func bind(to window: NSWindow?) {
                guard let window else {
                    return
                }

                configureNativeSidebarChrome(window)

                guard observedWindow !== window else {
                    return
                }

                removeObservers()

                observedWindow = window
                closeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    DispatchQueue.main.async {
                        NSApplication.shared.setActivationPolicy(.accessory)
                    }
                }
            }

            private func configureNativeSidebarChrome(_ window: NSWindow) {
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                window.toolbarStyle = .unifiedCompact
                window.titlebarSeparatorStyle = .none
                window.isMovableByWindowBackground = true
            }

            func detach() {
                removeObservers()
                observedWindow = nil
            }

            private func removeObservers() {
                if let closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                    self.closeObserver = nil
                }
            }
        }
    }

    private func applyNavigationRequest(_ request: MainWindowNavigationRequest?) {
        guard request?.destination == .meetings else { return }
        selectedSection = .meetings
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

        guard controller.canStartMeetingRecording else {
            return false
        }

        controller.startMeetingRecording()
        return true
    }
}

private struct SidebarNavigationShortcutMonitor: NSViewRepresentable {
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
            return flags.contains(.command) && flags.isDisjoint(with: disallowedFlags)
        }
    }
}

private struct VoicePenIconSidebar: View {
    @Environment(\.voicePenTheme) private var theme
    @Binding var selectedSection: VoicePenSettingsSection?
    @State private var hoveredSection: VoicePenSettingsSection?

    private let verticalPadding: CGFloat = 10

    let primarySections: [VoicePenSettingsSection]
    let settingsSections: [VoicePenSettingsSection]
    let bottomSections: [VoicePenSettingsSection]
    let systemImage: (VoicePenSettingsSection) -> String

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    sidebarButtons(primarySections)

                    sidebarButtons(settingsSections)
                }
                .padding(.top, topPadding(for: proxy.safeAreaInsets.top))

                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    sidebarDivider

                    sidebarButtons(bottomSections)
                }
                .padding(.bottom, verticalPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .background(theme.heroBackground)
    }

    private func topPadding(for safeAreaTopInset: CGFloat) -> CGFloat {
        max(verticalPadding, safeAreaTopInset + verticalPadding)
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sidebarButtons(_ sections: [VoicePenSettingsSection]) -> some View {
        ForEach(sections) { section in
            VoicePenIconSidebarButton(
                section: section,
                systemImage: systemImage(section),
                isSelected: selectedSection == section,
                isHovered: hoveredSection == section,
                theme: theme
            ) {
                selectedSection = section
            }
            .onHover { isHovered in
                hoveredSection = isHovered ? section : nil
            }
        }
    }
}

private struct VoicePenIconSidebarButton: View {
    let section: VoicePenSettingsSection
    let systemImage: String
    let isSelected: Bool
    let isHovered: Bool
    let theme: VoicePenTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 38)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderFill, lineWidth: isSelected || isHovered ? 1 : 0)
        }
    }

    private var iconColor: Color {
        if isSelected {
            return theme.blue
        }
        if isHovered {
            return theme.textPrimary
        }
        return theme.textSecondary
    }

    private var backgroundFill: LinearGradient {
        if isSelected {
            return theme.glassFill(tint: theme.blue)
        }
        if isHovered {
            return theme.glassFill(tint: theme.textSecondary)
        }
        return LinearGradient(
            colors: [.clear, .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderFill: LinearGradient {
        if isSelected {
            return theme.glassStroke(tint: theme.blue)
        }
        if isHovered {
            return theme.glassStroke(tint: theme.textSecondary)
        }
        return LinearGradient(
            colors: [.clear, .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct DictionaryEditorView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var dictionaryStore: DictionaryStore
    @Environment(\.voicePenTheme) private var theme
    @State private var selectedID: String?
    @State private var isCreatingNewEntry = false
    @State private var draft = TermEntryDraft()
    @State private var message: String?
    @State private var showingDeleteConfirmation = false
    @State private var searchText = ""
    @State private var reviewPreset = DictionaryReviewPromptPreset.dictionaryImprovement
    @State private var historyReviewLimit = HistoryReviewLimit.defaultValue
    @State private var pendingImportPreview: PendingDictionaryImportPreview?
    @State private var filteredEntries: [TermEntry] = []

    private var selectedEntry: TermEntry? {
        guard !isCreatingNewEntry else { return nil }
        guard let selectedID else { return filteredEntries.first }
        return filteredEntries.first { $0.id == selectedID } ?? filteredEntries.first
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
                        .scrollContentBackground(.hidden)
                        .background(theme.background)
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
                .voicePenThemedScreen(theme)
                .frame(minWidth: 340, idealWidth: 420)
            }
        }
        .background(theme.background)
        .onAppear {
            refreshFilteredEntries()
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
            refreshFilteredEntries()
            guard !isCreatingNewEntry else { return }
            guard !entries.contains(where: { $0.id == selectedID }) else {
                ensureSelectedEntryIsVisible()
                return
            }
            selectedID = filteredEntries.first?.id
            loadSelectedEntry()
        }
        .onChange(of: searchText) { _, _ in
            refreshFilteredEntries()
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

    private func refreshFilteredEntries() {
        filteredEntries = DictionaryEntryFilter(query: searchText)
            .filteredEntries(from: dictionaryStore.entries)
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
    @Environment(\.voicePenTheme) private var theme
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
        .background(theme.surfaceElevated)
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
    @Environment(\.voicePenTheme) private var theme
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
        .background(theme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.border, lineWidth: 1)
        }
    }

    private var diffText: Text {
        example.diff.enumerated().reduce(Text("")) { partial, element in
            let suffix = element.offset == example.diff.count - 1 ? "" : " "
            let token = element.element
            let text = Text(token.text + suffix)

            switch token.change {
            case .unchanged:
                return partial + text.foregroundStyle(theme.textPrimary)
            case .removed:
                return partial + text.foregroundStyle(theme.red).strikethrough()
            case .inserted:
                return partial + text.foregroundStyle(theme.green)
            }
        }
    }
}

private struct DictionaryListEditor: View {
    @Environment(\.voicePenTheme) private var theme
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
                .background(theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border, lineWidth: 1)
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
    @Environment(\.voicePenTheme) private var theme

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
                        showsDeterminateProgress(progress)
                    {
                        ProgressView(value: progress.fraction, total: 1.0)
                            .controlSize(.small)
                            .frame(width: 72)
                        Label(progressLabel(for: progress), systemImage: "waveform")
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Label("Processing Transcript", systemImage: "waveform")
                    }
                    Button(role: .cancel) {
                        controller.cancelMeetingProcessing()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Cancel Meeting Processing")
                    .accessibilityLabel("Cancel Meeting Processing")
                    .pointingHandCursor()
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
            .foregroundStyle(theme.textSecondary)
            .background(theme.surfaceElevated)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)
            }
        }
    }

    private var showsPanel: Bool {
        controller.appState.showsMeetingRecordingPanel
    }

    private func showsDeterminateProgress(_ progress: MeetingProcessingProgress) -> Bool {
        progress.totalChunks > 1 || progress.stage != .transcribing
    }

    private func progressLabel(for progress: MeetingProcessingProgress) -> String {
        switch progress.stage {
        case .transcribing:
            return "Processing \(progress.percent)%"
        case .labelingSpeakers:
            return "Labeling speakers \(progress.percent)%"
        case .finishing:
            return "Finishing \(progress.percent)%"
        }
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
    @Environment(\.voicePenTheme) private var theme
    @State private var isDimmed = false

    var body: some View {
        Circle()
            .fill(theme.red)
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
            return flags.contains(.command) && flags.isDisjoint(with: disallowedFlags)
        }
    }
}

extension View {
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
