import AVFoundation
import XCTest
@testable import Vela
import SWCompression

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
