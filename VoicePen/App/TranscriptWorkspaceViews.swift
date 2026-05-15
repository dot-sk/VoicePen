import SwiftUI

struct TranscriptWorkspaceView<
    Entry: Identifiable & Sendable,
    HeaderAccessory: View,
    RowContent: View,
    CenterContent: View,
    SidebarContent: View
>: View where Entry.ID: Hashable & Sendable {
    @Binding var selectedID: Entry.ID?
    @Binding var searchText: String

    let entries: [Entry]
    let hasSourceEntries: Bool
    let entryDate: (Entry) -> Date
    let searchPlaceholder: String
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: String
    let noMatchesTitle: String
    let noMatchesSystemImage: String
    let noMatchesDescription: String
    @ViewBuilder let headerAccessory: () -> HeaderAccessory
    @ViewBuilder let rowContent: (Entry) -> RowContent
    @ViewBuilder let centerContent: (Entry?) -> CenterContent
    @ViewBuilder let sidebarContent: (Entry?) -> SidebarContent

    @FocusState private var isSearchFocused: Bool

    private var selectedEntry: Entry? {
        guard let selectedID else {
            return entries.first
        }
        return entries.first { $0.id == selectedID } ?? entries.first
    }

    private var entryIDs: [Entry.ID] {
        entries.map(\.id)
    }

    private var dayGroups: [TranscriptDayGroup<Entry>] {
        TranscriptDayGroups(
            entries: entries,
            now: Date(),
            date: entryDate
        ).groups
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
        .background(searchKeyboardShortcut)
        .onAppear {
            ensureSelectedEntryIsVisible()
        }
        .onChange(of: entryIDs) { _, _ in
            ensureSelectedEntryIsVisible()
        }
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            listHeader
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 10)

            if !hasSourceEntries {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView(
                    noMatchesTitle,
                    systemImage: noMatchesSystemImage,
                    description: Text(noMatchesDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(dayGroups, id: \.day) { group in
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
                .id(entryIDs)
                .scrollIndicators(.automatic)
            }
        }
    }

    private var listHeader: some View {
        VStack(spacing: 10) {
            searchField
            headerAccessory()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)

            Text("⌘F")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        }
    }

    private var searchKeyboardShortcut: some View {
        Button {
            isSearchFocused = true
        } label: {
            EmptyView()
        }
        .keyboardShortcut("f", modifiers: [.command])
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func ensureSelectedEntryIsVisible() {
        guard !entries.contains(where: { $0.id == selectedID }) else { return }
        selectedID = entries.first?.id
    }
}

struct TranscriptTextWorkspace: View {
    let title: String
    let subtitle: String
    let text: String
    let selectionResetID: UUID
    let copyAction: () -> Void
    var isSecondaryText = false
    var isCopyDisabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            TranscriptTextEditor(
                text: text,
                selectionResetID: selectionResetID,
                copyAction: copyAction,
                isSecondaryText: isSecondaryText,
                isCopyDisabled: isCopyDisabled
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
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

struct TranscriptListRowStyle: ViewModifier {
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
