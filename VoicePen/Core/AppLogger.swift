import Foundation
import OSLog

enum AppLogger {
    nonisolated private static let logger = Logger(
        subsystem: "com.khokhlachev.VoicePen",
        category: "VoicePen"
    )

    nonisolated static func info(_ message: String) {
        logger.info("\(sanitizedForLogging(message), privacy: .public)")
    }

    nonisolated static func debug(_ message: String) {
        logger.debug("\(sanitizedForLogging(message), privacy: .public)")
    }

    nonisolated static func error(_ message: String) {
        logger.error("\(sanitizedForLogging(message), privacy: .public)")
    }

    nonisolated static func sanitizedForLogging(_ message: String, secrets: [String] = []) -> String {
        var sanitized = message

        for secret in secrets {
            let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sanitized = sanitized.replacingOccurrences(of: trimmed, with: "[REDACTED]")
        }

        sanitized = replacingMatches(
            in: sanitized,
            pattern: #"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+"#,
            template: "$1[REDACTED]"
        )
        sanitized = replacingMatches(
            in: sanitized,
            pattern: #"(?i)(api[_-]?key\s*[:=]\s*)[^\s,;]+"#,
            template: "$1[REDACTED]"
        )
        sanitized = replacingMatches(
            in: sanitized,
            pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#,
            template: "Bearer [REDACTED]"
        )

        return sanitized
    }

    nonisolated private static func replacingMatches(
        in message: String,
        pattern: String,
        template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return message
        }

        let range = NSRange(message.startIndex..<message.endIndex, in: message)
        return regex.stringByReplacingMatches(
            in: message,
            range: range,
            withTemplate: template
        )
    }
}
