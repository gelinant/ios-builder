import Foundation

/// What a system event may change while guidance is live. None of these actions ends the drive:
/// a background transition, the screen locking, a phone call and a Bluetooth route change all keep
/// the session, its route and the one Live Activity. Only End or arrival finish a drive.
enum NavLifecyclePolicy {
    enum Event {
        case background
        case foreground
        case audioInterruptionBegan
        case audioInterruptionEnded
        case audioRouteChanged
    }

    enum Action: Equatable {
        case none
        /// Cut the prompt in flight, as a call or a pause must.
        case cutSpeech
        /// The system may have deactivated the audio session; the next prompt re-arms it.
        case rearmAudio
        /// Guidance is live again and the camera was following before: re-attach it.
        case followCamera
    }

    static func action(
        _ event: Event, navigating: Bool, paused: Bool, cameraDetached: Bool
    ) -> Action {
        guard navigating else { return .none }
        switch event {
        case .background:
            return .none
        case .foreground:
            return paused || cameraDetached ? .none : .followCamera
        case .audioInterruptionBegan:
            return .cutSpeech
        case .audioInterruptionEnded:
            return .rearmAudio
        case .audioRouteChanged:
            return .rearmAudio
        }
    }
}

#if DEBUG
/// Launch-argument switches used only by the UI scenarios.
enum NavTestSupport {
    static var robustness: Bool { UserDefaults.standard.bool(forKey: "VelaNavRobustnessTest") }
}
#endif
