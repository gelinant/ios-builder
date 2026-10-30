import AVFoundation
import Foundation
import OSLog
import Speech
import SwiftUI
import VelaCore

/// Voice search (VO-2): permission, capture, recognition and the common intent parser.
///
/// The recognizer only produces text. `VoicePlanner` in `:ios-shared` reads that text with the same
/// `QueryIntents` vocabulary Android's voice dialog uses, and the actions below go through the
/// existing search and route stores. There is deliberately no second search path.
///
/// Two recognizers, chosen by what is installed:
///  - a downloaded sherpa-onnx model (Whisper by default), fully on-device, the same archives as
///    Android;
///  - Apple's `SFSpeechRecognizer`, only with `requiresOnDeviceRecognition`, as the fallback when no
///    model is installed.
@MainActor
final class VoiceSearchModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case recognising
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var heard = ""
    @Published private(set) var status = ""
    @Published private(set) var debugLine = "engine=none state=idle"

    private let session: MapSession
    private let search: SearchModel
    private let route: RouteModel
    private let saved: SavedModel
    private let capture = VoiceCapture()
    private let sherpa = SherpaAsr()
    private let apple = AppleSpeech()
    private let asr = AsrStore.shared
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "VoiceSearch")

    private var samples: [Float] = []
    private var engineId: String?
    private var engineLabel = "none"
    private var busy = false
    private var injected = false
    private var recognizing = false

    init(session: MapSession, search: SearchModel, route: RouteModel, saved: SavedModel) {
        self.session = session
        self.search = search
        self.route = route
        self.saved = saved
        capture.onBuffer = { [weak self] buffer in self?.collect(buffer) }
        capture.onRawBuffer = { [weak self] buffer in
            guard let self, self.engineLabel == "apple" else { return }
            self.apple.append(buffer)
        }
        capture.onLevel = { [weak self] value in
            DispatchQueue.main.async { self?.level = value }
        }
        capture.onAutoStop = { [weak self] in
            DispatchQueue.main.async { self?.finish() }
        }
        #if DEBUG
        injected = LaunchOptionsAsr.injectedText != nil
        #endif
    }

    var isOpen: Bool { phase != .idle }

    var isListening: Bool { phase == .listening }

    /// The app language, not the guidance language: voice search follows the menus even when the
    /// spoken directions are set to another language.
    private var language: String {
        DirectionsLanguage.shared.appLanguage(tag: DevicePlatformLocale.effectiveTag())
    }

    // MARK: - Opening

    /// Opens the listening sheet. With an injected phrase (Debug UI scenarios) it reviews that
    /// text instead of opening the microphone.
    func open() {
        guard !busy else { return }
        heard = ""
        level = 0
        samples = []
        #if DEBUG
        if let text = LaunchOptionsAsr.injectedText {
            injected = true
            engineLabel = "injected"
            heard = text
            status = "Searching"
            phase = .listening
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 450_000_000)
                await self?.apply(text)
            }
            return
        }
        #endif
        injected = false
        let chosen = asr.engineId(forLanguage: language)
        engineId = chosen
        if let chosen, let entry = asr.entry(chosen) {
            engineLabel = "sherpa"
            let model = SherpaAsr.Model(
                id: entry.id, modelType: entry.modelType, language: language,
                files: asr.files(for: entry))
            sherpa.warmUp(model)
            startCapture()
        } else {
            engineLabel = "apple"
            status = "Preparing speech recognition"
            phase = .listening
            Task { await startApple() }
        }
        updateDebug(state: "opening")
    }

    // MARK: - Capture

    private func requestMic() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: break
        @unknown default: return false
        }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startCapture() {
        Task {
            guard await requestMic() else {
                fail("Microphone access is off. Allow it for Vela in Settings, then try again.")
                return
            }
            guard DictationAudio.shared.begin() else {
                fail("The microphone could not start. Close other audio apps and try again.")
                return
            }
            do {
                try capture.start()
            } catch {
                DictationAudio.shared.end()
                fail(error.localizedDescription)
                return
            }
            phase = .listening
            status = "Listening"
            updateDebug(state: "listening")
        }
    }

    private func startApple() async {
        let authorization = await AppleSpeech.requestAuthorization()
        guard authorization == .authorized else {
            fail("Speech recognition is not allowed. Enable it for Vela in Settings, or download a Vela voice search model.")
            return
        }
        guard await requestMic() else {
            fail("Microphone access is off. Allow it for Vela in Settings, then try again.")
            return
        }
        guard DictationAudio.shared.begin() else {
            fail("The microphone could not start. Close other audio apps and try again.")
            return
        }
        do {
            try apple.start(language: language) { [weak self] text in
                guard let self, !text.isEmpty else { return }
                self.heard = text
            }
            try capture.start()
        } catch {
            apple.cancel()
            DictationAudio.shared.end()
            fail(error.localizedDescription)
            return
        }
        phase = .listening
        status = "Listening"
        updateDebug(state: "listening")
    }

    private func collect(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    /// The Stop button, and the silence timer, both land here.
    func finish() {
        guard phase == .listening, !busy, !injected else { return }
        busy = true
        capture.stop()
        DictationAudio.shared.end()
        let label = engineLabel
        phase = .recognising
        status = "Recognising"
        updateDebug(state: "recognising")
        Task {
            defer { busy = false }
            if label == "apple" {
                let text = await apple.finish()
                await apply(text)
                return
            }
            let collected = samples
            samples = []
            guard let id = engineId, let entry = asr.entry(id) else {
                fail("The speech model is no longer available. Download it again in Settings.")
                return
            }
            let model = SherpaAsr.Model(
                id: entry.id, modelType: entry.modelType, language: language,
                files: asr.files(for: entry))
            let recognizer = sherpa
            do {
                let text = try await Task.detached(priority: .userInitiated) {
                    try recognizer.transcribe(samples: collected, sampleRate: 16000, model: model)
                }.value
                await apply(text)
            } catch {
                fail(error.localizedDescription)
            }
        }
    }

    /// Cancel: nothing is applied, and the audio session is released like after a normal stop.
    func cancel() {
        if phase == .listening { capture.stop() }
        apple.cancel()
        DictationAudio.shared.end()
        samples = []
        phase = .idle
        heard = ""
        level = 0
        updateDebug(state: "idle")
    }

    func dismissError() {
        phase = .idle
        status = ""
        heard = ""
        updateDebug(state: "idle")
    }

    // MARK: - Intent

    private func apply(_ raw: String) async {
        guard let request = VoiceIntentPlanner.plan(heard: raw, language: language) else {
            fail("No speech was heard. Hold the phone closer and try again.")
            return
        }
        heard = request.display
        updateDebug(state: "planned", action: request.action, query: request.query)
        switch request.action {
        case "navigate":
            navigate(to: request.query)
        case "home":
            shortcut(home: true)
        case "work":
            shortcut(home: false)
        case "route":
            await routeBetween(from: request.from ?? "", to: request.to ?? "")
        case "eta":
            eta()
        case "along":
            phase = .idle
            updateDebug(state: "along", query: request.query)
            await search.runAlongRoute(query: request.query)
        case "call":
            phase = .idle
            updateDebug(state: "call", query: request.query)
            await search.runCall(query: request.query)
        default:
            runSearch(request.query)
        }
    }

    private func runSearch(_ query: String) {
        search.search(query, viewport: nil)
        phase = .idle
        status = ""
        updateDebug(state: "searched", query: query)
    }

    /// "navigate to X": search X, then open the chooser on its first result, exactly like Android's
    /// voice dialog (the search runs, then the route chooser opens on the top hit).
    private func navigate(to query: String) {
        let baseline = session.search.state.value.submissions
        search.search(query, viewport: nil)
        phase = .idle
        updateDebug(state: "navigate", query: query)
        Task {
            guard let place = await waitForFirstResult(after: baseline, timeout: 45) else {
                fail("No result for \(query). Try a different name.", keepsSheet: false)
                return
            }
            session.place.select(p: place)
            route.openFromPlace()
            updateDebug(state: "routed", query: query)
        }
    }

    private func shortcut(home: Bool) {
        guard let item = saved.openShortcut(home: home) else {
            fail(home
                ? "No Home is saved yet. Set it in Saved, then ask again."
                : "No Work is saved yet. Set it in Saved, then ask again.")
            return
        }
        phase = .idle
        route.openFromPlace()
        updateDebug(state: home ? "home" : "work", query: item.name)
    }

    /// "A to B": both ends go through the ordinary search, then the chooser opens with the start
    /// already set. A miss on either end says so instead of routing from the wrong place.
    private func routeBetween(from: String, to: String) async {
        guard !from.isEmpty, !to.isEmpty else {
            fail("Name both ends, for example: from Davis to San Francisco.")
            return
        }
        let firstBaseline = session.search.state.value.submissions
        search.search(from, viewport: nil)
        guard let origin = await waitForFirstResult(after: firstBaseline, timeout: 45) else {
            fail("No start found for \(from).")
            return
        }
        let secondBaseline = session.search.state.value.submissions
        search.search(to, viewport: nil)
        guard let destination = await waitForFirstResult(after: secondBaseline, timeout: 45) else {
            fail("No destination found for \(to).")
            return
        }
        phase = .idle
        session.place.select(p: destination)
        route.openFromPlace()
        route.useSearchedOrigin(origin)
        updateDebug(state: "route", query: "\(from) to \(to)")
    }

    private func eta() {
        let nav = session.nav.state.value
        guard nav.navigating, nav.remainingDurationSeconds > 0 else {
            fail("There is no route in progress. Start guidance to ask for the ETA.")
            return
        }
        let minutes = Int((nav.remainingDurationSeconds / 60).rounded())
        phase = .idle
        VelaNavVoice.shared.speakSample(
            minutes <= 1 ? "Less than a minute left." : "About \(minutes) minutes left.")
        updateDebug(state: "eta", query: "\(minutes)min")
    }

    /// Polls the shared search store for the first result of the search submitted after
    /// [baseline] (the same store the panel shows).
    private func waitForFirstResult(after baseline: Int32, timeout: TimeInterval) async -> Place? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let state = session.search.state.value
            if state.submissions > baseline, !state.searching {
                return state.results.first
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return nil
    }

    private func fail(_ message: String, keepsSheet: Bool = false) {
        log.error("voice search: \(message, privacy: .public)")
        phase = keepsSheet ? .listening : .failed(message)
        status = message
        updateDebug(state: "failed")
    }

    private func updateDebug(state: String, action: String? = nil, query: String = "") {
        var parts = ["engine=\(engineLabel)", "state=\(state)"]
        if let action { parts.append("action=\(action)") }
        if !query.isEmpty { parts.append("query=\(query.replacingOccurrences(of: " ", with: "_"))") }
        if !heard.isEmpty { parts.append("heard=\(heard.replacingOccurrences(of: " ", with: "_"))") }
        parts.append("results=\(session.search.state.value.results.count)")
        debugLine = parts.joined(separator: " ")
    }

    /// Test and Settings helper: run a phrase as if it had been heard.
    func run(_ text: String) {
        Task { await apply(text) }
    }
}
