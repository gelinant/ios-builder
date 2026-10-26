import AVFoundation
import AudioToolbox
import Foundation
import OSLog
import UIKit
import VelaCore

/// Apple spoken guidance behind the common `NavVoice` seam. Kotlin may call from any thread; the
/// synthesizer, audio session and delegate all stay on the main queue.
final class AppleNavVoice: NSObject, VelaCore.NavVoice, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let audio = AVAudioSession.sharedInstance()
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "NavVoice")
    private var audioArmed = false
    private var oldCategory: AVAudioSession.Category?
    private var oldMode: AVAudioSession.Mode?
    private var oldOptions: AVAudioSession.CategoryOptions = []
    private var spokenCount = 0

    var isMuted = false
    var onSpeech: ((Int, String) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func doInit(enginePackage: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.armAudio()
        }
    }

    func speak(text: String, interrupt: Bool, ignoreMute: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !text.isEmpty else { return }
            if self.isMuted && !ignoreMute { return }
            if interrupt { self.synthesizer.stopSpeaking(at: .immediate) }
            self.speakNow(text)
        }
    }

    func prepare(text: String, onDone: @escaping () -> Void) {
        // AVSpeechSynthesizer has no public offline render-ahead API. Building the utterance is
        // cheap; speech starts on the same main queue as the request.
        DispatchQueue.main.async {
            _ = text
            onDone()
        }
    }

    func speakOpener(text: String) {
        speak(text: text, interrupt: false, ignoreMute: false)
    }

    func setMuted(_ on: Bool) {
        isMuted = on
        if on { synthesizer.stopSpeaking(at: .immediate) }
    }

    func stop() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.synthesizer.stopSpeaking(at: .immediate)
            self.restoreAudio()
        }
    }

    func reroutingChime() {
        DispatchQueue.main.async {
            AudioServicesPlaySystemSound(1007)
        }
    }

    func fasterRouteChime() {
        DispatchQueue.main.async {
            AudioServicesPlaySystemSound(1003)
        }
    }

    private func speakNow(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        let strings = NavStringsRegistry.shared.current()
        let language = strings.language.isEmpty ? "en" : strings.language
        let tag = strings.region.isEmpty ? language : "\(language)-\(strings.region)"
        utterance.voice = AVSpeechSynthesisVoice(language: tag)
            ?? AVSpeechSynthesisVoice(language: language)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.97
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0.05
        synthesizer.speak(utterance)
    }

    private func armAudio() {
        guard !audioArmed else { return }
        oldCategory = audio.category
        oldMode = audio.mode
        oldOptions = audio.categoryOptions
        do {
            try audio.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try audio.setActive(true)
            audioArmed = true
        } catch {
            log.error("audio session could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func restoreAudio() {
        guard audioArmed else { return }
        audioArmed = false
        do {
            try audio.setActive(false, options: .notifyOthersOnDeactivation)
            if let oldCategory, let oldMode {
                try audio.setCategory(oldCategory, mode: oldMode, options: oldOptions)
            }
        } catch {
            log.error("audio session could not restore: \(error.localizedDescription, privacy: .public)")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.spokenCount += 1
            let text = utterance.speechString
            #if DEBUG
            self.log.debug("spoken: \(text, privacy: .public)")
            #endif
            self.onSpeech?(self.spokenCount, text)
        }
    }
}
