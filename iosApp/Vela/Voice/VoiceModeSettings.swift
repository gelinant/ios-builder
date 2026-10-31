import Foundation
import VelaCore

/// The three states Android's speaker button cycles: On, Alerts only, Off. The settings row and the
/// in-drive button both call `NavStore`, which owns and persists `spoken_directions` and
/// `spoken_alerts_only`; this object only mirrors the shared state, never a second copy.
enum VoiceMode: String, CaseIterable, Identifiable {
    case on
    case alerts
    case off

    var id: String { rawValue }

    var muted: Bool { self != .on }
    var alertsOnly: Bool { self == .alerts }

    var labelKey: String {
        switch self {
        case .on: return "settings_voice_mode_on"
        case .alerts: return "settings_voice_mode_alerts"
        case .off: return "settings_voice_mode_off"
        }
    }

    static func current(muted: Bool, alertsOnly: Bool) -> VoiceMode {
        if !muted { return .on }
        return alertsOnly ? .alerts : .off
    }
}

/// Observes the common `NavStore` so Settings and the navigation banner always show the same
/// mode. No key is written here: `setVoiceMode` writes the two Android keys on the shared store.
final class VoiceModeSettings: ObservableObject {
    static let shared = VoiceModeSettings()

    @Published private(set) var muted = false
    @Published private(set) var alertsOnly = false

    private var observing: Task<Void, Never>?
    private let store = AppGraph.session.nav

    init() {
        let state = store.state.value
        muted = state.voiceMuted
        alertsOnly = state.voiceAlertsOnly
        observing = Task { @MainActor [weak self] in
            for await state in store.state {
                guard let self else { return }
                if self.muted != state.voiceMuted { self.muted = state.voiceMuted }
                if self.alertsOnly != state.voiceAlertsOnly { self.alertsOnly = state.voiceAlertsOnly }
            }
        }
    }

    deinit { observing?.cancel() }

    var mode: VoiceMode {
        VoiceMode.current(muted: muted, alertsOnly: alertsOnly)
    }

    func setMode(_ mode: VoiceMode) {
        muted = mode.muted
        alertsOnly = mode.alertsOnly
        store.setVoiceMode(muted: mode.muted, alertsOnly: mode.alertsOnly)
    }

    /// Debug line for `SettingsVoiceUITests`: the same values the banner reads.
    var debugLine: String {
        let name = mode == .alerts ? "alerts" : (mode == .off ? "off" : "on")
        return "voicemode=\(name) spoken=\(muted ? 0 : 1) alertsOnly=\(alertsOnly ? 1 : 0)"
    }
}
