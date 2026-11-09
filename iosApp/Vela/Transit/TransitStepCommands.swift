import ActivityKit
import Foundation
import VelaCore

/// Routes a manual Previous or Next to the one process-owned TransitSession. An open GO screen
/// takes the same command first, so its machine moves with the session. The session state then
/// reaches the Live Activity through TransitModel, like any other step change.
enum TransitStepCommands {
    /// The open GO screen's model, if any. The screen owns it.
    @MainActor static weak var go: TransitGoModel?

    @MainActor static func install() {
        TransitStepRouter.handler = { command, sessionId in
            run(command, sessionId: sessionId)
        }
    }

    /// The Live Activity path. False when no running session matches [sessionId]: after a forced
    /// quit the process starts without a session, so the tapped activity can never be updated
    /// again and is ended instead.
    @MainActor @discardableResult
    static func run(
        _ command: TransitStepCommand,
        sessionId: Int64,
        session: TransitSession = AppGraph.session.transit
    ) -> Bool {
        let state = session.state.value
        guard state.active, Int64(state.sessionId) == sessionId else {
            endActivities(of: sessionId)
            return false
        }
        go?.applyLocally(command)
        return apply(command, to: session)
    }

    @discardableResult
    static func apply(_ command: TransitStepCommand, to session: TransitSession) -> Bool {
        switch command {
        case .previous: return session.previousStep()
        case .next: return session.nextStep()
        }
    }

    private static func endActivities(of sessionId: Int64) {
        let orphans = Activity<TransitActivityAttributes>.activities.filter {
            $0.content.state.sessionId == sessionId
        }
        guard !orphans.isEmpty else { return }
        Task {
            for activity in orphans {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
