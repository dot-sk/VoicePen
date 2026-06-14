import SwiftUI

struct MeetingHistoryActions {
    let retryProcessing: (MeetingHistoryEntry) -> Void
    let copyTranscript: (MeetingHistoryEntry) -> Void
    let deleteEntry: (MeetingHistoryEntry.ID) -> Void
    let cleanupExpiredRecoveryAudio: () -> Void
    let existingArchivedAudioURLs: (MeetingHistoryEntry) -> [URL]
    let revealArchivedAudio: (MeetingHistoryEntry) -> Void
    let toggleRecording: () -> Bool
    let cancelRecording: () -> Void

    init(
        retryProcessing: @escaping (MeetingHistoryEntry) -> Void,
        copyTranscript: @escaping (MeetingHistoryEntry) -> Void,
        deleteEntry: @escaping (MeetingHistoryEntry.ID) -> Void,
        cleanupExpiredRecoveryAudio: @escaping () -> Void,
        existingArchivedAudioURLs: @escaping (MeetingHistoryEntry) -> [URL],
        revealArchivedAudio: @escaping (MeetingHistoryEntry) -> Void,
        toggleRecording: @escaping () -> Bool,
        cancelRecording: @escaping () -> Void
    ) {
        self.retryProcessing = retryProcessing
        self.copyTranscript = copyTranscript
        self.deleteEntry = deleteEntry
        self.cleanupExpiredRecoveryAudio = cleanupExpiredRecoveryAudio
        self.existingArchivedAudioURLs = existingArchivedAudioURLs
        self.revealArchivedAudio = revealArchivedAudio
        self.toggleRecording = toggleRecording
        self.cancelRecording = cancelRecording
    }

    @MainActor
    init(controller: AppController) {
        self.init(
            retryProcessing: { controller.retryMeetingProcessing($0) },
            copyTranscript: { controller.copyMeetingTranscript($0) },
            deleteEntry: { controller.deleteMeetingEntry(id: $0) },
            cleanupExpiredRecoveryAudio: { controller.cleanupExpiredMeetingRecoveryAudio() },
            existingArchivedAudioURLs: { controller.existingArchivedAudioURLs(for: $0) },
            revealArchivedAudio: { controller.revealArchivedAudio(for: $0) },
            toggleRecording: {
                if controller.appState.isMeetingCaptureActive {
                    controller.stopMeetingRecording()
                    return true
                }

                guard controller.canStartMeetingRecording else {
                    return false
                }

                controller.startMeetingRecording()
                return true
            },
            cancelRecording: { controller.cancelMeetingRecording() }
        )
    }

    static let preview = MeetingHistoryActions(
        retryProcessing: { _ in },
        copyTranscript: { _ in },
        deleteEntry: { _ in },
        cleanupExpiredRecoveryAudio: {},
        existingArchivedAudioURLs: { entry in
            entry.archivedAudioURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        },
        revealArchivedAudio: { _ in },
        toggleRecording: { false },
        cancelRecording: {}
    )
}

struct MeetingRecordingControlsState: Equatable {
    var isCaptureActive: Bool
    var canStartRecording: Bool

    @MainActor
    init(controller: AppController) {
        self.init(
            isCaptureActive: controller.appState.isMeetingCaptureActive,
            canStartRecording: controller.canStartMeetingRecording
        )
    }

    init(isCaptureActive: Bool = false, canStartRecording: Bool = true) {
        self.isCaptureActive = isCaptureActive
        self.canStartRecording = canStartRecording
    }
}

struct MeetingsView: View {
    @ObservedObject var meetingHistoryStore: MeetingHistoryStore
    let recordingState: MeetingRecordingControlsState
    let actions: MeetingHistoryActions
    @Environment(\.voicePenTheme) private var theme
    @State private var selectedID: MeetingHistoryEntry.ID?
    @State private var entryPendingDeletion: MeetingHistoryEntry?
    @State private var focusedEntry: MeetingHistoryEntry?
    @State private var focusedTextUIState: TranscriptTextUIState?
    @State private var searchText = ""
    @State private var listModel = TranscriptWorkspaceListModel<MeetingHistoryEntry>(
        entries: [],
        entryIDs: [],
        dayGroups: []
    )

    @MainActor
    init(controller: AppController, meetingHistoryStore: MeetingHistoryStore) {
        self.meetingHistoryStore = meetingHistoryStore
        recordingState = MeetingRecordingControlsState(controller: controller)
        actions = MeetingHistoryActions(controller: controller)
    }

    init(
        meetingHistoryStore: MeetingHistoryStore,
        recordingState: MeetingRecordingControlsState = MeetingRecordingControlsState(),
        actions: MeetingHistoryActions
    ) {
        self.meetingHistoryStore = meetingHistoryStore
        self.recordingState = recordingState
        self.actions = actions
    }

    private var selectedSummaryEntry: MeetingHistoryEntry? {
        guard let selectedID else {
            return listModel.entries.first
        }
        return listModel.entries.first { $0.id == selectedID } ?? listModel.entries.first
    }

    var body: some View {
        TranscriptWorkspaceView(
            selectedID: $selectedID,
            searchText: $searchText,
            listModel: listModel,
            hasSourceEntries: !meetingHistoryStore.entries.isEmpty,
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
                retryAction: { actions.retryProcessing(entry) },
                copyAction: { actions.copyTranscript(entry) },
                deleteAction: { entryPendingDeletion = entry }
            )
        } centerContent: { entry in
            MeetingTranscriptWorkspace(
                entry: focusedEntry(for: entry),
                textUIState: textUIState(for: focusedEntry(for: entry)),
                copyAction: { actions.copyTranscript($0) }
            )
        } sidebarContent: { entry in
            MeetingMetadataSection(
                entry: focusedEntry(for: entry),
                textUIState: textUIState(for: focusedEntry(for: entry)),
                actions: actions,
                deleteAction: { entryPendingDeletion = $0 }
            )
        }
        .onAppear {
            refreshListModel()
            actions.cleanupExpiredRecoveryAudio()
            selectedID = selectedID ?? listModel.entries.first?.id
        }
        .onChange(of: meetingHistoryStore.entries) { _, _ in
            focusedEntry = nil
            focusedTextUIState = nil
            refreshListModel()
        }
        .onChange(of: searchText) { _, _ in
            refreshListModel()
            if !listModel.entries.contains(where: { $0.id == focusedEntry?.id }) {
                focusedEntry = nil
                focusedTextUIState = nil
                refreshListModel()
            }
        }
        .onChange(of: selectedID) { _, newSelectedID in
            if focusedEntry?.id != newSelectedID {
                focusedEntry = nil
                focusedTextUIState = nil
                refreshListModel()
            }
        }
        .task(id: selectedID) {
            await Task.yield()
            loadFocusedEntry()
        }
        .alert("Delete meeting?", isPresented: deleteConfirmationBinding) {
            Button("Delete", role: .destructive) {
                if let entryPendingDeletion {
                    actions.deleteEntry(entryPendingDeletion.id)
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

    private var canUseMeetingRecordingPrimaryAction: Bool {
        recordingState.isCaptureActive || recordingState.canStartRecording
    }

    @ViewBuilder
    private var meetingRecordingControls: some View {
        HStack(spacing: 8) {
            if recordingState.isCaptureActive {
                Button(role: .destructive) {
                    actions.cancelRecording()
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
                _ = actions.toggleRecording()
            } label: {
                HStack(spacing: 8) {
                    if recordingState.isCaptureActive {
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
        recordingState.isCaptureActive ? "Stop Meeting Recording" : "Start Meeting Recording"
    }

    private var meetingRecordingPrimaryButtonColor: Color {
        if recordingState.isCaptureActive {
            return theme.red
        }
        return recordingState.canStartRecording ? theme.blue : theme.blue.opacity(0.45)
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
            focusedTextUIState = nil
            refreshListModel()
            return
        }

        do {
            let loadedEntry = try meetingHistoryStore.loadEntry(id: selectedSummaryEntry.id) ?? selectedSummaryEntry
            focusedEntry = loadedEntry
            focusedTextUIState = TranscriptTextUIState.make(
                text: MeetingHistoryStore.displayText(for: loadedEntry),
                previous: focusedTextUIState
            )
            refreshListModel()
        } catch {
            focusedEntry = selectedSummaryEntry
            focusedTextUIState = textUIState(for: selectedSummaryEntry)
            refreshListModel()
        }
    }

    private func focusedEntry(for entry: MeetingHistoryEntry?) -> MeetingHistoryEntry? {
        guard let entry else { return nil }
        return focusedEntry?.id == entry.id ? focusedEntry : entry
    }

    private func textUIState(for entry: MeetingHistoryEntry?) -> TranscriptTextUIState {
        guard let entry else { return .empty }
        if focusedEntry?.id == entry.id, let focusedTextUIState {
            return focusedTextUIState
        }
        return meetingHistoryStore.transcriptTextUIStates[entry.id] ?? .empty
    }

    private func refreshListModel() {
        let entries = MeetingHistoryFilter(query: searchText)
            .filteredEntries(from: searchableEntries())
        listModel = TranscriptWorkspaceListModel(entries: entries, entryDate: \.createdAt)
    }

    private func searchableEntries() -> [MeetingHistoryEntry] {
        guard let focusedEntry else {
            return meetingHistoryStore.entries
        }
        return meetingHistoryStore.entries.map { entry in
            entry.id == focusedEntry.id ? focusedEntry : entry
        }
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
    let textUIState: TranscriptTextUIState
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
            text: MeetingHistoryStore.displayText(for: entry),
            textSnapshot: textUIState.snapshot,
            selectionResetID: entry.id,
            copyAction: {
                copyAction(entry)
            },
            isSecondaryText: entry.transcriptText.trimmed.isEmpty,
            isCopyDisabled: entry.transcriptText.trimmed.isEmpty,
            contentPadding: 0
        )
    }
}

private struct MeetingMetadataSection: View {
    @Environment(\.voicePenTheme) private var theme
    let entry: MeetingHistoryEntry?
    let textUIState: TranscriptTextUIState
    let actions: MeetingHistoryActions
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

            if !actions.existingArchivedAudioURLs(entry).isEmpty {
                TranscriptSidebarSection("Local recording") {
                    revealArchivedAudioButton(for: entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func retryButton(for entry: MeetingHistoryEntry) -> some View {
        Button {
            actions.retryProcessing(entry)
        } label: {
            Label("Retry Processing", systemImage: "arrow.clockwise")
        }
        .disabled(!isRecoveryAudioAvailable(entry))
        .help("Retry Processing")
        .accessibilityLabel("Retry Processing")
    }

    private func revealArchivedAudioButton(for entry: MeetingHistoryEntry) -> some View {
        Button {
            actions.revealArchivedAudio(entry)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal in Finder")
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
        .foregroundStyle(theme.red)
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
        if let timecodesStatusText = timecodesStatusText() {
            rows.append(("Timecodes", timecodesStatusText))
        }
        rows.append(("Processing time", processingTimeText(for: entry)))
        rows.append(contentsOf: pipelineTimingRows(for: entry))
        return rows
    }

    private func decodedByText(for entry: MeetingHistoryEntry) -> String {
        entry.modelMetadata?.displayName ?? "Unknown"
    }

    private func timecodesStatusText() -> String? {
        if textUIState.containsTimecode {
            return nil
        }
        return "Not present"
    }

    private func processingTimeText(for entry: MeetingHistoryEntry) -> String {
        let total = [
            entry.timings?.preprocessing,
            entry.timings?.transcription,
            entry.timings?.diarization
        ]
        .compactMap { $0 }
        .reduce(0, +)

        guard total > 0 else {
            return "Unknown"
        }

        return formatProcessingDuration(total)
    }

    private func pipelineTimingRows(for entry: MeetingHistoryEntry) -> [(label: String, value: String)] {
        guard let timings = entry.timings else {
            return []
        }

        return [
            ("Preprocessing", timings.preprocessing),
            ("ASR", timings.transcription),
            ("Diarization", timings.diarization)
        ]
        .compactMap { row in
            guard let duration = row.1 else { return nil }
            return (row.0, formatProcessingDuration(duration))
        }
    }

    private func formatProcessingDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return "\(Int((duration * 1_000).rounded())) ms"
        }

        return String(format: "%.2f s", duration)
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
            return "The retry window has expired."
        }

        if !recoveryAudio.hasAvailableAudio() {
            return "The saved audio files are missing."
        }

        return "Retry is available until \(recoveryAudio.expiresAt.formatted(date: .abbreviated, time: .shortened))."
    }
}
