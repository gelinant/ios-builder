import AVFoundation
import Combine
import Foundation

/// Settings > Voice > Guidance volume, using the same four tiers as Android. The value is a
/// multiplier on a voice that has been levelled to `GuidanceLevel.targetRMS`, never an absolute
/// output level: iOS gives an app no way to set the hardware volume separately from other audio.
enum GuidanceVolumeTier: Float, CaseIterable, Identifiable {
    case softer = 0.6
    case normal = 1.0
    case louder = 1.6
    case loudest = 2.2

    var id: Float { rawValue }

    /// AVSpeechUtterance.volume is capped at 1.0, so Apple's voice can only be made softer. The
    /// neural path can go above unity because it scales its own PCM before playback.
    var appleVolume: Float { min(rawValue, 1) }

    var labelKey: String {
        switch self {
        case .softer: return "settings_voice_volume_softer"
        case .normal: return "settings_voice_volume_normal"
        case .louder: return "settings_voice_volume_louder"
        case .loudest: return "settings_voice_volume_loudest"
        }
    }

    static func nearest(_ value: Float) -> GuidanceVolumeTier {
        allCases.min { abs($0.rawValue - value) < abs($1.rawValue - value) } ?? .normal
    }
}

/// The Android speed presets: a multiplier from 0.5 to 2.0 in steps of 0.1, default 0.8 (the
/// remotely configurable Android default). The same multiplier drives Apple's rate and the
/// Piper length scale, so one setting sounds consistent across both engines.
enum GuidanceSpeed {
    static let minimum: Float = 0.5
    static let maximum: Float = 2.0
    static let step: Float = 0.1
    static let defaultMultiplier: Float = 0.8

    static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return defaultMultiplier }
        return min(max(value, minimum), maximum)
    }

    /// AVSpeechUtterance rates span 0.0 to 1.0 with 0.5 as the system default. Multiplying keeps
    /// 1.00x at the Apple default; 2.0x reaches the maximum, 0.5x is a quarter of the default.
    static func appleRate(_ multiplier: Float) -> Float {
        let rate = AVSpeechUtteranceDefaultSpeechRate * clamp(multiplier)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }
}

/// The Android `VoiceLevel` math, in Swift: bring a voice's long-run RMS to a target and scale it
/// by the user tier, then round off what crosses the knee instead of clipping. The mean is kept
/// between sessions so the first line of a drive is already at the right level.
enum GuidanceLevel {
    static let targetRMS: Float = 0.13
    static let maxLift: Float = 4
    static let knee: Float = 0.8
    static let minPeak: Float = 0.02

    struct Meter: Equatable {
        var sumSq: Double = 0
        var count: Int64 = 0

        var rms: Float { count > 0 ? Float((sumSq / Double(count)).squareRoot()) : 0 }

        mutating func add(_ chunk: [Float]) {
            guard peak(chunk) >= GuidanceLevel.minPeak else { return }
            var sum = 0.0
            for sample in chunk { sum += Double(sample) * Double(sample) }
            sumSq += sum
            count += Int64(chunk.count)
        }

        var encoded: String { "\(sumSq)|\(count)" }

        init(sumSq: Double = 0, count: Int64 = 0) {
            self.sumSq = sumSq
            self.count = count
        }

        init(encoded: String?) {
            let parts = encoded?.split(separator: "|", maxSplits: 1) ?? []
            guard parts.count == 2,
                  let sum = Double(parts[0]),
                  let n = Int64(parts[1]),
                  sum.isFinite, sum >= 0, n > 0 else {
                self.init()
                return
            }
            self.init(sumSq: sum, count: n)
        }
    }

    /// The gain for a voice whose level is `voiceRMS`, times the user's `tier`. Never lowers a
    /// voice that is already loud: the lift alone is at least 1. An unmeasured voice gets the
    /// tier alone.
    static func gain(voiceRMS: Float, tier: Float) -> Float {
        let lift: Float
        if voiceRMS <= 0 || voiceRMS.isNaN {
            lift = 1
        } else {
            lift = min(max(targetRMS / voiceRMS, 1), maxLift)
        }
        return lift * tier
    }

    static func limit(_ value: Float) -> Float {
        let magnitude = abs(value)
        guard magnitude > knee else { return value }
        let limited = knee + (1 - knee) * tanhf((magnitude - knee) / (1 - knee))
        return value < 0 ? -limited : limited
    }

    static func apply(_ samples: inout [Float], gain: Float) {
        if gain == 1 {
            for index in samples.indices where abs(samples[index]) > knee {
                samples[index] = limit(samples[index])
            }
            return
        }
        for index in samples.indices {
            samples[index] = limit(samples[index] * gain)
        }
    }

    private static func peak(_ chunk: [Float]) -> Float {
        var result: Float = 0
        for sample in chunk {
            let magnitude = abs(sample)
            if magnitude > result { result = magnitude }
        }
        return result
    }
}

/// The persisted guidance volume and speed, plus each neural voice's measured loudness. Keys are
/// namespaced like the other iOS preferences. Testable with a throwaway `UserDefaults` suite.
final class VoiceControlSettings: ObservableObject {
    static let shared = VoiceControlSettings()

    static let volumeKey = "app.vela.ios.voice.volume"
    static let rateKey = "app.vela.ios.voice.rate"
    static let levelPrefix = "app.vela.ios.voice.level."

    @Published private(set) var tier: GuidanceVolumeTier
    @Published private(set) var rate: Float

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = (defaults.object(forKey: Self.volumeKey) as? NSNumber)?.floatValue
        tier = GuidanceVolumeTier.nearest(stored ?? GuidanceVolumeTier.normal.rawValue)
        let storedRate = (defaults.object(forKey: Self.rateKey) as? NSNumber)?.floatValue
        rate = GuidanceSpeed.clamp(storedRate ?? GuidanceSpeed.defaultMultiplier)
    }

    /// Multiplier for the neural gain and for any spoken sample.
    var gain: Float { tier.rawValue }

    var appleRate: Float { GuidanceSpeed.appleRate(rate) }

    var speedLabel: String { String(format: "%.2fx", rate) }

    func setTier(_ tier: GuidanceVolumeTier) {
        self.tier = tier
        defaults.set(tier.rawValue, forKey: Self.volumeKey)
    }

    func setRate(_ multiplier: Float) {
        rate = GuidanceSpeed.clamp(multiplier)
        defaults.set(rate, forKey: Self.rateKey)
    }

    func stepRate(_ delta: Float) {
        setRate((rate + delta).rounded(toPlaces: 1))
    }

    func meter(for voiceID: String) -> GuidanceLevel.Meter {
        GuidanceLevel.Meter(encoded: defaults.string(forKey: Self.levelPrefix + voiceID))
    }

    func store(_ meter: GuidanceLevel.Meter, for voiceID: String) {
        defaults.set(meter.encoded, forKey: Self.levelPrefix + voiceID)
    }

    /// The gain for a measured voice at the current tier.
    func gain(forVoiceRMS rms: Float) -> Float {
        GuidanceLevel.gain(voiceRMS: rms, tier: gain)
    }
}

private extension Float {
    func rounded(toPlaces places: Int) -> Float {
        let scale = powf(10, Float(places))
        return (self * scale).rounded() / scale
    }
}
