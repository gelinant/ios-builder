import AVFoundation
import XCTest
@testable import Vela

/// VO-2: the recognized-phrase planner, the shared catalog shape, and a real on-device
/// recognition of synthesized speech (the CI simulator has no usable microphone, so the words come
/// from the Piper voice fixture instead of a recording).
final class VoiceSearchTests: XCTestCase {

    // MARK: - Catalog

    func testCatalogMatchesTheAndroidRelease() {
        let ids = AsrCatalogView.all.map { $0.id }
        XCTAssertEqual(["whisper-tiny", "whisper-base", "whisper-small", "sensevoice", "moonshine"], ids)
        for entry in AsrCatalogView.all {
            XCTAssertTrue(entry.downloadUrl.hasPrefix(
                "https://github.com/PimpinPumpkin/Vela/releases/download/asr-models/"))
            XCTAssertGreaterThan(entry.sizeMb, 0)
            XCTAssertGreaterThan(entry.expectedBytes, 1_000_000)
            XCTAssertEqual(entry.sha256.count, 64)
            XCTAssertTrue(entry.files.contains("silero_vad.onnx"), "\(entry.id) has no VAD file")
        }
        XCTAssertEqual(AsrCatalogView.defaultEngine(language: "en")?.id ?? "", "whisper-tiny")
        XCTAssertEqual(AsrCatalogView.defaultEngine(language: "fr")?.id ?? "", "whisper-base")
        XCTAssertEqual(AsrCatalogView.entry("whisper-base")?.whisperPrefix ?? "", "base")
        XCTAssertEqual(AsrCatalogView.entry("sensevoice")?.whisperPrefix ?? "x", "")
    }

    func testInstalledEnginesComeFromTheFilesystem() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-asr-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = AsrCatalogView.entry("whisper-tiny")!
        let dir = AsrLayout.directory(id: entry.id, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertEqual(AsrLayout.installed(root: root), [], "an empty folder is not an install")
        for name in entry.files.dropLast() {
            try Data([0x01]).write(to: dir.appendingPathComponent(name))
        }
        XCTAssertEqual(AsrLayout.installed(root: root), [], "one missing file is not an install")
        try Data([0x01]).write(to: dir.appendingPathComponent(entry.files.last!))
        XCTAssertEqual(AsrLayout.installed(root: root), [entry.id])
        XCTAssertEqual(AsrLayout.files(entry, root: root).count, entry.files.count)
    }

    // MARK: - Intent from recognized text

    func testRecognizedPhrasesBecomeTheSameActionsAsAndroid() {
        let en = { (text: String) in VoiceIntentPlanner.plan(heard: text, language: "en") }
        XCTAssertEqual(en("coffee")?.action ?? "", "search")
        XCTAssertEqual(en("coffee")?.query ?? "", "coffee")
        XCTAssertEqual(en("where is the nearest gas station")?.query ?? "", "gas station")
        XCTAssertEqual(en("navigate to the ferry building")?.action ?? "", "navigate")
        XCTAssertEqual(en("navigate to the ferry building")?.query ?? "", "the ferry building")
        XCTAssertEqual(en("take me home")?.action ?? "", "home")
        XCTAssertEqual(en("get me to work")?.action ?? "", "work")
        XCTAssertEqual(en("what is my ETA")?.action ?? "", "eta")
        let route = en("from davis to san francisco")
        XCTAssertEqual(route?.action ?? "", "route")
        XCTAssertEqual(route?.from ?? "", "davis")
        XCTAssertEqual(route?.to ?? "", "san francisco")
        // A business name that looks like a command stays a search.
        XCTAssertEqual(en("home depot")?.action ?? "", "search")
        XCTAssertNil(VoiceIntentPlanner.plan(heard: "   ", language: "en"))
        XCTAssertEqual(VoiceIntentPlanner.plan(heard: "trouve-moi une pharmacie", language: "fr")?.query ?? "", "pharmacie")
    }

    // MARK: - Real recognition

    func testWhisperTinyTranscribesSynthesizedSpeech() throws {
        guard let asrFixture = Bundle.main.url(forResource: "AsrFixture", withExtension: nil) else {
            throw XCTSkip("no AsrFixture in the test app; scripts/ios/ci-ipa.sh injects one")
        }
        let entry = AsrCatalogView.entry("whisper-tiny")!
        let asrRoot = asrFixture
        guard AsrLayout.isComplete(entry, root: asrRoot) else {
            throw XCTSkip("AsrFixture is incomplete")
        }
        guard let voiceFixture = Bundle.main.url(forResource: "VoiceFixture", withExtension: nil),
              let voiceEntry = VoiceCatalog.entry("en_US-hfc_female-medium"),
              VoiceLayout.isComplete(id: voiceEntry.id, root: voiceFixture) else {
            throw XCTSkip("no VoiceFixture to speak the test sentence")
        }

        // Speak a short command with the neural voice, then recognize it with the same sherpa
        // runtime the app uses. No microphone and no network involved.
        let tts = SherpaTts()
        let files = SherpaTts.VoiceFiles(
            id: voiceEntry.id,
            model: VoiceLayout.modelPath(id: voiceEntry.id, root: voiceFixture),
            tokens: VoiceLayout.tokensPath(id: voiceEntry.id, root: voiceFixture),
            dataDir: VoiceLayout.dataPath(id: voiceEntry.id, root: voiceFixture))
        guard let rendered = tts.render(text: "Navigate to coffee", files: files) else {
            XCTFail("the Piper voice produced no audio")
            return
        }
        let samples = try Self.resampleTo16k(rendered.samples, from: Double(rendered.rate))
        XCTAssertGreaterThan(samples.count, 4_000, "the sentence is too short to recognize")

        let asr = SherpaAsr()
        let model = SherpaAsr.Model(
            id: entry.id, modelType: entry.modelType, language: "en",
            files: AsrLayout.files(entry, root: asrRoot))
        let text = try asr.transcribe(samples: samples, sampleRate: 16000, model: model)
        print("SEAM_TEST VOICE_ASR text=\(text.replacingOccurrences(of: " ", with: "_")) samples=\(samples.count)")
        XCTAssertFalse(text.isEmpty, "the recognizer returned nothing")
        XCTAssertTrue(text.lowercased().contains("coffee"),
                      "unexpected transcript: \(text)")

        // The transcript goes through the common planner, as a microphone result would.
        let plan = VoiceIntentPlanner.plan(heard: text, language: "en")
        print("SEAM_TEST VOICE_ASR_PLAN action=\(plan?.action ?? "none") query=\(plan?.query ?? "none")")
    }

    /// Linear resampling to 16 kHz mono. The test sentence is short, so a simple converter is
    /// enough; the app's capture path uses AVAudioConverter.
    private static func resampleTo16k(_ input: [Float], from rate: Double) throws -> [Float] {
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat,
                                              frameCapacity: AVAudioFrameCount(input.count)) else {
            throw XCTSkip("could not build the resampler")
        }
        inBuffer.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { source in
            inBuffer.floatChannelData![0].update(from: source.baseAddress!, count: input.count)
        }
        let capacity = AVAudioFrameCount(Double(input.count) * 16000 / rate) + 128
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            throw XCTSkip("could not build the resampler output")
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return inBuffer
        }
        if let error { throw error }
        let data = outBuffer.floatChannelData![0]
        return Array(UnsafeBufferPointer(start: data, count: Int(outBuffer.frameLength)))
    }
}
