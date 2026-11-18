import AVFoundation
import Foundation
import OSLog
import SherpaOnnxC

/// A Piper VITS model through the sherpa-onnx C API, rendered on a serial worker and played with
/// AVAudioEngine. The model's own sample rate is used (Piper is 22.05 kHz; 24 kHz models work
/// unchanged), and a whole prompt is rendered before playback so an interrupt never mixes half a
/// sentence with the next one.
final class SherpaTts {
    struct VoiceFiles {
        let id: String
        let model: String
        let tokens: String
        let dataDir: String
    }

    private let log = Logger(subsystem: OSLogLog.subsystem, category: "NeuralVoice")
    private let queue = DispatchQueue(label: "app.vela.ios.neural-tts", qos: .userInitiated)
    private var engine: OpaquePointer?
    private var loaded: VoiceFiles?
    private var loadedSpeakers = 0
    private var generation = 0
    private var audio: NeuralAudioOutput?

    /// True once a model is loaded and can generate audio.
    var ready: Bool { engine != nil }

    var speakerCount: Int { loadedSpeakers }

    /// Load [files] off the main thread. Idempotent for the same voice.
    func warmUp(_ files: VoiceFiles) {
        queue.async { [weak self] in _ = self?.ensureLoaded(files) }
    }

    func speak(
        _ text: String,
        files: VoiceFiles,
        interrupt: Bool,
        onStart: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        if interrupt {
            generation += 1
            DispatchQueue.main.async { [weak self] in self?.audio?.stop() }
        }
        let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            guard let engine = self.ensureLoaded(files) else {
                DispatchQueue.main.async { if token == self.generation { onFailure() } }
                return
            }
            guard token == self.generation else {
                DispatchQueue.main.async { onDone() }
                return
            }
            let start = Date()
            // The Android presets drive this model too: speed is the same multiplier the system
            // voice uses, and the gain is the levelled voice at the user's guidance tier.
            let control = VoiceControlSettings.shared
            let speed = GuidanceSpeed.clamp(control.rate)
            guard let rendered = Self.generate(engine, text: text, speed: speed) else {
                self.log.error("synthesis failed for voice \(files.id, privacy: .public)")
                DispatchQueue.main.async { if token == self.generation { onFailure() } }
                return
            }
            self.log.info(
                "synthesized \(rendered.samples.count, privacy: .public) samples at \(rendered.rate, privacy: .public) Hz in \(Int(Date().timeIntervalSince(start) * 1000), privacy: .public) ms")
            guard token == self.generation else {
                DispatchQueue.main.async { onDone() }
                return
            }
            // Measure the raw render, then apply one gain to the whole line so the level cannot
            // pump between phrases. The mean is kept per voice for the next session.
            var meter = control.meter(for: files.id)
            meter.add(rendered.samples)
            let gain = control.gain(forVoiceRMS: meter.count > 0 ? meter.rms : 0)
            var samples = rendered.samples
            GuidanceLevel.apply(&samples, gain: gain)
            control.store(meter, for: files.id)
            let levelled = Rendered(samples: samples, rate: rendered.rate)

            DispatchQueue.main.async {
                guard token == self.generation else { onDone(); return }
                self.play(levelled, token: token, onStart: onStart, onDone: onDone)
            }
        }
    }

    func stop() {
        generation += 1
        DispatchQueue.main.async { [weak self] in self?.audio?.stop() }
    }

    /// Synchronous render for the synthesis smoke test. Never used on the speaking path.
    func render(text: String, files: VoiceFiles) -> (samples: [Float], rate: Int)? {
        queue.sync {
            guard let engine = ensureLoaded(files), let rendered = Self.generate(engine, text: text) else {
                return nil
            }
            return (rendered.samples, rendered.rate)
        }
    }

    /// Release the engine when its files are about to be deleted. A subsequent speak reloads.
    func unload(_ id: String) {
        queue.async { [weak self] in
            guard let self, self.loaded?.id == id else { return }
            self.releaseLocked()
        }
    }

    func release() {
        generation += 1
        DispatchQueue.main.async { [weak self] in self?.audio?.stop() }
        queue.async { [weak self] in self?.releaseLocked() }
    }

    private func releaseLocked() {
        if let engine { SherpaOnnxDestroyOfflineTts(engine) }
        engine = nil
        loaded = nil
        loadedSpeakers = 0
    }

    /// Called only on [queue].
    private func ensureLoaded(_ files: VoiceFiles) -> OpaquePointer? {
        if let engine, loaded?.id == files.id { return engine }
        releaseLocked()
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.num_threads = 2
        config.model.debug = 0
        config.max_num_sentences = 1
        config.silence_scale = 0.2
        config.model.vits.noise_scale = 0.45
        config.model.vits.noise_scale_w = 0.55
        config.model.vits.length_scale = 1.0
        let model = strdup(files.model)
        let tokens = strdup(files.tokens)
        let dataDir = strdup(files.dataDir)
        defer {
            free(model)
            free(tokens)
            free(dataDir)
        }
        config.model.vits.model = model.map { UnsafePointer($0) }
        config.model.vits.tokens = tokens.map { UnsafePointer($0) }
        config.model.vits.data_dir = dataDir.map { UnsafePointer($0) }
        let created = SherpaOnnxCreateOfflineTts(&config)
        guard let created else {
            log.error("model load failed: \(files.id, privacy: .public)")
            return nil
        }
        engine = created
        loaded = files
        loadedSpeakers = Int(SherpaOnnxOfflineTtsNumSpeakers(created))
        log.info(
            "loaded \(files.id, privacy: .public): \(SherpaOnnxOfflineTtsSampleRate(created), privacy: .public) Hz, \(self.loadedSpeakers, privacy: .public) speakers")
        return created
    }

    private struct Rendered {
        let samples: [Float]
        let rate: Int
    }

    private static func generate(_ engine: OpaquePointer, text: String, speed: Float = 1.0) -> Rendered? {
        let audio: UnsafePointer<SherpaOnnxGeneratedAudio>? = text.withCString {
            SherpaOnnxOfflineTtsGenerate(engine, $0, 0, speed)
        }
        guard let audio else { return nil }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples else { return nil }
        return Rendered(
            samples: Array(UnsafeBufferPointer(start: samples, count: count)),
            rate: Int(audio.pointee.sample_rate))
    }

    private func play(
        _ rendered: Rendered, token: Int, onStart: @escaping () -> Void, onDone: @escaping () -> Void
    ) {
        guard token == generation else { onDone(); return }
        audio?.stop()
        let output = NeuralAudioOutput()
        audio = output
        guard output.play(samples: rendered.samples, rate: rendered.rate, completion: { [weak self] in
            guard let self, token == self.generation else { return }
            self.audio = nil
            onDone()
        }) else {
            audio = nil
            onDone()
            return
        }
        onStart()
    }
}

/// One AVAudioEngine per prompt. The engine converts the model's mono float rate to the output
/// route; stopping it releases the graph after the line, so a route change cannot leave stale state.
private final class NeuralAudioOutput {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var armed = false
    private var finished = false

    func play(samples: [Float], rate: Int, completion: @escaping () -> Void) -> Bool {
        guard rate > 0, !samples.isEmpty else { return false }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(rate), channels: 1, interleaved: false),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
        else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        guard let channel = buffer.floatChannelData?[0] else { return false }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }

        armed = GuidanceAudioSession.shared.arm()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            if armed { GuidanceAudioSession.shared.restore() }
            armed = false
            return false
        }
        self.engine = engine
        self.player = player
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                self.finished = true
                self.stop()
                completion()
            }
        }
        player.play()
        return true
    }

    func stop() {
        finished = true
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        if armed {
            GuidanceAudioSession.shared.restore()
            armed = false
        }
    }
}
