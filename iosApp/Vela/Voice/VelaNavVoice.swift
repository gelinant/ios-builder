import AVFoundation
import Foundation
import OSLog
import VelaCore

/// Chooses the spoken-guidance engine per prompt: the downloaded Piper voice when a complete model
/// of the guidance language is installed, otherwise Apple's AVSpeechSynthesizer. A model that fails
/// to load falls back to Apple for that line instead of leaving guidance silent.
final class VelaNavVoice: NSObject, VelaCore.NavVoice {
    static let shared = VelaNavVoice()

    private let apple = AppleNavVoice()
    private let neural = SherpaTts()
    private let library = VoiceLibrary.shared
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "NeuralVoice")
    private var spokenCount = 0
    /// A model that failed to load stays out of the speaking path until the app restarts, rather
    /// than retrying a 60 MB load on every prompt.
    private var failedVoiceId: String?
    private(set) var lastEngine = "system"

    var isMuted = false
    var onSpeech: ((Int, String) -> Void)?
    /// Set while the voice-search microphone is open: returns true when a prompt was held back so
    /// it is not spoken into the microphone, and speaks it again after the capture (VO-2).
    var holdGuidance: ((String) -> Bool)?

    override init() {
        super.init()
        library.prepareForLaunch()
        library.beforeRemoving = { [weak self] id in self?.forgetVoice(id) }
        apple.onSpeech = { [weak self] _, text in
            self?.report(text)
        }
    }

    /// The debug line read by VoiceUITests and NavModel: the engine of the last prompt plus the
    /// selection the next prompt will use.
    var engineDebug: String {
        "last=\(lastEngine) next=\(library.engineDebug)"
    }

    func doInit(enginePackage: String?) {
        library.prepareForLaunch()
        apple.doInit(enginePackage: enginePackage)
    }

    /// A removed or replaced model must be retried after a reinstall.
    func forgetVoice(_ id: String) {
        if failedVoiceId == id { failedVoiceId = nil }
        neural.unload(id)
    }

    func speak(text: String, interrupt: Bool, ignoreMute: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !text.isEmpty else { return }
            if self.isMuted && !ignoreMute { return }
            self.speakOnMain(text, interrupt: interrupt)
        }
    }

    func prepare(text: String, onDone: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            if let files = self?.library.currentVoiceFiles() {
                self?.neural.warmUp(files)
            }
            onDone()
        }
    }

    func speakOpener(text: String) {
        speak(text: text, interrupt: false, ignoreMute: false)
    }

    func setMuted(_ on: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isMuted = on
            self.apple.setMuted(on)
            if on { self.neural.stop() }
        }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.neural.stop()
            self?.apple.stop()
        }
    }

    /// After a call, Bluetooth route change or resume, re-arm the session for the next prompt.
    func rearm() {
        DispatchQueue.main.async { [weak self] in
            self?.apple.rearm()
        }
    }

    func reroutingChime() { apple.reroutingChime() }
    func fasterRouteChime() { apple.fasterRouteChime() }

    /// A guidance line held during dictation, spoken once the microphone is closed.
    func speakHeld(_ text: String) {
        speak(text: text, interrupt: false, ignoreMute: false)
    }

    /// Test hook: speak a sample now, even without navigation.
    func speakSample(_ text: String) {
        speak(text: text, interrupt: true, ignoreMute: false)
    }

    private func speakOnMain(_ text: String, interrupt: Bool) {
        if let hold = holdGuidance, hold(text) { return }
        // The shared lexicon and its number, unit and clock rules. The banner keeps the compact
        // form ("Main St"); only the spoken line is expanded. One table serves both platforms.
        let spoken = SpeechText.shared.forSpeech(text: text, language: library.guidanceLanguage)
        if let files = library.currentVoiceFiles(), files.id != failedVoiceId {
            lastEngine = "neural"
            neural.speak(
                spoken, files: files, interrupt: interrupt,
                onStart: { [weak self] in self?.report(spoken) },
                onDone: {},
                onFailure: { [weak self] in
                    guard let self else { return }
                    self.failedVoiceId = files.id
                    self.speakSystem(spoken, interrupt: interrupt)
                })
        } else {
            speakSystem(spoken, interrupt: interrupt)
        }
    }

    private func speakSystem(_ text: String, interrupt: Bool) {
        lastEngine = "system"
        apple.speak(text: text, interrupt: interrupt, ignoreMute: true)
    }

    private func report(_ text: String) {
        spokenCount += 1
        #if DEBUG
        log.debug("spoken: \(text, privacy: .public)")
        #endif
        onSpeech?(spokenCount, text)
    }
}
