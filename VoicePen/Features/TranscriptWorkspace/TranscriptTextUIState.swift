import Foundation

nonisolated struct TranscriptTextSnapshot: Equatable, Sendable {
    let revision: Int
    let fingerprint: Int
    let metrics: TranscriptEditorMetrics
}

nonisolated struct TranscriptTextUIState: Equatable, Sendable {
    let revision: Int
    let fingerprint: Int
    let metrics: TranscriptEditorMetrics
    let containsTimecode: Bool

    static let empty = TranscriptTextUIState.make(text: "")

    var snapshot: TranscriptTextSnapshot {
        TranscriptTextSnapshot(revision: revision, fingerprint: fingerprint, metrics: metrics)
    }

    static func make(text: String, previous: TranscriptTextUIState? = nil) -> TranscriptTextUIState {
        let fingerprint = fingerprint(for: text)
        let revision: Int
        if previous?.fingerprint == fingerprint {
            revision = previous?.revision ?? 1
        } else {
            revision = (previous?.revision ?? 0) + 1
        }

        return TranscriptTextUIState(
            revision: revision,
            fingerprint: fingerprint,
            metrics: TranscriptEditorMetrics(text: text),
            containsTimecode: containsTimecode(in: text)
        )
    }

    private static func fingerprint(for text: String) -> Int {
        var hasher = Hasher()
        hasher.combine(text)
        return hasher.finalize()
    }

    private static func containsTimecode(in text: String) -> Bool {
        var lineStart = text.startIndex

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(where: \.isNewline) ?? text.endIndex
            let line = text[lineStart..<lineEnd]

            if line.first == "[",
                line.range(of: " - ") != nil,
                line.firstIndex(of: "]") != nil
            {
                return true
            }

            guard lineEnd < text.endIndex else {
                break
            }
            lineStart = text.index(after: lineEnd)
        }

        return false
    }
}
