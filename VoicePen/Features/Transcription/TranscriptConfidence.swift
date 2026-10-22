import CryptoKit
import Foundation

nonisolated struct WordConfidence: Codable, Equatable, Sendable {
    let location: Int
    let length: Int
    let text: String
    let probability: Float
    let reviewThreshold: Float?

    init(location: Int, length: Int, text: String, probability: Float, reviewThreshold: Float? = nil) {
        self.location = location
        self.length = length
        self.text = text
        self.probability = probability
        self.reviewThreshold = reviewThreshold
    }

    var range: NSRange { NSRange(location: location, length: length) }

    var hasValidReviewPolicy: Bool {
        let threshold = reviewThreshold ?? TranscriptConfidence.reviewThreshold
        return threshold.isFinite && threshold > 0 && threshold <= 1
    }

    var needsReview: Bool {
        hasValidReviewPolicy && probability.isFinite && probability >= 0 && probability < (reviewThreshold ?? TranscriptConfidence.reviewThreshold)
    }
}

nonisolated struct RecognitionTokenConfidence: Sendable {
    let bytes: [UInt8]
    let probability: Float
    let isSpecial: Bool

    init(bytes: [UInt8], probability: Float, isSpecial: Bool = false) {
        self.bytes = bytes
        self.probability = probability
        self.isSpecial = isSpecial
    }
}

nonisolated struct TranscriptConfidence: Codable, Equatable, Sendable {
    static let reviewThreshold: Float = 0.3

    let version: Int
    let textDigest: String
    let words: [WordConfidence]

    init(text: String, words: [WordConfidence]) {
        version = 1
        textDigest = Self.digest(text)
        self.words = words
    }

    static func extract(text: String, tokens: [RecognitionTokenConfidence], reviewThreshold: Float? = nil) -> TranscriptConfidence? {
        let tokens = tokens.filter { !$0.isSpecial }
        let bytes = tokens.flatMap(\.bytes)
        guard bytes == Array(text.utf8), !tokens.isEmpty else { return nil }

        var byteToUTF16 = [0: 0]
        var byteOffset = 0
        var utf16Offset = 0
        for scalar in text.unicodeScalars {
            byteOffset += scalar.utf8.count
            utf16Offset += scalar.utf16.count
            byteToUTF16[byteOffset] = utf16Offset
        }
        let utf16ToByte = Dictionary(uniqueKeysWithValues: byteToUTF16.map { ($0.value, $0.key) })
        var tokenSpans: [(start: Int, end: Int, probability: Float)] = []
        byteOffset = 0
        for token in tokens {
            tokenSpans.append((byteOffset, byteOffset + token.bytes.count, token.probability))
            byteOffset += token.bytes.count
        }

        var tokenIndex = 0
        var words: [WordConfidence] = []
        for word in wordRanges(in: text) {
            guard let lower = utf16ToByte[word.range.location],
                let upper = utf16ToByte[NSMaxRange(word.range)]
            else { continue }
            while tokenIndex < tokenSpans.count, tokenSpans[tokenIndex].end <= lower { tokenIndex += 1 }
            var index = tokenIndex
            var probabilities: [Float] = []
            while index < tokenSpans.count, tokenSpans[index].start < upper {
                if tokenSpans[index].end > lower { probabilities.append(tokenSpans[index].probability) }
                index += 1
            }
            guard !probabilities.isEmpty, probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                let probability = probabilities.min()
            else { continue }
            words.append(WordConfidence(location: word.range.location, length: word.range.length, text: word.text, probability: probability, reviewThreshold: reviewThreshold))
        }
        return words.isEmpty ? nil : TranscriptConfidence(text: text, words: words)
    }

    func validatedWords(in text: String) -> [WordConfidence] {
        guard version == 1, textDigest == Self.digest(text) else { return [] }
        let ranges = Dictionary(uniqueKeysWithValues: Self.wordRanges(in: text).map { ($0.range.location, $0) })
        var end = 0
        return words.filter { word in
            guard word.location >= end, word.length > 0,
                word.probability.isFinite, (0...1).contains(word.probability),
                word.hasValidReviewPolicy,
                let expected = ranges[word.location], expected.range.length == word.length, expected.text == word.text
            else { return false }
            end = NSMaxRange(expected.range)
            return true
        }
    }

    func remapped(from source: String, to target: String) -> TranscriptConfidence? {
        let valid = validatedWords(in: source)
        guard !valid.isEmpty else { return nil }
        let sourceWords = Self.wordRanges(in: source)
        let targetWords = Self.wordRanges(in: target)
        let sourceKeys = sourceWords.map { Self.wordKey($0.text) }
        let targetKeys = targetWords.map { Self.wordKey($0.text) }
        let sourceGroups = Dictionary(grouping: sourceWords.indices, by: { sourceKeys[$0] })
        let targetGroups = Dictionary(grouping: targetWords.indices, by: { targetKeys[$0] })
        let confidenceByLocation = Dictionary(uniqueKeysWithValues: valid.map { ($0.location, $0) })
        let sameWords = sourceKeys == targetKeys
        var mapped: [WordConfidence] = []
        for index in targetWords.indices {
            let sourceIndex: Int?
            if sameWords {
                sourceIndex = index
            } else if sourceGroups[targetKeys[index]]?.count == 1, targetGroups[targetKeys[index]]?.count == 1 {
                sourceIndex = sourceGroups[targetKeys[index]]?.first
            } else {
                sourceIndex = nil
            }
            guard let sourceIndex, let confidence = confidenceByLocation[sourceWords[sourceIndex].range.location] else { continue }
            let word = targetWords[index]
            mapped.append(
                WordConfidence(
                    location: word.range.location, length: word.range.length, text: word.text, probability: confidence.probability,
                    reviewThreshold: confidence.reviewThreshold
                ))
        }
        return mapped.isEmpty ? nil : TranscriptConfidence(text: target, words: mapped)
    }

    func reviewHints(in text: String) -> [WordConfidence] {
        validatedWords(in: text).filter(\.needsReview)
    }

    private static func wordKey(_ text: String) -> String {
        text.replacingOccurrences(of: "ё", with: "е").replacingOccurrences(of: "Ё", with: "Е")
    }

    private static func wordRanges(in text: String) -> [(range: NSRange, text: String)] {
        guard let wordPattern else { return [] }
        return wordPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return (match.range, String(text[range]))
        }
    }

    private static let wordPattern = try? NSRegularExpression(pattern: #"[\p{L}\p{N}][\p{L}\p{M}\p{N}]*(?:['’_\-][\p{L}\p{N}][\p{L}\p{M}\p{N}]*)*"#)

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
