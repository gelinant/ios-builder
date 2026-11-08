import AVFoundation
import Foundation
import OSLog
import VelaCore

/// The dictation audio session. It is driven by the pure `VoiceAudioMachine` from `:ios-shared`:
/// the same start, duck, hold and restore timeline the Linux tests cover, so the Swift side only
/// executes the steps.
///
/// Recording needs `.playAndRecord`; guidance uses `.playback` with ducking. This captures the
/// session before changing it, ducks the other apps, stops the guidance line in flight instead of
/// mixing with it, and restores exactly what was there when the mic closes. A prompt that fires
/// during the capture is held by `VelaNavVoice` and spoken afterwards.
final class DictationAudio {
    static let shared = DictationAudio()

    private let session = AVAudioSession.sharedInstance()
    private let machine = VoiceAudioMachine()
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "VoiceSearch")
    private var savedCategory: AVAudioSession.Category?
    private var savedMode: AVAudioSession.Mode?
    private var savedOptions: AVAudioSession.CategoryOptions = []
    private var armed = false

    private init() {}

    private(set) var lastOutcome = "idle"

    /// Starts recording: guidance in flight is stopped, then the session ducks for the capture.
    @discardableResult
    func begin() -> Bool {
        guard !armed else { return true }
        savedCategory = session.category
        savedMode = session.mode
        savedOptions = session.categoryOptions
        // Always stop a prompt rather than talk over the microphone. A silent stop is harmless.
        _ = machine.started(navSpeaking: true)
        VelaNavVoice.shared.stop()
        do {
            try session.setCategory(
                .playAndRecord, mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            log.error("dictation session could not start: \(error.localizedDescription, privacy: .public)")
            machine.ended()
            restoreCategory()
            lastOutcome = "audio-failed"
            return false
        }
        armed = true
        lastOutcome = "listening"
        VelaNavVoice.shared.holdGuidance = { [weak self] text in
            guard let self else { return false }
            return !(self.machine.guidanceRequested(text: text).isEmpty)
        }
        return true
    }

    /// Restores the session and releases the guidance line that waited for the mic to close.
    func end() {
        let held = machine.deferredGuidance
        let steps = machine.ended()
        VelaNavVoice.shared.holdGuidance = nil
        guard armed else { return }
        armed = false
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            log.error("dictation session could not deactivate: \(error.localizedDescription, privacy: .public)")
        }
        restoreCategory()
        lastOutcome = steps.isEmpty ? "idle" : "restored"
        if let held {
            VelaNavVoice.shared.speakHeld(held)
        }
    }

    private func restoreCategory() {
        defer {
            savedCategory = nil
            savedMode = nil
            savedOptions = []
        }
        guard let savedCategory, let savedMode else { return }
        do {
            try session.setCategory(savedCategory, mode: savedMode, options: savedOptions)
        } catch {
            log.error("dictation session could not restore: \(error.localizedDescription, privacy: .public)")
        }
    }
}
