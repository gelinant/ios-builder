import AVFoundation
import XCTest
@testable import Vela
import SWCompression
import VelaCore

final class VoiceSelectionTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("vela-voice-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "vela-voice-tests-\(UUID().uuidString)")
        defaults.removeObject(forKey: "app.vela.ios.voice.model")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeVoice(_ id: String, modelBytes: Int = 1_100_000) throws {
        let dir = VoiceLayout.directory(id: id, root: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(count: modelBytes).write(to: dir.appendingPathComponent("\(id).onnx"))
        try Data("tokens".utf8).write(to: dir.appendingPathComponent("tokens.txt"))
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("espeak-ng-data"), withIntermediateDirectories: true)
    }

    func testCatalogMatchesAndroidIds() {
        XCTAssertEqual(VoiceCatalog.all.count, 43)
        XCTAssertEqual(VoiceCatalog.entry("en_US-hfc_female-medium")?.name, "HFC Female")
        XCTAssertEqual(VoiceCatalog.entry("fr_FR-siwis-medium")?.name, "Siwis")
        XCTAssertEqual(
            VoiceCatalog.entry("fr_FR-siwis-medium")?.downloadUrl,
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-fr_FR-siwis-medium.tar.bz2")
        XCTAssertEqual(VoiceCatalog.recommended(language: "fr")?.id, "fr_FR-siwis-medium")
    }

    func testInstalledSetComesFromCompleteDirectories() throws {
        try makeVoice("en_US-hfc_female-medium")
        try makeVoice("fr_FR-siwis-medium")
        // A partial extraction and a zero-byte model must never appear.
        try FileManager.default.createDirectory(
            at: VoiceLayout.directory(id: "en_US-lessac-medium", root: root), withIntermediateDirectories: true)
        try makeVoice("de_DE-thorsten-medium", modelBytes: 10)

        XCTAssertEqual(
            VoiceLayout.installed(root: root),
            ["en_US-hfc_female-medium", "fr_FR-siwis-medium"])
    }

    func testMissingModelKeepsSystemVoice() {
        let library = VoiceLibrary(root: root, defaults: defaults)
        XCTAssertNil(library.effectiveId)
        XCTAssertEqual(library.engine, "system")
        XCTAssertEqual(library.fallbackReason, "no-voice")
        XCTAssertNil(library.currentVoiceFiles())
    }

    func testCorruptModelFallsBackToSystem() throws {
        try makeVoice("en_US-hfc_female-medium", modelBytes: 10)
        let library = VoiceLibrary(root: root, defaults: defaults)
        XCTAssertTrue(library.installed.isEmpty)
        XCTAssertEqual(library.engine, "system")
    }

    func testSelectedVoiceWinsAndMissingSelectionFallsBack() throws {
        try makeVoice("en_US-hfc_female-medium")
        try makeVoice("en_US-lessac-medium")
        let library = VoiceLibrary(root: root, defaults: defaults)
        library.select("en_US-lessac-medium")
        XCTAssertEqual(library.effectiveId, "en_US-lessac-medium")
        XCTAssertEqual(library.engine, "neural")

        // A pref that names a deleted voice never points the engine at missing files.
        defaults.set("en_US-ryan-high", forKey: "app.vela.ios.voice.model")
        library.refresh()
        XCTAssertEqual(library.effectiveId, "en_US-hfc_female-medium")
        XCTAssertEqual(library.engine, "neural")
    }

    func testAnotherLanguageFallsBackToSystem() throws {
        try makeVoice("fr_FR-siwis-medium")
        defaults.set("fr_FR-siwis-medium", forKey: "app.vela.ios.voice.model")
        let library = VoiceLibrary(root: root, defaults: defaults)
        // The test process runs with English navigation strings.
        XCTAssertEqual(library.engine, "system")
        XCTAssertEqual(library.fallbackReason, "voice-language")
    }

    func testUnsafeArchiveEntryIsRejected() throws {
        var entries: [TarEntry] = []
        let info = TarEntryInfo(name: "../escape", type: .regular)
        entries.append(TarEntry(info: info, data: Data("evil".utf8)))
        let tar = TarContainer.create(from: entries)
        XCTAssertThrowsError(
            try VoiceModelInstaller.extractTar(tar, id: "en_US-hfc_female-medium", into: root))
    }

    func testExtractionStripsTopFolderAndValidatesModel() throws {
        var entries: [TarEntry] = []
        let top = TarEntryInfo(name: "vits-piper-en_US-hfc_female-medium", type: .directory)
        entries.append(TarEntry(info: top, data: nil))
        let tokensInfo = TarEntryInfo(
            name: "vits-piper-en_US-hfc_female-medium/tokens.txt", type: .regular)
        entries.append(TarEntry(info: tokensInfo, data: Data("tokens".utf8)))
        let dataInfo = TarEntryInfo(
            name: "vits-piper-en_US-hfc_female-medium/espeak-ng-data", type: .directory)
        entries.append(TarEntry(info: dataInfo, data: nil))
        let dictInfo = TarEntryInfo(
            name: "vits-piper-en_US-hfc_female-medium/espeak-ng-data/en_dict", type: .regular)
        entries.append(TarEntry(info: dictInfo, data: Data("dict".utf8)))
        let modelInfo = TarEntryInfo(
            name: "vits-piper-en_US-hfc_female-medium/en_US-hfc_female-medium.onnx", type: .regular)
        let model = Data(count: 1_100_000)
        entries.append(TarEntry(info: modelInfo, data: model))
        let data = TarContainer.create(from: entries)
        let compressed = BZip2.compress(data: data)
        let tar = try BZip2.decompress(data: compressed)

        try VoiceModelInstaller.extractTar(tar, id: "en_US-hfc_female-medium", into: root)
        XCTAssertTrue(VoiceLayout.isComplete(id: "en_US-hfc_female-medium", root: root))
        XCTAssertEqual(
            try Data(contentsOf: VoiceLayout.directory(id: "en_US-hfc_female-medium", root: root)
                .appendingPathComponent("tokens.txt")),
            Data("tokens".utf8))
    }
}

/// VO-CONTROL: the shared speed presets, the persisted guidance volume and the levelled gain.
final class VoiceControlTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "vela-voice-control-\(UUID().uuidString)")
    }

    func testSpeedPresetsMapToAppleRates() {
        XCTAssertEqual(GuidanceSpeed.appleRate(1.0), AVSpeechUtteranceDefaultSpeechRate, accuracy: 0.0001)
        XCTAssertEqual(GuidanceSpeed.appleRate(0.8), AVSpeechUtteranceDefaultSpeechRate * 0.8, accuracy: 0.0001)
        XCTAssertEqual(GuidanceSpeed.appleRate(2.0), AVSpeechUtteranceMaximumSpeechRate, accuracy: 0.0001)
        XCTAssertEqual(GuidanceSpeed.appleRate(0.5), AVSpeechUtteranceDefaultSpeechRate * 0.5, accuracy: 0.0001)
    }

    func testSpeedStaysInsideTheAndroidRange() {
        XCTAssertEqual(GuidanceSpeed.clamp(0.1), GuidanceSpeed.minimum)
        XCTAssertEqual(GuidanceSpeed.clamp(9), GuidanceSpeed.maximum)
        XCTAssertEqual(GuidanceSpeed.clamp(.nan), GuidanceSpeed.defaultMultiplier)
        XCTAssertEqual(GuidanceSpeed.clamp(0.8), 0.8)
    }

    func testVolumeAndSpeedPersist() {
        let first = VoiceControlSettings(defaults: defaults)
        XCTAssertEqual(first.tier, .normal)
        XCTAssertEqual(first.rate, GuidanceSpeed.defaultMultiplier, accuracy: 0.0001)

        first.setTier(.louder)
        first.setRate(1.3)
        let second = VoiceControlSettings(defaults: defaults)
        XCTAssertEqual(second.tier, .louder)
        XCTAssertEqual(second.tier.rawValue, 1.6, accuracy: 0.0001)
        XCTAssertEqual(second.rate, 1.3, accuracy: 0.0001)
        XCTAssertEqual(second.speedLabel, "1.30x")
    }

    func testSpeedStepperStepsAndClamps() {
        let control = VoiceControlSettings(defaults: defaults)
        control.setRate(2.0)
        control.stepRate(GuidanceSpeed.step)
        XCTAssertEqual(control.rate, GuidanceSpeed.maximum, accuracy: 0.0001)
        control.setRate(0.7)
        control.stepRate(-GuidanceSpeed.step)
        XCTAssertEqual(control.rate, 0.6, accuracy: 0.0001)
    }

    func testAppleVolumeCapsTheLoudTiers() {
        XCTAssertEqual(GuidanceVolumeTier.softer.appleVolume, 0.6, accuracy: 0.0001)
        XCTAssertEqual(GuidanceVolumeTier.normal.appleVolume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(GuidanceVolumeTier.louder.appleVolume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(GuidanceVolumeTier.loudest.appleVolume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(GuidanceVolumeTier.nearest(1.55), .louder)
    }

    func testLevelBringsAQuietVoiceUpAndKeepsALoudOne() {
        XCTAssertEqual(GuidanceLevel.gain(voiceRMS: GuidanceLevel.targetRMS, tier: 1), 1, accuracy: 0.001)
        XCTAssertEqual(GuidanceLevel.gain(voiceRMS: GuidanceLevel.targetRMS / 2, tier: 1), 2, accuracy: 0.001)
        XCTAssertEqual(GuidanceLevel.gain(voiceRMS: 0.001, tier: 1), GuidanceLevel.maxLift, accuracy: 0.001)
        // An already-loud voice is never lowered, only scaled by the tier.
        XCTAssertEqual(GuidanceLevel.gain(voiceRMS: 0.5, tier: 1.6), 1.6, accuracy: 0.001)
        XCTAssertEqual(GuidanceLevel.gain(voiceRMS: 0, tier: 2.2), 2.2, accuracy: 0.001)
    }

    func testLevelLimitNeverExceedsFullScale() {
        XCTAssertEqual(GuidanceLevel.limit(0.5), 0.5, accuracy: 0.0001)
        // The curve reaches full scale only in the limit, so a huge input can round to 1.0.
        XCTAssertLessThanOrEqual(GuidanceLevel.limit(3), 1.0)
        XCTAssertGreaterThan(GuidanceLevel.limit(3), GuidanceLevel.knee)
        XCTAssertEqual(GuidanceLevel.limit(-3), -GuidanceLevel.limit(3), accuracy: 0.0001)
    }

    func testMeterKeepsTheMeanAndIgnoresPauses() {
        var meter = GuidanceLevel.Meter()
        meter.add([Float](repeating: 0.001, count: 100)) // a pause, below minPeak
        XCTAssertEqual(meter.count, 0)
        meter.add([0.2, -0.2, 0.2, -0.2])
        XCTAssertEqual(meter.count, 4)
        XCTAssertEqual(meter.rms, 0.2, accuracy: 0.0001)
        XCTAssertEqual(GuidanceLevel.Meter(encoded: meter.encoded), meter)
        XCTAssertEqual(GuidanceLevel.Meter(encoded: "bad"), GuidanceLevel.Meter())
    }

    func testMeterPersistsPerVoice() {
        let control = VoiceControlSettings(defaults: defaults)
        var meter = GuidanceLevel.Meter()
        meter.add([0.2, -0.2, 0.2, -0.2])
        control.store(meter, for: "en_US-hfc_female-medium")
        let again = VoiceControlSettings(defaults: defaults)
        XCTAssertEqual(again.meter(for: "en_US-hfc_female-medium").rms, 0.2, accuracy: 0.0001)
        XCTAssertEqual(again.meter(for: "fr_FR-siwis-medium").count, 0)
    }
}

/// The spoken-form lexicon, with the same expectations as `SpeechTextTest` in `:core-common`.
final class GuidanceSpeechTests: XCTestCase {
    private func speak(_ text: String, _ language: String = "en") -> String {
        SpeechText.shared.forSpeech(text: text, language: language)
    }

    func testStreetAbbreviations() {
        XCTAssertEqual(speak("Turn right onto Main St"), "Turn right onto Main Street")
        XCTAssertEqual(speak("Turn left onto Market Ave", "en-US"), "Turn left onto Market Avenue")
        XCTAssertEqual(speak("Continue on Elm Blvd", "en_GB"), "Continue on Elm Boulevard")
        XCTAssertEqual(speak("Bear N on Oak Pkwy"), "Bear North on Oak Parkway")
    }

    func testRefsNumbersUnitsAndClock() {
        XCTAssertEqual(speak("I-80 E"), "Interstate 80 East")
        XCTAssertEqual(speak("CA-99"), "State Route 99")
        XCTAssertEqual(speak("128th St"), "one twenty eighth Street")
        XCTAssertEqual(speak("5:49 PM"), "five forty nine PM")
        XCTAssertEqual(speak("Walk 10 min"), "Walk 10 minutes")
        XCTAssertEqual(speak("0.4 mi"), "0.4 miles")
        XCTAssertEqual(speak("2 km"), "2 kilometers")
    }

    func testAnotherLanguageIsUntouched() {
        XCTAssertEqual(speak("Tournez à droite sur Main St", "fr"), "Tournez à droite sur Main St")
        XCTAssertEqual(speak("Rechts auf die Hauptstraße", "de"), "Rechts auf die Hauptstraße")
        XCTAssertEqual(speak("128th St", "he"), "128th St")
    }
}

/// The bundled place-name dictionary replaces a voice's own `en_dict` once per version and keeps
/// the stock file for a clean reinstall.
final class PlaceDictionaryTests: XCTestCase {
    private var data: URL!

    override func setUpWithError() throws {
        data = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-dict-tests-\(UUID().uuidString)")
            .appendingPathComponent("espeak-ng-data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("stock".utf8).write(to: data.appendingPathComponent("en_dict"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: data.deletingLastPathComponent())
    }

    private func contents(_ name: String) -> String? {
        try? String(contentsOf: data.appendingPathComponent(name), encoding: .utf8)
    }

    func testInstallsOncePerVersionAndKeepsTheStock() throws {
        XCTAssertTrue(PlaceDictionary.install(
            voiceID: "en_US-hfc_female-medium", dataDir: data.path,
            dictionary: Data("vela-v1".utf8), version: "v1"))
        XCTAssertEqual(contents("en_dict"), "vela-v1")
        XCTAssertEqual(contents("en_dict.stock"), "stock")
        XCTAssertEqual(contents("en_dict.vela"), "v1")

        XCTAssertFalse(PlaceDictionary.install(
            voiceID: "en_US-hfc_female-medium", dataDir: data.path,
            dictionary: Data("vela-v1-again".utf8), version: "v1"))
        XCTAssertEqual(contents("en_dict"), "vela-v1")

        XCTAssertTrue(PlaceDictionary.install(
            voiceID: "en_US-hfc_female-medium", dataDir: data.path,
            dictionary: Data("vela-v2".utf8), version: "v2"))
        XCTAssertEqual(contents("en_dict"), "vela-v2")
        XCTAssertEqual(contents("en_dict.stock"), "stock")
    }

    func testOnlyEnglishVoicesAreTouched() {
        XCTAssertFalse(PlaceDictionary.install(
            voiceID: "fr_FR-siwis-medium", dataDir: data.path,
            dictionary: Data("vela".utf8), version: "v1"))
        XCTAssertEqual(contents("en_dict"), "stock")
        XCTAssertFalse(PlaceDictionary.install(
            voiceID: "en_US-hfc_female-medium", dataDir: data.path,
            dictionary: Data(), version: "v1"))
    }

    func testMissingDataDirectoryFailsQuietly() {
        XCTAssertFalse(PlaceDictionary.install(
            voiceID: "en_US-hfc_female-medium", dataDir: data.appendingPathComponent("absent").path,
            dictionary: Data("vela".utf8), version: "v1"))
    }
}

final class NeuralSynthesisTests: XCTestCase {
    func testPiperModelSynthesizesDecodableAudio() throws {
        guard let fixture = Bundle.main.url(forResource: "VoiceFixture", withExtension: nil) else {
            throw XCTSkip("no VoiceFixture in the test app; scripts/ios/ci-ipa.sh injects one")
        }
        let id = "en_US-hfc_female-medium"
        guard VoiceLayout.isComplete(id: id, root: fixture) else {
            throw XCTSkip("VoiceFixture is incomplete")
        }
        let files = SherpaTts.VoiceFiles(
            id: id,
            model: VoiceLayout.modelPath(id: id, root: fixture),
            tokens: VoiceLayout.tokensPath(id: id, root: fixture),
            dataDir: VoiceLayout.dataPath(id: id, root: fixture))
        let tts = SherpaTts()
        guard let rendered = tts.render(text: "In a quarter mile, turn right onto Main Street.", files: files) else {
            XCTFail("sherpa-onnx returned no audio")
            return
        }
        XCTAssertGreaterThan(rendered.samples.count, 2_000)
        XCTAssertEqual(rendered.rate, 22_050)
        XCTAssertGreaterThan(rendered.samples.map { abs($0) }.max() ?? 0, 0.01)

        // Write the same PCM as a WAV and decode it again: catches a runtime that only returns
        // silence or a broken sample rate.
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("vela-voice-smoke.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(rendered.rate), channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rendered.samples.count))!
        buffer.frameLength = AVAudioFrameCount(rendered.samples.count)
        rendered.samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: rendered.samples.count)
        }
        var output: AVAudioFile? = try AVAudioFile(forWriting: wav, settings: format.settings)
        try output?.write(from: buffer)
        output = nil
        let file = try AVAudioFile(forReading: wav)
        XCTAssertEqual(Int(file.fileFormat.sampleRate), 22_050)
        XCTAssertGreaterThan(file.length, 2_000)
        print("SEAM_TEST VOICE_SYNTH samples=\(rendered.samples.count) rate=\(rendered.rate) wav_frames=\(file.length)")
        try? FileManager.default.removeItem(at: wav)
    }
}
