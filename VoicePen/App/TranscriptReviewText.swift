import AppKit

@MainActor
enum TranscriptReviewText {
    static let explanation = "Highlighted words may need review. Unhighlighted words can still contain mistakes."

    static func attributedText(_ text: String, hints: [WordConfidence], font: NSFont, foregroundColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: foregroundColor])
        let count = result.length
        for hint in hints {
            guard hint.location >= 0, hint.length > 0, hint.location <= count, hint.length <= count - hint.location,
                (text as NSString).substring(with: hint.range) == hint.text,
                hint.needsReview
            else { continue }
            result.addAttributes(
                [
                    .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.22),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.systemOrange,
                    .toolTip: "Review this word"
                ], range: hint.range)
        }
        return result
    }

    static func selectedPlainText(_ text: String, range: NSRange) -> String? {
        let count = text.utf16.count
        guard range.location >= 0, range.length > 0, range.location <= count, range.length <= count - range.location,
            Range(range, in: text) != nil
        else { return nil }
        return (text as NSString).substring(with: range)
    }
}
