import Foundation

/// The English dictionary a Piper voice reads with: eSpeak NG's own plus about 3,500 place names
/// said the local way, built from `tools/pronunciation/places.tsv` by
/// `scripts/build-espeak-dict.sh`. The same asset Android installs (`PlaceDictionary.kt`), copied
/// into the app bundle as `vela-en_dict`; no audio and no per-voice model is shipped.
///
/// A voice's stock dictionary is kept beside the replacement as `en_dict.stock`, and the installed
/// version is recorded in `en_dict.vela`, so a reinstall is idempotent and a voice update can be
/// detected. Only complete English (`en_`) voices are touched. The Apple voice never reads this
/// file; it applies to the downloadable Piper voices only.
enum PlaceDictionary {
    static let assetName = "vela-en_dict"
    static let versionAssetName = "vela-en_dict"
    static let stockName = "en_dict.stock"
    static let markerName = "en_dict.vela"

    /// Install the bundled dictionary into [voiceID]'s `espeak-ng-data` at [dataDir]. A failure
    /// leaves the voice's own dictionary in place; the voice still speaks.
    @discardableResult
    static func install(voiceID: String, dataDir: String, bundle: Bundle = .main) -> Bool {
        guard voiceID.hasPrefix("en_"),
              let dictionary = bundle.url(forResource: assetName, withExtension: nil),
              let versionURL = bundle.url(forResource: versionAssetName, withExtension: "version"),
              let data = try? Data(contentsOf: dictionary),
              let version = try? String(contentsOf: versionURL, encoding: .utf8) else {
            return false
        }
        return install(
            voiceID: voiceID, dataDir: dataDir, dictionary: data,
            version: version.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The testable core. Returns true when this call changed the installed dictionary.
    @discardableResult
    static func install(voiceID: String, dataDir: String, dictionary: Data, version: String) -> Bool {
        guard voiceID.hasPrefix("en_"), !dictionary.isEmpty, !version.isEmpty else { return false }
        let fm = FileManager.default
        let data = URL(fileURLWithPath: dataDir, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: data.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let target = data.appendingPathComponent("en_dict")
        let stock = data.appendingPathComponent(stockName)
        let marker = data.appendingPathComponent(markerName)

        if let installed = try? String(contentsOf: marker, encoding: .utf8),
           installed.trimmingCharacters(in: .whitespacesAndNewlines) == version {
            return false
        }
        if !fm.fileExists(atPath: stock.path), fm.fileExists(atPath: target.path) {
            try? fm.copyItem(at: target, to: stock)
        }
        do {
            // Atomic write: a crash mid-install leaves the previous dictionary intact.
            try dictionary.write(to: target, options: .atomic)
            try version.write(to: marker, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
