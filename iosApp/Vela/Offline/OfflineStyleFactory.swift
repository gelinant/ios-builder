import Foundation

/// Builds the offline Liberty variant. The PMTiles source itself is added after style load under a
/// fresh id, matching Android's workaround for local sources that otherwise never pass z0.
enum OfflineStyleFactory {
    static let sourceId = "vela-basemap"

    static func makeStyle(archivePath: String, glyphsPath: String, spritesPath: String) throws -> URL {
        guard let asset = resource("liberty-roboto", "json") else { throw CocoaError(.fileReadNoSuchFile) }
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: asset)) as! [String: Any]
        var sources = root["sources"] as? [String: Any] ?? [:]
        sources.removeValue(forKey: "ne2_shaded")
        sources.removeValue(forKey: "openmaptiles")
        root["sources"] = sources

        root["layers"] = (root["layers"] as? [[String: Any]] ?? []).compactMap {
            (original: [String: Any]) -> [String: Any]? in
            var layer = original
            if layer["source"] as? String == "ne2_shaded" { return nil }
            if layer["source"] as? String == "openmaptiles" { layer["source"] = sourceId }
            if var layout = layer["layout"] as? [String: Any],
               let fonts = layout["text-font"] as? [String] {
                layout["text-font"] = fonts.map(stackName)
                layer["layout"] = layout
            }
            return layer
        }
        root["glyphs"] = URL(fileURLWithPath: glyphsPath).absoluteString + "/{fontstack}/{range}.pbf"
        try copySprites(to: spritesPath)
        root["sprite"] = URL(fileURLWithPath: spritesPath).appendingPathComponent("ofm").absoluteString

        let json = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let token = archivePath + "|" + String(fileSize(archivePath)) + "|" + String(fileDate(archivePath))
        let output = URL(fileURLWithPath: spritesPath)
            .appendingPathComponent("offline-style-\(fnv1a(token)).json")
        try json.write(to: output, options: .atomic)
        return output
    }

    static func remoteURLCount(in styleURL: URL) -> Int {
        guard let data = try? Data(contentsOf: styleURL),
              let root = try? JSONSerialization.jsonObject(with: data) else { return -1 }
        return remoteStrings(root)
    }

    static func resource(_ name: String, _ ext: String) -> URL? {
        for directory in [nil, "Resources", "Resources/styles", "Resources/sprites"] as [String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: directory) {
                return url
            }
        }
        return nil
    }

    private static func copySprites(to directory: String) throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["ofm.json", "ofm.png", "ofm@2x.json", "ofm@2x.png"] {
            let target = root.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { continue }
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            guard let source = resource(parts[0], parts[1]) else { throw CocoaError(.fileReadNoSuchFile) }
            try fm.copyItem(at: source, to: target)
        }
    }

    private static func stackName(_ font: String) -> String {
        switch font {
        case "Roboto Regular": return "Noto Sans Regular"
        case "Roboto Italic": return "Noto Sans Italic"
        case "Roboto Medium", "Roboto Bold": return "Noto Sans Bold"
        default: return font
        }
    }

    private static func remoteStrings(_ value: Any) -> Int {
        if let text = value as? String {
            return text.hasPrefix("https://") || text.hasPrefix("http://") ? 1 : 0
        }
        if let array = value as? [Any] { return array.reduce(0) { $0 + remoteStrings($1) } }
        if let object = value as? [String: Any] { return object.values.reduce(0) { $0 + remoteStrings($1) } }
        return 0
    }

    private static func fileSize(_ path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func fileDate(_ path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let date = attrs?[.modificationDate] as? Date
        return Int64((date?.timeIntervalSince1970 ?? 0) * 1000)
    }

    private static func fnv1a(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
