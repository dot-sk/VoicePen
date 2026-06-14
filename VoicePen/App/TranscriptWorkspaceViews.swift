import SwiftUI

struct TranscriptWorkspaceListModel<Entry: Identifiable & Sendable> where Entry.ID: Hashable & Sendable {
    let entries: [Entry]
    let entryIDs: [Entry.ID]
    let dayGroups: [TranscriptDayGroup<Entry>]

    init(
        entries: [Entry],
        entryIDs: [Entry.ID],
        dayGroups: [TranscriptDayGroup<Entry>]
    ) {
        self.entries = entries
        self.entryIDs = entryIDs
        self.dayGroups = dayGroups
    }

    init(entries: [Entry], now: Date = Date(), entryDate: (Entry) -> Date) {
        self.entries = entries
        entryIDs = entries.map(\.id)
        dayGroups =
            TranscriptDayGroups(
                entries: entries,
                now: now,
                date: entryDate
            ).groups
    }
}

struct TranscriptWorkspaceView<
    Entry: Identifiable & Sendable,
    HeaderAccessory: View,
    RowContent: View,
    CenterContent: View,
    SidebarContent: View
>: View where Entry.ID: Hashable & Sendable {
    @Binding var selectedID: Entry.ID?
    @Binding var searchText: String
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.voicePenTheme) private var theme

    let listModel: TranscriptWorkspaceListModel<Entry>
    let hasSourceEntries: Bool
    let searchPlaceholder: String
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let noMatchesTitle: String
    let noMatchesSystemImage: String
    let noMatchesDescription: String
    let showsHeaderAccessory: Bool = true
    @ViewBuilder let headerAccessory: () -> HeaderAccessory
    @ViewBuilder let rowContent: (Entry) -> RowContent
    @ViewBuilder let centerContent: (Entry?) -> CenterContent
    @ViewBuilder let sidebarContent: (Entry?) -> SidebarContent

    @FocusState private var isSearchFocused: Bool
    @State private var isSearchPresented = false

    private var selectedEntry: Entry? {
        guard let selectedID else {
            return listModel.entries.first
        }
        return listModel.entries.first { $0.id == selectedID } ?? listModel.entries.first
    }

    var body: some View {
        HStack(spacing: 0) {
            listPanel
                .frame(
                    minWidth: TranscriptWorkspaceLayout.listMinWidth,
                    idealWidth: TranscriptWorkspaceLayout.listDefaultWidth,
                    maxWidth: TranscriptWorkspaceLayout.listMaxWidth,
                    maxHeight: .infinity
                )

            Divider()

            centerContent(selectedEntry)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            sidebarContent(selectedEntry)
                .frame(
                    minWidth: TranscriptWorkspaceLayout.sidebarMinWidth,
                    idealWidth: TranscriptWorkspaceLayout.sidebarIdealWidth,
                    maxWidth: TranscriptWorkspaceLayout.sidebarMaxWidth,
                    maxHeight: .infinity
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
        .tint(theme.blue)
        .background(searchKeyboardShortcut)
        .modifier(
            TranscriptWorkspaceSearchExitModifier(
                isSearchPresented: isSearchPresented,
                dismissSearch: dismissSearch
            )
        )
        .onAppear {
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: listModel.entryIDs) { _, _ in
            ensureSelectedEntryIsVisible()
        }
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            listHeader

            if !hasSourceEntries {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if listModel.entries.isEmpty {
                ContentUnavailableView(
                    noMatchesTitle,
                    systemImage: noMatchesSystemImage,
                    description: Text(noMatchesDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(listModel.dayGroups, id: \.day) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    rowContent(entry)
                                        .transcriptListRowStyle(isSelected: selectedID == entry.id)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedID = entry.id
                                        }
                                }
                            } header: {
                                TranscriptDaySectionHeader(title: group.title)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .id(listModel.entryIDs)
                .scrollIndicators(.automatic)
            }
        }
        .background(theme.background)
    }

    private var listHeader: some View {
        VStack(spacing: 10) {
            if isSearchPresented {
                searchField
                    .transition(searchFieldTransition)
            }

            if showsHeaderAccessory {
                headerAccessory()
            }
        }
        .padding(.horizontal, hasVisibleHeaderContent ? 16 : 0)
        .padding(.top, hasVisibleHeaderContent ? 16 : 0)
        .padding(.bottom, hasVisibleHeaderContent ? 10 : 0)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(theme.textTertiary)

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            Text("⌘F")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.surfaceElevated)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.border)
        }
    }

    private var searchKeyboardShortcut: some View {
        Button {
            presentSearch()
        } label: {
            EmptyView()
        }
        .keyboardShortcut("f", modifiers: [.command])
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var searchFieldTransition: AnyTransition {
        if accessibilityReduceMotion {
            return .opacity
        }

        return .move(edge: .top).combined(with: .opacity)
    }

    private var searchPresentationAnimation: Animation? {
        accessibilityReduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.16)
    }

    private var hasVisibleHeaderContent: Bool {
        isSearchPresented || showsHeaderAccessory
    }

    private func presentSearch() {
        guard !isSearchPresented else {
            focusSearchField()
            return
        }

        withAnimation(searchPresentationAnimation) {
            isSearchPresented = true
        }
        focusSearchField()
    }

    private func dismissSearch() {
        guard isSearchPresented else { return }
        searchText = ""
        isSearchFocused = false
        withAnimation(searchPresentationAnimation) {
            isSearchPresented = false
        }
    }

    private func focusSearchField() {
        Task { @MainActor in
            await Task.yield()
            isSearchFocused = true
        }
    }

    private func ensureSelectedEntryIsVisible() {
        guard !listModel.entries.contains(where: { $0.id == selectedID }) else { return }
        selectedID = listModel.entries.first?.id
    }
}

private struct TranscriptWorkspaceSearchExitModifier: ViewModifier {
    let isSearchPresented: Bool
    let dismissSearch: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSearchPresented {
            content
                .onExitCommand {
                    dismissSearch()
                }
        } else {
            content
        }
    }
}

struct TranscriptTextWorkspace: View {
    let title: String
    let text: String
    let textSnapshot: TranscriptTextSnapshot
    let selectionResetID: UUID
    let copyAction: () -> Void
    var isSecondaryText = false
    var isCopyDisabled = false
    var showsLineNumbers = true
    @Environment(\.voicePenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TranscriptTextEditor(
                fileName: title,
                text: text,
                textSnapshot: textSnapshot,
                selectionResetID: selectionResetID,
                copyAction: copyAction,
                isSecondaryText: isSecondaryText,
                isCopyDisabled: isCopyDisabled,
                showsLineNumbers: showsLineNumbers
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(theme.background)
    }
}

enum TranscriptWorkspaceLayout {
    static let listMinWidth: CGFloat = 214
    static let listDefaultWidth: CGFloat = 248
    static let listMaxWidth: CGFloat = 294
    static let sidebarMinWidth: CGFloat = 225
    static let sidebarIdealWidth: CGFloat = 265
    static let sidebarMaxWidth: CGFloat = 305
}

struct TranscriptDaySectionHeader: View {
    @Environment(\.voicePenTheme) private var theme
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.background)
    }
}

struct TranscriptListRowStyle: ViewModifier {
    @Environment(\.voicePenTheme) private var theme
    let isSelected: Bool
    @State private var isHovered = false

    private var backgroundColor: Color {
        if isSelected {
            return theme.blue.opacity(theme.isDark ? 0.28 : 0.14)
        }
        return isHovered ? theme.blue.opacity(theme.isDark ? 0.12 : 0.07) : Color.clear
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            }
            .padding(.horizontal, 6)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isSelected)
    }
}

extension View {
    func transcriptListRowStyle(isSelected: Bool) -> some View {
        modifier(TranscriptListRowStyle(isSelected: isSelected))
    }
}

struct TranscriptSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TranscriptMetadataGrid: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(rows, id: \.label) { row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                    TranscriptMetadataValue(row.value)
                }
            }
        }
        .font(.system(size: 12))
    }
}

struct TranscriptMetadataValue: View {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value)
            .font(.system(size: 12))
            .textSelection(.enabled)
    }
}
