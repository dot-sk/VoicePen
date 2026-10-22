import Foundation

nonisolated struct GigaAMAlignedToken: Sendable {
    let text: String
    let startMilliseconds: Int64
    let endMilliseconds: Int64
    let probability: Float?

    init(text: String, startMilliseconds: Int64, endMilliseconds: Int64, probability: Float? = nil) {
        self.text = text
        self.startMilliseconds = startMilliseconds
        self.endMilliseconds = endMilliseconds
        self.probability = probability
    }
}

nonisolated enum GigaAMConfidence {
    static let reviewThreshold: Float = 0.6

    static func extract(text: String, tokens: [GigaAMAlignedToken]) -> TranscriptConfidence? {
        let pieces = tokens.map { $0.text.replacingOccurrences(of: "▁", with: " ") }
        let reconstructed = pieces.joined()
        guard !tokens.isEmpty, reconstructed.trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let evidence = zip(tokens, pieces).map { token, piece in
            RecognitionTokenConfidence(bytes: Array(piece.utf8), probability: token.probability ?? .nan)
        }
        return TranscriptConfidence.extract(text: reconstructed, tokens: evidence, reviewThreshold: reviewThreshold)?
            .remapped(from: reconstructed, to: text)
    }
}
