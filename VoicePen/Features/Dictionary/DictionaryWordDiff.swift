import Foundation

nonisolated enum DictionaryWordDiffChange: String, Equatable, Sendable {
    case unchanged
    case removed
    case inserted
}

nonisolated struct DictionaryWordDiffToken: Equatable, Sendable {
    var text: String
    var change: DictionaryWordDiffChange
}

nonisolated enum DictionaryWordDiff {
    static func compare(from currentText: String, to simulatedText: String) -> [DictionaryWordDiffToken] {
        let currentTokens = tokens(in: currentText)
        let simulatedTokens = tokens(in: simulatedText)
        guard !currentTokens.isEmpty || !simulatedTokens.isEmpty else { return [] }

        let table = longestCommonSubsequenceTable(
            currentTokens: currentTokens,
            simulatedTokens: simulatedTokens
        )

        var index = currentTokens.count
        var simulatedIndex = simulatedTokens.count
        var diff: [DictionaryWordDiffToken] = []

        while index > 0 || simulatedIndex > 0 {
            if index > 0,
               simulatedIndex > 0,
               currentTokens[index - 1] == simulatedTokens[simulatedIndex - 1] {
                diff.append(DictionaryWordDiffToken(text: currentTokens[index - 1], change: .unchanged))
                index -= 1
                simulatedIndex -= 1
            } else if simulatedIndex > 0,
                      (index == 0 || table[index][simulatedIndex - 1] >= table[index - 1][simulatedIndex]) {
                diff.append(DictionaryWordDiffToken(text: simulatedTokens[simulatedIndex - 1], change: .inserted))
                simulatedIndex -= 1
            } else if index > 0 {
                diff.append(DictionaryWordDiffToken(text: currentTokens[index - 1], change: .removed))
                index -= 1
            }
        }

        return diff.reversed()
    }

    private static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func longestCommonSubsequenceTable(
        currentTokens: [String],
        simulatedTokens: [String]
    ) -> [[Int]] {
        var table = Array(
            repeating: Array(repeating: 0, count: simulatedTokens.count + 1),
            count: currentTokens.count + 1
        )

        guard !currentTokens.isEmpty, !simulatedTokens.isEmpty else {
            return table
        }

        for currentIndex in 1...currentTokens.count {
            for simulatedIndex in 1...simulatedTokens.count {
                if currentTokens[currentIndex - 1] == simulatedTokens[simulatedIndex - 1] {
                    table[currentIndex][simulatedIndex] = table[currentIndex - 1][simulatedIndex - 1] + 1
                } else {
                    table[currentIndex][simulatedIndex] = max(
                        table[currentIndex - 1][simulatedIndex],
                        table[currentIndex][simulatedIndex - 1]
                    )
                }
            }
        }

        return table
    }
}
