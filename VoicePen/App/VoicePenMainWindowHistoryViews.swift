import SwiftUI

struct HistoryView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var historyStore: VoiceHistoryStore
    @State private var selectedID: VoiceHistoryEntry.ID?
    @State private var entryPendingDeletion: VoiceHistoryEntry?
    @State private var searchText = ""
    @State private var listModel = TranscriptWorkspaceListModel<VoiceHistoryEntry>(
        entries: [],
        entryIDs: [],
        dayGroups: []
    )

    var body: some View {
        TranscriptWorkspaceView(
            selectedID: $selectedID,
            searchText: $searchText,
            listModel: listModel,
            hasSourceEntries: !historyStore.entries.isEmpty,
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
                textUIState: textUIState(for: entry),
                copyAction: {
                    copyHistoryEntry($0)
                }
            )
        } sidebarContent: { entry in
            SessionMetadataSection(
                controller: controller,
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
            refreshListModel()
            selectedID = selectedID ?? listModel.entries.first?.id
        }
        .onChange(of: historyStore.entries) { _, _ in
            refreshListModel()
        }
        .onChange(of: searchText) { _, _ in
            refreshListModel()
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

    private func textUIState(for entry: VoiceHistoryEntry?) -> TranscriptTextUIState {
        guard let entry else { return .empty }
        return historyStore.transcriptTextUIStates[entry.id] ?? .empty
    }

    private func refreshListModel() {
        let entries = VoiceHistoryFilter(query: searchText)
            .filteredEntries(from: historyStore.entries)
        listModel = TranscriptWorkspaceListModel(entries: entries, entryDate: \.createdAt)
    }
}

struct HistoryRowView: View {
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

struct SessionTranscriptWorkspace: View {
    let entry: VoiceHistoryEntry?
    let textUIState: TranscriptTextUIState
    let copyAction: (VoiceHistoryEntry) -> Void

    var body: some View {
        Group {
            if let entry {
                TranscriptTextWorkspace(
                    title: entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()),
                    text: VoiceHistoryStore.displayText(for: entry),
                    textSnapshot: textUIState.snapshot,
                    selectionResetID: entry.id,
                    copyAction: {
                        copyAction(entry)
                    },
                    isSecondaryText: entry.finalText.trimmed.isEmpty,
                    isCopyDisabled: entry.finalText.trimmed.isEmpty,
                    showsLineNumbers: false
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
}

struct SessionMetadataSection: View {
    @ObservedObject var controller: AppController
    @Environment(\.voicePenTheme) private var theme
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

            if !controller.existingArchivedAudioURLs(for: entry).isEmpty {
                TranscriptSidebarSection("Local recording") {
                    revealArchivedAudioButton(for: entry)
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

    private func revealArchivedAudioButton(for entry: VoiceHistoryEntry) -> some View {
        Button {
            controller.revealArchivedAudio(for: entry)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal in Finder")
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
        .foregroundStyle(theme.red)
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
