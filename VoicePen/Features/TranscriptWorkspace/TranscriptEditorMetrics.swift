import Foundation

nonisolated struct TranscriptEditorMetrics: Equatable, Sendable {
    let lineCount: Int
    let characterCount: Int

    init(text: String) {
        lineCount = Self.lineCount(in: text)
        characterCount = text.count
    }

    var statusText: String {
        "\(lineCount) \(lineLabel) · \(characterCount) \(characterLabel)"
    }

    private var lineLabel: String {
        lineCount == 1 ? "line" : "lines"
    }

    private var characterLabel: String {
        characterCount == 1 ? "char" : "chars"
    }

    private static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else {
            return 0
        }

        var count = 1
        var previousWasCarriageReturn = false

        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 10:
                if previousWasCarriageReturn {
                    previousWasCarriageReturn = false
                } else {
                    count += 1
                }
            case 13, 0x85, 0x2028, 0x2029:
                count += 1
                previousWasCarriageReturn = scalar.value == 13
            default:
                previousWasCarriageReturn = false
            }
        }

        return count
    }
}
