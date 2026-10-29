import Foundation
import VelaCore

/// One spoken query as the map sees it, copied out of the Kotlin `VoiceRequest` so the rest of the
/// app (and the unit tests) never name a Kotlin type.
struct VoicePlan: Equatable {
    /// One of `search`, `navigate`, `home`, `work`, `route`, `eta` (the `VoiceAction` ids).
    let action: String
    let display: String
    let query: String
    let from: String?
    let to: String?
}

/// The Swift face of `VoicePlanner` (`:ios-shared`), which itself wraps the shared `QueryIntents`
/// parser. Keeping the Kotlin call here means the voice-search tests do not have to link VelaCore.
enum VoiceIntentPlanner {
    static func plan(heard: String, language: String) -> VoicePlan? {
        guard let request = VoicePlanner.shared.plan(heard: heard, lang: language) else {
            return nil
        }
        return VoicePlan(
            action: request.action,
            display: request.display,
            query: request.query,
            from: request.from,
            to: request.to)
    }
}
