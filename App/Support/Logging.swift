import Foundation
import OSLog

enum FFLog {
    private static let logger = Logger(subsystem: "com.fitfluence.ios", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
