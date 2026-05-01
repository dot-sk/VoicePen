import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(subsystem: "com.khokhlachev.VoicePen", category: "VoicePen")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
