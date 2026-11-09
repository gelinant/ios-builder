import AVFoundation
import Foundation

/// The microphone side of dictation: the engine's input node, converted to the 16 kHz mono float
/// samples sherpa-onnx expects, with a loudness value for the listening ring and a silence timer so
/// a forgotten sheet stops by itself. It records only between [start] and [stop]: there is no
/// always-on microphone.
final class VoiceCapture {
    enum Failure: LocalizedError {
        case noInput
        case converter
        case engine(String)

        var errorDescription: String? {
            switch self {
            case .noInput: return "No microphone is available."
            case .converter: return "The microphone format could not be converted."
            case .engine(let detail): return "The microphone could not start: \(detail)"
            }
        }
    }

    /// Samples at 16 kHz for the offline recognizer.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Unchanged original buffers, for Apple's recognizer (which wants the input format).
    var onRawBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Loudness in 0...1, about fifteen times a second.
    var onLevel: ((Float) -> Void)?
    /// Called once when the silence timer or the maximum length stops the capture.
    var onAutoStop: (() -> Void)?

    var maxSeconds: TimeInterval = 12
    private let silenceSeconds: TimeInterval = 1.4

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?
    private var startedAt = Date()
    private var sawSpeech = false
    private var quietSince: Date?
    private var running = false

    func start() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw Failure.noInput }
        guard let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: target) else {
            throw Failure.converter
        }
        self.target = target
        self.converter = converter
        startedAt = Date()
        sawSpeech = false
        quietSince = nil
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.engine(error.localizedDescription)
        }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        target = nil
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        let level = Self.level(of: buffer)
        let now = Date()
        if level > 0.06 {
            sawSpeech = true
            quietSince = nil
        } else if sawSpeech, quietSince == nil {
            quietSince = now
        }
        onLevel?(level)
        onRawBuffer?(buffer)
        if let converted = Self.convert(buffer, with: converter, to: target) {
            onBuffer?(converted)
        }
        let timedOut = now.timeIntervalSince(startedAt) > maxSeconds
        let silenced = quietSince.map { now.timeIntervalSince($0) > silenceSeconds } ?? false
        if timedOut || silenced { onAutoStop?() }
    }

    /// Root mean square of the buffer, exaggerated into a visible 0...1 range.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for index in 0..<count {
            let sample = data[index]
            sum += sample * sample
        }
        let rms = (sum / Float(count)).squareRoot()
        return min(1, rms * 12)
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter?, to target: AVAudioFormat?
    ) -> AVAudioPCMBuffer? {
        guard let converter, let target else { return nil }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            return nil
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
