import Foundation

extension TranscriptConfidence {
    @MainActor static func storedPayload(text: String, hints: [WordConfidence]) throws -> Data? {
        let valid = TranscriptConfidence(text: text, words: hints).reviewHints(in: text)
        guard !valid.isEmpty else { return nil }
        let json = try JSONEncoder().encode(TranscriptConfidence(text: text, words: valid))
        return try VoiceHistoryTextCompressor.compress(String(decoding: json, as: UTF8.self))
    }

    @MainActor static func storedHints(_ data: Data?, text: String) -> [WordConfidence] {
        guard let data, let json = try? VoiceHistoryTextCompressor.decompress(data),
            let payload = try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
        else { return [] }
        return payload.reviewHints(in: text)
    }

}
