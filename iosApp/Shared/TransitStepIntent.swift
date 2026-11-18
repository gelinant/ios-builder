import AppIntents
import Foundation

/// The two manual step commands shared by the GO screen and the transit Live Activity.
enum TransitStepCommand: String {
    case previous
    case next
}

/// Previous and Next on the transit Live Activity. This file is compiled into the app and into
/// NavActivityExtension: the widget needs the type for `Button(intent:)`, and iOS runs a
/// LiveActivityIntent's `perform()` in the app process, launching it in the background when it is
/// not running. Only the app sets `TransitStepRouter.handler`; in the extension it stays nil.
struct TransitStepIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Change transit step" }
    static var description: IntentDescription { IntentDescription("Goes to the previous or next transit step.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Step")
    var command: String

    /// The session the activity shows. A button left on an older activity cannot move a newer trip.
    @Parameter(title: "Session")
    var sessionId: Int

    init() {}

    init(_ command: TransitStepCommand, sessionId: Int64) {
        self.command = command.rawValue
        self.sessionId = Int(sessionId)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let step = TransitStepCommand(rawValue: command) {
            TransitStepRouter.handler?(step, Int64(sessionId))
        }
        return .result()
    }
}

enum TransitStepRouter {
    /// Set once by the app at launch, before any intent can run.
    @MainActor static var handler: ((TransitStepCommand, Int64) -> Void)?
}
