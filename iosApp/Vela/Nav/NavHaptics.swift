import Foundation
import UIKit
import VelaCore

/// Direction-coded turn feedback. As on Android, cues default off for driving and on for walking,
/// cycling and transit. The iOS settings screen can add the per-mode switches later.
final class AppleNavHaptics: NSObject, VelaCore.NavHaptics {
    func cue(type: ManeuverType, approaching: Bool, mode: TravelMode) {
        guard mode.name != "DRIVE" else { return }
        DispatchQueue.main.async {
            if approaching {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            let name = type.name
            if self.leftTypes.contains(name) {
                self.pulses(count: 2, style: .heavy)
            } else if self.rightTypes.contains(name) {
                self.pulses(count: 3, style: .medium)
            } else {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }

    func reroute(mode: TravelMode) {
        guard mode.name != "DRIVE" else { return }
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func pulses(count: Int, style: UIImpactFeedbackGenerator.FeedbackStyle) {
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18) {
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            }
        }
    }

    private let leftTypes: Set<String> = [
        "TURN_LEFT", "SLIGHT_LEFT", "SHARP_LEFT", "FORK_LEFT", "RAMP_LEFT", "KEEP_LEFT", "UTURN",
    ]
    private let rightTypes: Set<String> = [
        "TURN_RIGHT", "SLIGHT_RIGHT", "SHARP_RIGHT", "FORK_RIGHT", "RAMP_RIGHT", "KEEP_RIGHT",
    ]
}
