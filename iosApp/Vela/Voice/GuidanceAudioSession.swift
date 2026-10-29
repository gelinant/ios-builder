import AVFoundation
import Foundation
import OSLog

/// The navigation guidance audio session: `.playback` in `.voicePrompt` mode with ducking, shared
/// by the Apple and neural engines so switching between them cannot leave the session active or
/// restore the wrong category. Refcounted per speak: End restores the category captured before the
/// first prompt.
final class GuidanceAudioSession {
    static let shared = GuidanceAudioSession()

    private let session = AVAudioSession.sharedInstance()
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "NavAudio")
    private var users = 0
    private var oldCategory: AVAudioSession.Category?
    private var oldMode: AVAudioSession.Mode?
    private var oldOptions: AVAudioSession.CategoryOptions = []

    private init() {}

    @discardableResult
    func arm() -> Bool {
        if users == 0 {
            oldCategory = session.category
            oldMode = session.mode
            oldOptions = session.categoryOptions
            do {
                try session.setCategory(
                    .playback, mode: .voicePrompt,
                    options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
                try session.setActive(true)
            } catch {
                log.error("audio session could not start: \(error.localizedDescription, privacy: .public)")
                oldCategory = nil
                oldMode = nil
                return false
            }
        }
        users += 1
        return true
    }

    func restore() {
        guard users > 0 else { return }
        users -= 1
        guard users == 0 else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            if let oldCategory, let oldMode {
                try session.setCategory(oldCategory, mode: oldMode, options: oldOptions)
            }
        } catch {
            log.error("audio session could not restore: \(error.localizedDescription, privacy: .public)")
        }
        oldCategory = nil
        oldMode = nil
    }
}
