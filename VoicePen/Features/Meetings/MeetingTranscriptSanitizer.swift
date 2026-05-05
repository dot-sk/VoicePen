import Foundation

nonisolated enum MeetingTranscriptSanitizer {
    private static let subtitleCreditPattern =
        #"^(?:(?:субтитры\s+(?:сделал|создал|подготовил|добавил)|добавил\s+субтитры)"#
        + #"(?:\s+[\p{L}\p{N}_@.-]+){0,4}\s*)+[.!?…]*$"#

    private static let outroPattern = #"^продолжение\s+следует[.!?…]*$"#

    static func sanitize(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty && !isKnownArtifactLine($0) }
            .joined(separator: "\n")
    }

    private static func isKnownArtifactLine(_ line: String) -> Bool {
        isSubtitleCreditLine(line) || isOutroLine(line)
    }

    private static func isSubtitleCreditLine(_ line: String) -> Bool {
        line.range(of: subtitleCreditPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isOutroLine(_ line: String) -> Bool {
        line.range(of: outroPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
