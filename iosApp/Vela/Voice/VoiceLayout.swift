import Foundation
import VelaCore

/// The on-disk voice store under Application Support. The installed set is derived from the
/// filesystem, never from a mutable pref, so a crashed or partial download self-heals: an
/// incomplete directory is simply not offered. Layout per voice:
///
///     Application Support/VelaVoices/<id>/
///       <id>.onnx
///       tokens.txt
///       espeak-ng-data/
enum VoiceLayout {
    static let directoryName = "VelaVoices"

    static func storeRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func directory(id: String, root: URL = storeRoot()) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    static func modelPath(id: String, root: URL = storeRoot()) -> String {
        directory(id: id, root: root).appendingPathComponent("\(id).onnx").path
    }

    static func tokensPath(id: String, root: URL = storeRoot()) -> String {
        directory(id: id, root: root).appendingPathComponent("tokens.txt").path
    }

    static func dataPath(id: String, root: URL = storeRoot()) -> String {
        directory(id: id, root: root).appendingPathComponent("espeak-ng-data").path
    }

    /// A complete voice needs the model, the token table and the eSpeak data directory. A file
    /// left by an interrupted extraction (or a zero-byte model) is rejected.
    static func isComplete(id: String, root: URL = storeRoot()) -> Bool {
        let dir = directory(id: id, root: root)
        let fm = FileManager.default
        let model = dir.appendingPathComponent("\(id).onnx")
        let tokens = dir.appendingPathComponent("tokens.txt")
        let data = dir.appendingPathComponent("espeak-ng-data", isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: model.path, isDirectory: &isDir), !isDir.boolValue,
              let attrs = try? fm.attributesOfItem(atPath: model.path),
              (attrs[.size] as? NSNumber)?.int64Value ?? 0 > 1_000_000,
              fm.fileExists(atPath: tokens.path),
              fm.fileExists(atPath: data.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        return true
    }

    /// Voice ids with a complete directory, sorted for a stable UI and deterministic tests.
    static func installed(root: URL = storeRoot()) -> [String] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return names
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { isComplete(id: $0, root: root) }
            .sorted()
    }
}
