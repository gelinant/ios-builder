import AVFoundation
import Foundation
import Speech

/// Apple's speech recognizer as the fallback when no sherpa model is installed. On-device
/// recognition is REQUIRED (`requiresOnDeviceRecognition`): if the device or the language cannot
/// run it locally, this refuses instead of letting SFSpeechRecognizer send audio to Apple's
/// service. That is the documented difference from the sherpa path, which never leaves the phone.
final class AppleSpeech {
    enum Failure: LocalizedError {
        case notAuthorized
        case unavailable
        case onDeviceUnavailable(String)
        case noResult

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Speech recognition is not allowed. Enable it for Vela in Settings."
            case .unavailable:
                return "The speech recognizer is not available right now."
            case .onDeviceUnavailable(let language):
                return "On-device speech recognition is not available for \(language). Download a Vela voice search model, or add the language in iOS Settings."
            case .noResult:
                return "No speech was recognized."
            }
        }
    }

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    private var onPartial: ((String) -> Void)?

    /// Asks for speech authorization once (the caller asks for the microphone separately).
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static var authorization: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// Start a live recognition. Buffers appended afterwards must be in the recognizer's format.
    func start(language: String, onPartial: @escaping (String) -> Void) throws {
        guard Self.authorization == .authorized else { throw Failure.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
              recognizer.isAvailable else { throw Failure.unavailable }
        guard recognizer.supportsOnDeviceRecognition else {
            throw Failure.onDeviceUnavailable(Locale.current.localizedString(forIdentifier: language) ?? language)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .search
        self.recognizer = recognizer
        self.request = request
        self.latest = ""
        self.onPartial = onPartial
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.latest = result.bestTranscription.formattedString
                if result.isFinal { self.onPartial?(self.latest) }
            }
            if error != nil && self.latest.isEmpty { self.onPartial?("") }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    /// End the audio and wait for the final transcript (or an empty string).
    func finish(timeout: TimeInterval = 6) async -> String {
        request?.endAudio()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if task?.state != .running, !latest.isEmpty { break }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        let text = latest
        cancel()
        return text
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        recognizer = nil
    }
}
