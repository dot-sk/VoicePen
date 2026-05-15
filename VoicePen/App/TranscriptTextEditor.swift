import AppKit
import SwiftUI

struct TranscriptTextEditor: View {
    let text: String
    let selectionResetID: UUID
    let copyAction: () -> Void
    var isSecondaryText = false
    var isCopyDisabled = false
    @State private var selectedCharacterCount = 0
    @State private var copyFeedbackTrigger = 0
    @State private var isCopyButtonHovered = false

    private var metrics: TranscriptEditorMetrics {
        TranscriptEditorMetrics(text: text)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ReadOnlyTranscriptTextView(
                text: text,
                selectionResetID: selectionResetID,
                foregroundColor: isSecondaryText ? .secondaryLabelColor : .labelColor,
                copyFullTranscriptAction: copyTranscriptWithFeedback,
                selectedCharacterCount: $selectedCharacterCount
            )

            Divider()

            HStack {
                Text(metrics.statusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer()

                Text(selectionStatusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.secondary.opacity(0.22), lineWidth: 1)
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
                    .fill(copyButtonHoverColor)
            }
            .onHover { isCopyButtonHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isCopyButtonHovered)

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
    }

    private var selectionStatusText: String {
        "Selected: \(selectedCharacterCount) \(selectedCharacterCount == 1 ? "char" : "chars")"
    }

    private var copyButtonHoverColor: Color {
        isCopyButtonHovered && !isCopyDisabled ? Color.primary.opacity(0.055) : Color.clear
    }

    private func copyTranscriptWithFeedback() {
        guard !isCopyDisabled else {
            return
        }

        copyAction()
        copyFeedbackTrigger += 1
    }
}

private struct ReadOnlyTranscriptTextView: NSViewRepresentable {
    let text: String
    let selectionResetID: UUID
    let foregroundColor: NSColor
    let copyFullTranscriptAction: () -> Void
    @Binding var selectedCharacterCount: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = CopyableTranscriptTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.copyFullTranscriptAction = copyFullTranscriptAction

        applyText(to: textView)
        context.coordinator.recordDisplayedTranscript(selectionResetID: selectionResetID, text: text)
        scrollView.documentView = textView
        context.coordinator.resetSelection(in: textView)

        let rulerView = TranscriptLineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = rulerView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textColor = foregroundColor
        textView.font = Self.editorFont
        textView.delegate = context.coordinator
        (textView as? CopyableTranscriptTextView)?.copyFullTranscriptAction = copyFullTranscriptAction

        let shouldResetSelection = context.coordinator.shouldResetSelection(
            selectionResetID: selectionResetID,
            text: text
        )
        let textDidChange = textView.string != text

        if textDidChange {
            applyText(to: textView)
        }

        if shouldResetSelection || textDidChange {
            context.coordinator.resetSelection(in: textView)
        }

        scrollView.verticalRulerView?.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedCharacterCount: $selectedCharacterCount)
    }

    private func applyText(to textView: NSTextView) {
        let attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: Self.editorFont,
                .foregroundColor: foregroundColor
            ]
        )
        textView.textStorage?.setAttributedString(attributedText)
        textView.typingAttributes = [
            .font: Self.editorFont,
            .foregroundColor: foregroundColor
        ]
        invalidateRenderedText(in: textView)
    }

    private func invalidateRenderedText(in textView: NSTextView) {
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }

        textView.needsDisplay = true
        textView.enclosingScrollView?.contentView.needsDisplay = true
        textView.enclosingScrollView?.needsDisplay = true
    }

    private static var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var selectedCharacterCount: Int
        private var displayedSelectionResetID: UUID?
        private var displayedText: String?

        init(selectedCharacterCount: Binding<Int>) {
            _selectedCharacterCount = selectedCharacterCount
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            updateSelectedCharacterCount(from: textView)
        }

        func recordDisplayedTranscript(selectionResetID: UUID, text: String) {
            displayedSelectionResetID = selectionResetID
            displayedText = text
        }

        func shouldResetSelection(selectionResetID: UUID, text: String) -> Bool {
            defer {
                recordDisplayedTranscript(selectionResetID: selectionResetID, text: text)
            }

            guard
                let displayedSelectionResetID,
                let displayedText
            else {
                return true
            }

            return displayedSelectionResetID != selectionResetID || displayedText != text
        }

        func resetSelection(in textView: NSTextView) {
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            selectedCharacterCount = 0
        }

        func updateSelectedCharacterCount(from textView: NSTextView) {
            let ranges = textView.selectedRanges.map(\.rangeValue)
            selectedCharacterCount = TranscriptEditorMetrics.selectedCharacterCount(
                in: textView.string,
                ranges: ranges
            )
        }
    }
}

private final class CopyableTranscriptTextView: NSTextView {
    var copyFullTranscriptAction: (() -> Void)?

    override func copy(_ sender: Any?) {
        if selectedRanges.contains(where: { $0.rangeValue.length > 0 }) {
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
            return flags.contains(.command) && flags.intersection(disallowedFlags).isEmpty
        }

        private static func firstResponderHandlesOwnCopy(_ responder: NSResponder?) -> Bool {
            responder is NSText || responder is NSTextField
        }
    }
}

private final class TranscriptLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private let textAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 29
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        drawSeparator()
        drawLineNumbers(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        drawLineNumbers(in: rect)
    }

    private func drawSeparator() {
        let inset: CGFloat = 8
        let startY = bounds.minY + inset
        let endY = bounds.maxY - inset
        guard endY > startY else {
            return
        }

        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.maxX - 0.5, y: startY))
        path.line(to: NSPoint(x: bounds.maxX - 0.5, y: endY))
        path.lineWidth = 1
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    private func drawLineNumbers(in rect: NSRect) {
        guard
            let textView,
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard glyphRange.length > 0 else {
            drawLineNumber(1, atY: textView.textContainerInset.height)
            return
        }

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveRange)
            let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            if isStartOfLogicalLine(characterIndex, in: textView.string as NSString) {
                let lineNumber = lineNumber(forCharacterIndex: characterIndex, in: textView.string as NSString)
                let textPoint = NSPoint(
                    x: 0,
                    y: lineRect.minY + textView.textContainerOrigin.y
                )
                let rulerPoint = convert(textPoint, from: textView)
                drawLineNumber(lineNumber, atY: rulerPoint.y)
            }

            let nextGlyphIndex = NSMaxRange(effectiveRange)
            glyphIndex = nextGlyphIndex > glyphIndex ? nextGlyphIndex : glyphIndex + 1
        }
    }

    private func drawLineNumber(_ lineNumber: Int, atY y: CGFloat) {
        let lineNumberText = "\(lineNumber)" as NSString
        let size = lineNumberText.size(withAttributes: textAttributes)
        let x = max(4, ruleThickness - size.width - 8)
        lineNumberText.draw(at: NSPoint(x: x, y: y), withAttributes: textAttributes)
    }

    private func isStartOfLogicalLine(_ characterIndex: Int, in text: NSString) -> Bool {
        characterIndex == text.lineRange(for: NSRange(location: characterIndex, length: 0)).location
    }

    private func lineNumber(forCharacterIndex characterIndex: Int, in text: NSString) -> Int {
        guard characterIndex > 0 else {
            return 1
        }

        var lineNumber = 1
        for index in 0..<min(characterIndex, text.length) where text.character(at: index) == 10 {
            lineNumber += 1
        }
        return lineNumber
    }
}
