import AVFoundation
import Foundation
import VelaCore

/// Plays the short tones a list can choose. The frequencies and durations come from the shared
/// Kotlin `PassAlerts` table through `SavedListSounds`, so iOS and Android keep the same four
/// sounds and no audio file is bundled. "Say its name" is spoken by `VelaNavVoice` instead.
///
/// The engine uses the ambient category with mixing so a preview never stops guidance or another
/// app's audio, and it is built on first use: a launch that never opens a list editor pays nothing.
final class SavedSoundPlayer {
    static let shared = SavedSoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
    private var configured = false

    private init() {}

    func play(notes: [SavedToneNote]) {
        guard !notes.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.playOnMain(notes)
        }
    }

    private func playOnMain(_ notes: [SavedToneNote]) {
        guard configure() else { return }
        player.stop()
        var scheduled = false
        for note in notes {
            guard note.hz > 0, note.milliseconds > 0,
                  let buffer = tone(hz: note.hz, milliseconds: note.milliseconds) else { continue }
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            scheduled = true
        }
        guard scheduled else { return }
        player.play()
    }

    private func configure() -> Bool {
        if configured { return engine.isRunning || (try? engine.start()) != nil }
        guard let format else { return false }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try engine.start()
            configured = true
            return true
        } catch {
            return false
        }
    }

    /// One sine note with a 6 ms fade in and out, so the speaker does not click at either end.
    private func tone(hz: Double, milliseconds: Double) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let frames = AVAudioFrameCount(format.sampleRate * milliseconds / 1000)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        let fade = min(AVAudioFrameCount(format.sampleRate * 0.006), frames / 2)
        for frame in 0..<Int(frames) {
            let phase = 2 * Double.pi * hz * Double(frame) / format.sampleRate
            var gain = 0.22
            if fade > 0 {
                if frame < Int(fade) { gain *= Double(frame) / Double(fade) }
                if frame > Int(frames) - Int(fade) { gain *= Double(Int(frames) - frame) / Double(fade) }
            }
            samples[frame] = Float(sin(phase) * gain)
        }
        return buffer
    }
}
