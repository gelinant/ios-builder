import UIKit
import VelaCore

/// Plays the two get-off cues of the GO screen. The voice seam is NAV-LIFE's, read at the moment
/// of the cue from the shared `NavStore`: On speaks one line, Alerts only keeps the haptic and
/// drops the sentence, Off is silent including the haptic. Each cue is one pattern, never a loop.
enum TransitGoCuePlayer {
    static func play(kind: String, text: String) {
        guard kind == "two_before" || kind == "stop" else { return }
        let voice = AppGraph.session.nav.state.value
        let off = voice.voiceMuted && !voice.voiceAlertsOnly
        if off { return }
        haptic(kind)
        if voice.voiceMuted { return }
        VelaNavVoice.shared.speak(text: text, interrupt: false, ignoreMute: false)
    }

    /// Two-before is two light pulses; at the stop one success notification. Both are one pattern,
    /// distinct enough to feel without looking at the phone.
    private static func haptic(_ kind: String) {
        DispatchQueue.main.async {
            if kind == "stop" {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return
            }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
        }
    }
}
