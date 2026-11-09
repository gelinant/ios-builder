import Foundation
import OSLog
import VelaCore

/// The `Log` seam over the unified log: subsystem `app.vela.ios`, one category per tag. Debug
/// lines are written in Debug builds only. Lines are public: the shared code never logs a
/// coordinate, typed text or a place name (SPEC "Platform seams").
final class OSLogLog: NSObject, VelaCore.Log {
    static let subsystem = "app.vela.ios"

    private let lock = NSLock()
    private var loggers: [String: Logger] = [:]

    func isLoggable(tag: String, level: LogLevel) -> Bool {
        #if DEBUG
        return true
        #else
        return level != .debug
        #endif
    }

    func log(level: LogLevel, tag: String, message: String, error: KotlinThrowable?) {
        guard isLoggable(tag: tag, level: level) else { return }
        let out = self.logger(for: tag)
        let text = error.map { "\(message): \(String(describing: $0))" } ?? message
        if level == .error {
            out.error("\(text, privacy: .public)")
        } else if level == .warn {
            out.warning("\(text, privacy: .public)")
        } else if level == .info {
            out.info("\(text, privacy: .public)")
        } else {
            out.debug("\(text, privacy: .public)")
        }
    }

    private func logger(for tag: String) -> Logger {
        lock.lock()
        defer { lock.unlock() }
        if let logger = loggers[tag] { return logger }
        let logger = Logger(subsystem: Self.subsystem, category: tag)
        loggers[tag] = logger
        return logger
    }
}
