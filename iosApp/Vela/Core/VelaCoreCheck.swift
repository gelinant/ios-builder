import Foundation
import OSLog
import VelaCore

/// The app's one call into the Kotlin framework VelaCore for now. It proves the framework links
/// and runs, in the simulator and in a device archive; the logged line is what CI reads back.
/// The tests go through it too, so the test bundle never references a Kotlin symbol directly.
enum VelaCoreCheck {
    static let logger = Logger(subsystem: "app.vela.ios", category: "VelaCore")

    static var version: String { IosGraph.shared.frameworkVersion }

    static func shortRoadName(_ name: String) -> String {
        IosGraph.shared.shortRoadName(name: name)
    }

    /// Runs the Kotlin suspend function `IosGraph.selfCheck()` (async through SKIE) and logs the
    /// line it returns.
    static func run() async -> String {
        do {
            let line = try await IosGraph.shared.selfCheck()
            logger.notice("Kotlin call ok: \(line, privacy: .public)")
            return line
        } catch {
            logger.error("Kotlin call failed: \(String(describing: error), privacy: .public)")
            return "VelaCore \(version): error"
        }
    }
}
