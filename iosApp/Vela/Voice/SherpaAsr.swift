import Foundation
import OSLog
import SherpaOnnxC

/// On-device speech recognition through the sherpa-onnx C API, the same runtime and the same model
/// archives as Android's voice search. The model is loaded once per (engine, language) pair on a
/// serial worker; recognition takes the whole utterance at 16 kHz and returns its text. Nothing
/// leaves the phone.
final class SherpaAsr {
    struct Model {
        let id: String
        let modelType: String
        let language: String
        /// File paths by archive file name (`tiny-encoder.int8.onnx`, `tokens.txt`, ...).
        let files: [String: String]
    }

    enum RecognitionError: LocalizedError {
        case loadFailed
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .loadFailed: return "The offline speech model could not be loaded."
            case .emptyAudio: return "No speech was recorded."
            }
        }
    }

    private let log = Logger(subsystem: OSLogLog.subsystem, category: "VoiceSearch")
    private let queue = DispatchQueue(label: "app.vela.ios.asr", qos: .userInitiated)
    private var engine: OpaquePointer?
    private var loadedKey: String?

    /// Load the model if it is not already the loaded one. Called before recording so a cold model
    /// does not eat the beginning of the sentence.
    func warmUp(_ model: Model) {
        queue.async { [weak self] in _ = self?.load(model) }
    }

    /// Transcribe mono float samples in [-1, 1] at [sampleRate]. Blocks its worker, never the caller.
    func transcribe(samples: [Float], sampleRate: Int32, model: Model) throws -> String {
        guard !samples.isEmpty else { throw RecognitionError.emptyAudio }
        return try queue.sync {
            guard let engine = load(model) else { throw RecognitionError.loadFailed }
            guard let stream = SherpaOnnxCreateOfflineStream(engine) else {
                throw RecognitionError.loadFailed
            }
            defer { SherpaOnnxDestroyOfflineStream(stream) }
            samples.withUnsafeBufferPointer { buffer in
                SherpaOnnxAcceptWaveformOffline(
                    stream, sampleRate, buffer.baseAddress, Int32(buffer.count))
            }
            SherpaOnnxDecodeOfflineStream(engine, stream)
            guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
            defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
            guard let text = result.pointee.text else { return "" }
            return String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Free the loaded model (a removed or replaced engine must not stay resident).
    func unload() {
        queue.async { [weak self] in
            guard let self else { return }
            if let engine = self.engine { SherpaOnnxDestroyOfflineRecognizer(engine) }
            self.engine = nil
            self.loadedKey = nil
        }
    }

    private func load(_ model: Model) -> OpaquePointer? {
        let key = "\(model.id)|\(model.language)"
        if key == loadedKey, let engine { return engine }
        if let engine { SherpaOnnxDestroyOfflineRecognizer(engine) }
        engine = nil
        loadedKey = nil

        var config = SherpaOnnxOfflineRecognizerConfig()
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80
        config.model_config.num_threads = 2
        config.model_config.debug = 0
        config.decoding_method = Self.cString("greedy_search")
        config.model_config.provider = Self.cString("cpu")

        let strings = CStringStore()
        let files = model.files
        switch model.modelType {
        case "whisper":
            let prefix = model.id.replacingOccurrences(of: "whisper-", with: "")
            config.model_config.whisper.encoder = strings.p(files["\(prefix)-encoder.int8.onnx"])
            config.model_config.whisper.decoder = strings.p(files["\(prefix)-decoder.int8.onnx"])
            config.model_config.whisper.task = strings.p("transcribe")
            config.model_config.whisper.language = strings.p(Self.whisperLanguage(model.language))
            config.model_config.tokens = strings.p(files["\(prefix)-tokens.txt"])
        case "sense_voice":
            config.model_config.sense_voice.model = strings.p(files["model.int8.onnx"])
            config.model_config.sense_voice.language = strings.p(model.language)
            config.model_config.sense_voice.use_itn = 1
            config.model_config.tokens = strings.p(files["tokens.txt"])
        case "moonshine":
            config.model_config.moonshine.preprocessor = strings.p(files["preprocess.onnx"])
            config.model_config.moonshine.encoder = strings.p(files["encode.int8.onnx"])
            config.model_config.moonshine.uncached_decoder = strings.p(files["uncached_decode.int8.onnx"])
            config.model_config.moonshine.cached_decoder = strings.p(files["cached_decode.int8.onnx"])
            config.model_config.tokens = strings.p(files["tokens.txt"])
        default:
            log.error("unsupported speech model type \(model.modelType, privacy: .public)")
            return nil
        }

        guard let created = SherpaOnnxCreateOfflineRecognizer(&config) else {
            log.error("could not load \(model.id, privacy: .public) for \(model.language, privacy: .public)")
            return nil
        }
        engine = created
        loadedKey = key
        log.info("loaded \(model.id, privacy: .public) for \(model.language, privacy: .public)")
        return created
    }

    /// Whisper wants an ISO language code; an app language it does not know is left to auto-detect.
    private static func whisperLanguage(_ language: String) -> String {
        let code = language.lowercased().prefix(2)
        let known: Set<String> = [
            "en", "fr", "de", "es", "it", "pt", "nl", "pl", "cs", "sk", "ro", "hu", "hr",
            "ru", "uk", "bg", "sr", "el", "tr", "ar", "he", "fa", "hi", "bn", "ta", "te",
            "ur", "th", "vi", "id", "ms", "zh", "ja", "ko", "sv", "da", "no", "fi", "et",
            "lv", "lt", "sl", "ca", "gl", "af", "sw",
        ]
        return known.contains(String(code)) ? String(code) : ""
    }

    private static func cString(_ value: String) -> UnsafePointer<CChar>? {
        // The config copies these during creation; a leaked tiny buffer per load is acceptable and
        // avoids dangling pointers when Swift reuses a String's storage.
        guard !value.isEmpty else { return nil }
        return UnsafePointer(strdup(value))
    }
}

/// Keeps the C strings handed to a sherpa config alive until the recognizer has copied them.
private final class CStringStore {
    private var pointers: [UnsafeMutablePointer<CChar>] = []

    func p(_ value: String?) -> UnsafePointer<CChar>? {
        guard let value, !value.isEmpty, let copy = strdup(value) else { return nil }
        pointers.append(copy)
        return UnsafePointer(copy)
    }

    deinit {
        for pointer in pointers { free(pointer) }
    }
}
