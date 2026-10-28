import Foundation

/// Builds the map style document at runtime from a generated bundle variant. The look palettes are
/// already baked into `style-<look>.json` by `scripts/ios/gen-map-styles.py`; this type applies the
/// per-launch choices (name mode, house-number gate) and writes a small local file. MapLibre then
/// loads that file, so no style document is ever fetched from a server.
enum MapStyleBuilder {
    private static let nameFields: Set<String> = [
        "name", "name:en", "name_en", "name:latin", "name:nonlatin",
    ]

    private static let nonLatinUILanguages: Set<String> = [
        "he", "iw", "ar", "fa", "ur", "ru", "uk", "bg", "sr", "mk", "el",
        "zh", "ja", "ko", "th", "hi",
    ]

    /// The generated document for [options], with the selected name mode and house-number gate.
    static func root(options: MapStyleOptions) throws -> [String: Any] {
        guard let url = resource(options.styleResource) else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        apply(options, to: &root)
        return root
    }

    /// The raw bundled document, for callers that only need the look's palette (the trip mini map).
    static func bundledStyleURL(options: MapStyleOptions = MapStyleSettings.current()) -> URL? {
        resource(options.styleResource)
    }

    /// A cached local style file for the online map.
    static func onlineStyleURL(options: MapStyleOptions = MapStyleSettings.current()) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VelaMapStyles", isDirectory: true)
        let url = directory.appendingPathComponent("\(options.cacheToken)-\(styleToken(options)).json")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let root = try root(options: options)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Applies the runtime choices to a style document already in memory. The offline factory calls
    /// this before swapping the remote source for the downloaded archive.
    static func apply(_ options: MapStyleOptions, to root: inout [String: Any]) {
        guard var layers = root["layers"] as? [[String: Any]] else { return }
        let expression = nameExpression(options)
        for index in layers.indices {
            var layer = layers[index]
            if var layout = layer["layout"] as? [String: Any],
               let field = layout["text-field"], referencesName(field) {
                layout["text-field"] = fieldExpression(for: layer, options: options,
                                                       fallback: expression)
                layer["layout"] = layout
            }
            if layer["id"] as? String == "vela-housenumber" {
                layer["minzoom"] = options.houseNumbers.minZoom
                var paint = layer["paint"] as? [String: Any] ?? [:]
                let gate = options.houseNumbers.minZoom
                let opacity: [Any] = [
                    "interpolate", ["linear"], ["zoom"],
                    gate, 0, gate + 0.6, 1,
                ]
                paint["text-opacity"] = opacity
                layer["paint"] = paint
            }
            layers[index] = layer
        }
        root["layers"] = layers
    }

    private static func fieldExpression(for layer: [String: Any], options: MapStyleOptions,
                                        fallback: [Any]) -> Any {
        // The mode expression is the same for every feature; only a line label changes the
        // separator of local + English, because a label along a line cannot break.
        if options.names == .localEnglish && latinUI(options.language),
           (layer["layout"] as? [String: Any])?["symbol-placement"] as? String != "line" {
            return ["case",
                    ["all", ["has", "name:en"], ["!=", ["get", "name:en"], ["get", "name"]]],
                    ["concat", ["get", "name"], "\n", ["get", "name:en"]],
                    ["get", "name"]]
        }
        return fallback
    }

    /// Android's `roadLabelTextField`: the local (or app-language) name, the English name or the
    /// romanized `name:latin`, by the chosen mode. A non-Latin UI keeps the local script.
    private static func nameExpression(_ options: MapStyleOptions) -> [Any] {
        guard latinUI(options.language) else { return ["get", "name"] }
        switch options.names {
        case .local:
            return ["get", "name"]
        case .englishLocal:
            return ["coalesce", ["get", "name:en"], ["get", "name"]]
        case .localEnglish:
            return ["case",
                    ["all", ["has", "name:en"], ["!=", ["get", "name:en"], ["get", "name"]]],
                    ["concat", ["get", "name"], "  ", ["get", "name:en"]],
                    ["get", "name"]]
        case .englishLatin:
            var fields: [Any] = []
            if let tag = languageTag(options.language) {
                fields.append(["get", "name:\(tag)"])
            }
            fields.append(["get", "name:en"])
            fields.append(["get", "name:latin"])
            fields.append(["get", "name"])
            var expression: [Any] = ["coalesce"]
            expression.append(contentsOf: fields)
            return expression
        }
    }

    private static func latinUI(_ language: String) -> Bool {
        !nonLatinUILanguages.contains(languageCode(language))
    }

    /// Android still reports Hebrew as `iw` while the tiles carry `name:he`. Chinese splits by
    /// script, so a Traditional reader asks for `name:zh-Hant` before `name:zh`.
    private static func languageTag(_ language: String) -> String? {
        let lower = language.lowercased()
        if lower.hasPrefix("zh") && (lower.contains("hant") || lower.contains("tw")
            || lower.contains("hk") || lower.contains("mo")) {
            return "zh-Hant"
        }
        let code = languageCode(lower)
        if code == "en" || code.isEmpty { return nil }
        if code == "iw" { return "he" }
        return code
    }

    private static func languageCode(_ language: String) -> String {
        guard let first = language.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" }).first else { return "" }
        return String(first)
    }

    private static func referencesName(_ value: Any) -> Bool {
        if let text = value as? String { return nameFields.contains(text) }
        if let array = value as? [Any] { return array.contains { referencesName($0) } }
        if let object = value as? [String: Any] {
            return object.values.contains { referencesName($0) }
        }
        return false
    }

    static func resource(_ name: String) -> URL? {
        for directory in [nil, "Resources", "Resources/styles"] as [String?] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json",
                                         subdirectory: directory) {
                return url
            }
        }
        return nil
    }

    /// The generated file changes only when the base is regenerated; including its size and date
    /// keeps an app update from loading a stale cache file.
    private static func styleToken(_ options: MapStyleOptions) -> String {
        guard let url = resource(options.styleResource),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "0"
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attributes[.modificationDate] as? Date).map {
            Int64($0.timeIntervalSince1970 * 1000)
        } ?? 0
        return "\(size)-\(date)"
    }
}
