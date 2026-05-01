import Foundation
import OSLog

enum AppLogger {
    nonisolated private static let logger = Logger(
        subsystem: "com.khokhlachev.VoicePen",
        category: "VoicePen"
    )

    nonisolated static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    nonisolated static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
