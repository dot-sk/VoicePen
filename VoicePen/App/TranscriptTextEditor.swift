import AppKit
import STTextView
import SwiftUI

struct TranscriptTextEditor: View {
    let fileName: String
    let text: String
    let textSnapshot: TranscriptTextSnapshot
    let selectionResetID: UUID
    let copyAction: () -> Void
    var isSecondaryText = false
    var isCopyDisabled = false
    var showsLineNumbers = true
    @Environment(\.voicePenTheme) private var theme
    @State private var copyFeedbackTrigger = 0
    @State private var isCopyButtonHovered = false

    private let footerHeight: CGFloat = 26
    private let footerDividerHeight: CGFloat = 1

    private var footerReservedHeight: CGFloat {
        footerHeight + footerDividerHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)

            Divider()
                .zIndex(1)

            ZStack(alignment: .bottom) {
                ReadOnlyTranscriptTextView(
                    text: text,
                    textSnapshot: textSnapshot,
                    selectionResetID: selectionResetID,
                    foregroundColor: isSecondaryText ? .secondaryLabelColor : .labelColor,
                    bottomContentInset: footerReservedHeight,
                    copyFullTranscriptAction: copyTranscriptWithFeedback,
                    showsLineNumbers: showsLineNumbers
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footerOverlay
            }
            .clipped()
        }
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.border, lineWidth: 1)
        }
        .background {
            TranscriptCopyShortcutMonitor(
                isEnabled: !isCopyDisabled,
                copyFullTranscriptAction: copyTranscriptWithFeedback
            )
            .frame(width: 0, height: 0)
        }
    }

    private var header: some View {
        HStack {
            CopyButton(
                title: "Copy",
                copiedTitle: "Copied",
                systemImage: "doc.on.doc",
                presentation: .label,
                isDisabled: isCopyDisabled,
                feedbackTrigger: copyFeedbackTrigger,
                action: copyAction
            )
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(copyButtonBackgroundColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            }
            .onHover { isCopyButtonHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isCopyButtonHovered)

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(headerBackgroundColor)
    }

    private var footerOverlay: some View {
        VStack(spacing: 0) {
            Divider()
            footer
        }
        .background(statusLineBackgroundColor)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .zIndex(1)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            statusSegment(
                "READONLY",
                foreground: Color(nsColor: .selectedMenuItemTextColor),
                background: theme.blue,
                weight: .semibold,
                showsChevron: true
            )
            .zIndex(1)

            statusSegment(
                fileName,
                foreground: .primary,
                background: theme.border.opacity(theme.isDark ? 0.50 : 0.45),
                weight: .medium,
                maxWidth: .infinity,
                showsChevron: true
            )
            .zIndex(0)

            HStack(spacing: 10) {
                statusMetric("\(metrics.lineCount)L")
                statusMetric("\(metrics.characterCount)C")
            }
            .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: footerHeight)
        .background(statusLineBackgroundColor)
        .textSelection(.enabled)
    }

    private var metrics: TranscriptEditorMetrics {
        textSnapshot.metrics
    }

    private var copyButtonBackgroundColor: Color {
        if isCopyDisabled {
            return theme.surfaceElevated.opacity(0.6)
        }

        return isCopyButtonHovered
            ? theme.blue.opacity(theme.isDark ? 0.20 : 0.12)
            : theme.surfaceElevated
    }

    private var headerBackgroundColor: Color {
        theme.surfaceElevated
    }

    private var statusLineFont: Font {
        .system(size: 11, design: .monospaced)
    }

    private var statusLineBackgroundColor: Color {
        theme.surfaceElevated
    }

    private func statusMetric(_ text: String) -> some View {
        Text(text)
            .font(statusLineFont)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func statusSegment(
        _ text: String,
        foreground: Color,
        background: Color,
        weight: Font.Weight,
        maxWidth: CGFloat? = nil,
        showsChevron: Bool
    ) -> some View {
        Text(text)
            .font(statusLineFont.weight(weight))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 10)
            .padding(.trailing, showsChevron ? 20 : 10)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .frame(height: footerHeight)
            .background {
                StatusLineSegmentShape(chevronWidth: showsChevron ? 13 : 0)
                    .fill(background)
            }
            .fixedSize(horizontal: maxWidth == nil, vertical: false)
    }

    private func copyTranscriptWithFeedback() {
        guard !isCopyDisabled else {
            return
        }

        copyAction()
        copyFeedbackTrigger += 1
    }
}

private struct StatusLineSegmentShape: Shape {
    let chevronWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let pointWidth = min(max(chevronWidth, 0), rect.width)
        var path = Path()

        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX - pointWidth, y: rect.minY))
        if pointWidth > 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX - pointWidth, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct ReadOnlyTranscriptTextView: NSViewRepresentable {
    let text: String
    let textSnapshot: TranscriptTextSnapshot
    let selectionResetID: UUID
    let foregroundColor: NSColor
    let bottomContentInset: CGFloat
    let copyFullTranscriptAction: () -> Void
    let showsLineNumbers: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CopyableTranscriptSTTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        applyScrollInsets(to: scrollView)

        guard let textView = scrollView.documentView as? CopyableTranscriptSTTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.backgroundColor = .clear
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.showsLineNumbers = showsLineNumbers
        textView.highlightSelectedLine = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.textContainer.lineFragmentPadding = 12
        textView.copyFullTranscriptAction = copyFullTranscriptAction

        applyStyle(to: textView)
        applyText(to: textView)
        context.coordinator.recordDisplayedTranscript(selectionResetID: selectionResetID, textSnapshot: textSnapshot)
        context.coordinator.resetSelection(in: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CopyableTranscriptSTTextView else {
            return
        }

        textView.backgroundColor = .clear
        textView.copyFullTranscriptAction = copyFullTranscriptAction
        textView.showsLineNumbers = showsLineNumbers
        applyScrollInsets(to: scrollView)

        let textDidChange = !context.coordinator.isDisplaying(textSnapshot)
        let shouldResetSelection = context.coordinator.shouldResetSelection(
            selectionResetID: selectionResetID,
            textSnapshot: textSnapshot
        )

        if textDidChange {
            applyText(to: textView)
        } else {
            applyStyle(to: textView)
        }

        if shouldResetSelection || textDidChange {
            context.coordinator.resetSelection(in: textView)
            context.coordinator.recordDisplayedTranscript(selectionResetID: selectionResetID, textSnapshot: textSnapshot)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.frame.width,
            height: proposal.height ?? nsView.frame.height
        )
    }

    private func applyScrollInsets(to scrollView: NSScrollView) {
        let insets = NSEdgeInsets(top: 0, left: 0, bottom: bottomContentInset, right: 0)
        scrollView.contentInsets = insets
        scrollView.scrollerInsets = insets
    }

    private func applyStyle(to textView: STTextView) {
        if !textView.textColor.isEqual(foregroundColor) {
            textView.textColor = foregroundColor
        }
        if !textView.font.isEqual(Self.editorFont) {
            textView.font = Self.editorFont
        }
    }

    private func applyText(to textView: STTextView) {
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: Self.editorFont,
                .foregroundColor: foregroundColor
            ]
        )
        textView.attributedText = attributedText
        textView.needsLayout = true
        textView.needsDisplay = true
        textView.enclosingScrollView?.contentView.needsDisplay = true
        textView.enclosingScrollView?.needsDisplay = true
    }

    private static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    @MainActor
    final class Coordinator {
        private var displayedSelectionResetID: UUID?
        private(set) var displayedTextRevision: Int?
        private var displayedTextFingerprint: Int?

        func recordDisplayedTranscript(selectionResetID: UUID, textSnapshot: TranscriptTextSnapshot) {
            displayedSelectionResetID = selectionResetID
            displayedTextRevision = textSnapshot.revision
            displayedTextFingerprint = textSnapshot.fingerprint
        }

        func isDisplaying(_ textSnapshot: TranscriptTextSnapshot) -> Bool {
            displayedTextRevision == textSnapshot.revision && displayedTextFingerprint == textSnapshot.fingerprint
        }

        func shouldResetSelection(selectionResetID: UUID, textSnapshot: TranscriptTextSnapshot) -> Bool {
            guard let displayedSelectionResetID, let displayedTextRevision else {
                return true
            }

            if displayedSelectionResetID != selectionResetID || displayedTextRevision != textSnapshot.revision || displayedTextFingerprint != textSnapshot.fingerprint {
                return true
            }

            return false
        }

        func resetSelection(in textView: STTextView) {
            textView.textSelection = NSRange(location: 0, length: 0)
        }
    }
}

private final class CopyableTranscriptSTTextView: STTextView {
    var copyFullTranscriptAction: (() -> Void)?

    override func copy(_ sender: Any?) {
        if textSelection.length > 0 {
            super.copy(sender)
            return
        }

        copyFullTranscriptAction?()
    }
}

private struct TranscriptCopyShortcutMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let copyFullTranscriptAction: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.copyFullTranscriptAction = copyFullTranscriptAction
        context.coordinator.attach(to: view)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isEnabled: isEnabled,
            copyFullTranscriptAction: copyFullTranscriptAction
        )
    }

    final class Coordinator {
        private static let copyKeyCode: UInt16 = 8

        var isEnabled: Bool
        var copyFullTranscriptAction: () -> Void
        private weak var view: NSView?
        private var monitor: Any?

        init(isEnabled: Bool, copyFullTranscriptAction: @escaping () -> Void) {
            self.isEnabled = isEnabled
            self.copyFullTranscriptAction = copyFullTranscriptAction
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
                isEnabled,
                Self.isCopyShortcut(event),
                let window = view?.window,
                window.isKeyWindow
            else {
                return event
            }

            if let eventWindow = event.window, eventWindow !== window {
                return event
            }

            guard !Self.firstResponderHandlesOwnCopy(window.firstResponder) else {
                return event
            }

            copyFullTranscriptAction()
            return nil
        }

        private static func isCopyShortcut(_ event: NSEvent) -> Bool {
            guard event.keyCode == Self.copyKeyCode else {
                return false
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let disallowedFlags: NSEvent.ModifierFlags = [.control, .option, .shift]
            return flags.contains(.command) && flags.isDisjoint(with: disallowedFlags)
        }

        private static func firstResponderHandlesOwnCopy(_ responder: NSResponder?) -> Bool {
            if let textView = responder as? STTextView {
                return textView.textSelection.length > 0
            }

            return responder is NSText || responder is NSTextField
        }
    }
}
