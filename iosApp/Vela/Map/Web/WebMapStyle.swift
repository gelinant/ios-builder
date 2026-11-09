import CoreGraphics
import Foundation
import UIKit

// The style model of the main map. Swift holds the authoritative copy of every source, layer and
// image; each mutation is mirrored to MapLibre GL JS as one command. The API is the subset of
// MapLibre Native's `MLNStyle` the app uses, so the layer classes did not change.

struct MLNTileSourceOption: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let tileSize = MLNTileSourceOption(rawValue: "MLNTileSourceOptionTileSize")
    static let minimumZoomLevel = MLNTileSourceOption(rawValue: "MLNTileSourceOptionMinimumZoomLevel")
    static let maximumZoomLevel = MLNTileSourceOption(rawValue: "MLNTileSourceOptionMaximumZoomLevel")
    static let attributionInfos = MLNTileSourceOption(rawValue: "MLNTileSourceOptionAttributionInfos")
    static let attributionHTMLString = MLNTileSourceOption(rawValue: "MLNTileSourceOptionAttributionHTMLString")
    static let coordinateBounds = MLNTileSourceOption(rawValue: "MLNTileSourceOptionCoordinateBounds")
    static let tileCoordinateSystem = MLNTileSourceOption(rawValue: "MLNTileSourceOptionTileCoordinateSystem")
    static let demEncoding = MLNTileSourceOption(rawValue: "MLNTileSourceOptionDEMEncoding")
}

struct MLNShapeSourceOption: RawRepresentable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let clustered = MLNShapeSourceOption(rawValue: "MLNShapeSourceOptionClustered")
    static let clusterRadius = MLNShapeSourceOption(rawValue: "MLNShapeSourceOptionClusterRadius")
    static let maximumZoomLevelForClustering = MLNShapeSourceOption(
        rawValue: "MLNShapeSourceOptionMaximumZoomLevelForClustering")
    static let maximumZoomLevel = MLNShapeSourceOption(rawValue: "MLNShapeSourceOptionMaximumZoomLevel")
    static let buffer = MLNShapeSourceOption(rawValue: "MLNShapeSourceOptionBuffer")
    static let simplificationTolerance = MLNShapeSourceOption(
        rawValue: "MLNShapeSourceOptionSimplificationTolerance")
    static let lineDistanceMetrics = MLNShapeSourceOption(rawValue: "MLNShapeSourceOptionLineDistanceMetrics")
}

enum MLNDEMEncoding: UInt {
    case mapbox = 0
    case terrarium = 1
}

enum MLNTileCoordinateSystem: UInt {
    case XYZ = 0
    case TMS = 1
}

final class MLNAttributionInfo: NSObject {
    let title: NSAttributedString
    let url: URL?

    init(title: NSAttributedString, url: URL?) {
        self.title = title
        self.url = url
    }
}

struct MLNTransition {
    var duration: TimeInterval
    var delay: TimeInterval
}

func MLNTransitionMake(_ duration: TimeInterval, _ delay: TimeInterval) -> MLNTransition {
    MLNTransition(duration: duration, delay: delay)
}

private func optionNumber(_ value: Any?) -> Double? {
    switch value {
    case let number as NSNumber: return number.doubleValue
    case let int as Int: return Double(int)
    case let double as Double: return double
    case let float as Float: return Double(float)
    default: return nil
    }
}

// MARK: - URLs the page can load

/// The page runs with the OpenFreeMap origin, so its style, tiles, sprites and glyphs are plain
/// same-origin fetches. Every other URL goes through a MapLibre protocol answered by Swift:
/// local files, PMTiles archives and remote hosts that send no CORS header (WebMapResources).
enum WebMapURLs {
    static let pageOrigin = "https://tiles.openfreemap.org/"

    static func page(_ url: String) -> String {
        if url.hasPrefix(pageOrigin) { return url }
        if url.hasPrefix("https://") { return "vela-nets://" + url.dropFirst("https://".count) }
        if url.hasPrefix("http://") { return "vela-net://" + url.dropFirst("http://".count) }
        if url.hasPrefix("file://") { return "vela-file://" + url.dropFirst("file://".count) }
        if url.hasPrefix("/") { return "vela-file://" + url }
        return url
    }

    /// The source as the page needs it. A `pmtiles://` source becomes a tile template on the
    /// `vela-pmtiles` protocol with the archive's own zoom range.
    static func source(_ spec: [String: Any]) -> [String: Any] {
        var out = spec
        if let url = spec["url"] as? String {
            if url.hasPrefix("pmtiles://") {
                let rest = String(url.dropFirst("pmtiles://".count))
                let path = rest.hasPrefix("file://")
                    ? (URL(string: rest)?.path ?? String(rest.dropFirst("file://".count)))
                    : rest
                if let archive = WebMapResources.shared.registerArchive(path: path) {
                    out.removeValue(forKey: "url")
                    out["tiles"] = ["vela-pmtiles://\(archive.key)/{z}/{x}/{y}"]
                    out["minzoom"] = archive.minZoom
                    out["maxzoom"] = archive.maxZoom
                }
            } else {
                out["url"] = page(url)
            }
        }
        if let tiles = spec["tiles"] as? [String] {
            out["tiles"] = tiles.map(page)
        }
        if let data = spec["data"] as? String {
            out["data"] = page(data)
        }
        return out
    }
}

// MARK: - Sources

class MLNSource: NSObject {
    let identifier: String
    var spec: [String: Any]
    weak var style: MLNStyle?

    init(identifier: String, spec: [String: Any]) {
        self.identifier = identifier
        self.spec = spec
        super.init()
    }

    func pageSpec() -> [String: Any] {
        WebMapURLs.source(spec)
    }

    static func make(identifier: String, spec: [String: Any]) -> MLNSource {
        switch spec["type"] as? String {
        case "vector": return MLNVectorTileSource(identifier: identifier, spec: spec)
        case "raster": return MLNRasterTileSource(identifier: identifier, spec: spec)
        case "raster-dem": return MLNRasterDEMSource(identifier: identifier, spec: spec)
        case "geojson": return MLNShapeSource(identifier: identifier, spec: spec)
        default: return MLNSource(identifier: identifier, spec: spec)
        }
    }

    fileprivate static func tileSpec(type: String, templates: [String],
                                     options: [MLNTileSourceOption: Any]?) -> [String: Any] {
        var spec: [String: Any] = ["type": type, "tiles": templates]
        let options = options ?? [:]
        if let size = optionNumber(options[.tileSize]) { spec["tileSize"] = Int(size) }
        if let minimum = optionNumber(options[.minimumZoomLevel]) { spec["minzoom"] = minimum }
        if let maximum = optionNumber(options[.maximumZoomLevel]) { spec["maxzoom"] = maximum }
        if let system = optionNumber(options[.tileCoordinateSystem]),
           UInt(system) == MLNTileCoordinateSystem.TMS.rawValue {
            spec["scheme"] = "tms"
        }
        if let encoding = optionNumber(options[.demEncoding]) {
            spec["encoding"] = UInt(encoding) == MLNDEMEncoding.terrarium.rawValue ? "terrarium" : "mapbox"
        }
        if let infos = options[.attributionInfos] as? [MLNAttributionInfo], !infos.isEmpty {
            spec["attribution"] = infos.map(\.title.string).joined(separator: " ")
        } else if let html = options[.attributionHTMLString] as? String {
            spec["attribution"] = html
        }
        return spec
    }
}

class MLNTileSource: MLNSource {
    var attributionInfos: [MLNAttributionInfo] {
        guard let text = spec["attribution"] as? String, !text.isEmpty else { return [] }
        return [MLNAttributionInfo(title: NSAttributedString(string: text), url: nil)]
    }

    var configurationURL: URL? {
        (spec["url"] as? String).flatMap(URL.init(string:))
    }
}

class MLNVectorTileSource: MLNTileSource {
    convenience init(identifier: String, configurationURLString: String) {
        self.init(identifier: identifier, spec: ["type": "vector", "url": configurationURLString])
    }

    convenience init(identifier: String, configurationURL: URL) {
        self.init(identifier: identifier, spec: ["type": "vector", "url": configurationURL.absoluteString])
    }

    convenience init(identifier: String, tileURLTemplates: [String], options: [MLNTileSourceOption: Any]?) {
        self.init(identifier: identifier,
                  spec: MLNSource.tileSpec(type: "vector", templates: tileURLTemplates, options: options))
    }
}

class MLNRasterTileSource: MLNTileSource {
    fileprivate class var sourceType: String { "raster" }

    convenience init(identifier: String, tileURLTemplates: [String], options: [MLNTileSourceOption: Any]?) {
        var spec = MLNSource.tileSpec(type: Self.sourceType, templates: tileURLTemplates, options: options)
        if spec["tileSize"] == nil { spec["tileSize"] = 512 }
        self.init(identifier: identifier, spec: spec)
    }

    convenience init(identifier: String, configurationURL: URL, tileSize: CGFloat) {
        self.init(identifier: identifier, spec: [
            "type": Self.sourceType, "url": configurationURL.absoluteString, "tileSize": Int(tileSize),
        ])
    }
}

final class MLNRasterDEMSource: MLNRasterTileSource {
    fileprivate override class var sourceType: String { "raster-dem" }
}

/// A GeoJSON source fed with shapes. Setting [shape] replaces the page's data in one command; an
/// unchanged document is not sent again.
class MLNShapeSource: MLNSource {
    private var lastSentData: Data?

    var shape: MLNShape? {
        didSet {
            spec["data"] = GeoJSON.featureCollection(shape)
            style?.sourceDataChanged(self)
        }
    }

    var url: URL? {
        get { (spec["data"] as? String).flatMap(URL.init(string:)) }
        set {
            spec["data"] = newValue?.absoluteString ?? GeoJSON.featureCollection(nil)
            style?.sourceDataChanged(self)
        }
    }

    convenience init(identifier: String, shape: MLNShape?, options: [MLNShapeSourceOption: Any]? = nil) {
        self.init(identifier: identifier, spec: MLNShapeSource.baseSpec(options))
        self.shape = shape
    }

    convenience init(identifier: String, features: [MLNShape & MLNFeature],
                     options: [MLNShapeSourceOption: Any]? = nil) {
        self.init(identifier: identifier, shape: MLNShapeCollectionFeature(shapes: features), options: options)
    }

    convenience init(identifier: String, shapes: [MLNShape], options: [MLNShapeSourceOption: Any]? = nil) {
        self.init(identifier: identifier, shape: MLNShapeCollection(shapes: shapes), options: options)
    }

    convenience init(identifier: String, url: URL, options: [MLNShapeSourceOption: Any]? = nil) {
        var spec = MLNShapeSource.baseSpec(options)
        spec["data"] = url.absoluteString
        self.init(identifier: identifier, spec: spec)
    }

    private static func baseSpec(_ options: [MLNShapeSourceOption: Any]?) -> [String: Any] {
        var spec: [String: Any] = ["type": "geojson", "data": GeoJSON.featureCollection(nil)]
        let options = options ?? [:]
        if let maximum = optionNumber(options[.maximumZoomLevel]) { spec["maxzoom"] = maximum }
        if let buffer = optionNumber(options[.buffer]) { spec["buffer"] = buffer }
        if let tolerance = optionNumber(options[.simplificationTolerance]) { spec["tolerance"] = tolerance }
        if let clustered = options[.clustered] as? Bool, clustered { spec["cluster"] = true }
        if let radius = optionNumber(options[.clusterRadius]) { spec["clusterRadius"] = radius }
        if let maximum = optionNumber(options[.maximumZoomLevelForClustering]) { spec["clusterMaxZoom"] = maximum }
        if let metrics = options[.lineDistanceMetrics] as? Bool, metrics { spec["lineMetrics"] = true }
        return spec
    }

    /// The data command, or nil when the page already holds this exact document.
    func dataCommandIfChanged() -> [String: Any]? {
        let data = spec["data"] ?? GeoJSON.featureCollection(nil)
        if let encoded = try? JSONSerialization.data(withJSONObject: ["d": data]) {
            if encoded == lastSentData { return nil }
            lastSentData = encoded
        }
        let pageData: Any = (data as? String).map(WebMapURLs.page) ?? data
        return ["op": "setData", "id": identifier, "data": pageData]
    }

    func markSent() {
        lastSentData = try? JSONSerialization.data(withJSONObject: ["d": spec["data"] ?? NSNull()])
    }
}

// MARK: - Layers

class MLNStyleLayer: NSObject {
    let identifier: String
    var spec: [String: Any]
    weak var style: MLNStyle?
    /// True while the layer exists in the page's map.
    var isLive = false

    required init(spec: [String: Any]) {
        identifier = spec["id"] as? String ?? UUID().uuidString
        self.spec = spec
        super.init()
    }

    fileprivate static func baseSpec(_ identifier: String, _ type: String, _ source: MLNSource?) -> [String: Any] {
        var spec: [String: Any] = ["id": identifier, "type": type]
        if let source { spec["source"] = source.identifier }
        return spec
    }

    static func make(spec: [String: Any]) -> MLNStyleLayer {
        let type: MLNStyleLayer.Type
        switch spec["type"] as? String {
        case "line": type = MLNLineStyleLayer.self
        case "fill": type = MLNFillStyleLayer.self
        case "fill-extrusion": type = MLNFillExtrusionStyleLayer.self
        case "circle": type = MLNCircleStyleLayer.self
        case "symbol": type = MLNSymbolStyleLayer.self
        case "raster": type = MLNRasterStyleLayer.self
        case "hillshade": type = MLNHillshadeStyleLayer.self
        case "background": type = MLNBackgroundStyleLayer.self
        case "heatmap": type = MLNHeatmapStyleLayer.self
        default: type = MLNStyleLayer.self
        }
        return type.init(spec: spec)
    }

    var sourceID: String? { spec["source"] as? String }

    var isVisible: Bool {
        get { (section("layout")["visibility"] as? String) != "none" }
        set { setLayoutValue("visibility", newValue ? "visible" : "none") }
    }

    var minimumZoomLevel: Float {
        get { (spec["minzoom"] as? NSNumber)?.floatValue ?? -Float.infinity }
        set {
            if newValue.isFinite { spec["minzoom"] = max(0, min(24, Double(newValue))) } else { spec.removeValue(forKey: "minzoom") }
            sendZoomRange()
        }
    }

    var maximumZoomLevel: Float {
        get { (spec["maxzoom"] as? NSNumber)?.floatValue ?? Float.infinity }
        set {
            if newValue.isFinite { spec["maxzoom"] = max(0, min(24, Double(newValue))) } else { spec.removeValue(forKey: "maxzoom") }
            sendZoomRange()
        }
    }

    private func sendZoomRange() {
        style?.layerChanged(self, command: [
            "op": "zoomRange", "id": identifier,
            "min": spec["minzoom"] ?? 0, "max": spec["maxzoom"] ?? 24,
        ])
    }

    fileprivate func section(_ name: String) -> [String: Any] {
        spec[name] as? [String: Any] ?? [:]
    }

    fileprivate func expression(_ section: String, _ key: String) -> NSExpression! {
        guard let value = self.section(section)[key] else { return nil }
        return NSExpression.mglJSON(value)
    }

    fileprivate func setValue(_ section: String, _ key: String, _ json: Any?) {
        var values = self.section(section)
        if let json, !(json is NSNull) {
            values[key] = json
        } else {
            values.removeValue(forKey: key)
        }
        spec[section] = values
        style?.layerChanged(self, command: [
            "op": section == "paint" ? "paint" : "layout",
            "id": identifier, "k": key, "v": json ?? NSNull(),
        ])
    }

    fileprivate func setLayoutValue(_ key: String, _ json: Any?) {
        setValue("layout", key, json)
    }

    fileprivate func paint(_ key: String) -> NSExpression! { expression("paint", key) }
    fileprivate func layout(_ key: String) -> NSExpression! { expression("layout", key) }

    fileprivate func setPaint(_ key: String, _ value: NSExpression?) {
        setValue("paint", key, value.map { WebMapJSON.expression($0, topLevel: true) })
    }

    fileprivate func setLayout(_ key: String, _ value: NSExpression?) {
        setValue("layout", key, value.map { WebMapJSON.expression($0, topLevel: true) })
    }

    fileprivate func transition(_ key: String) -> MLNTransition {
        let value = section("paint")[key] as? [String: Any]
        return MLNTransition(
            duration: ((value?["duration"] as? NSNumber)?.doubleValue ?? 300) / 1000,
            delay: ((value?["delay"] as? NSNumber)?.doubleValue ?? 0) / 1000)
    }

    fileprivate func setTransition(_ key: String, _ transition: MLNTransition) {
        setValue("paint", key, [
            "duration": Int(transition.duration * 1000), "delay": Int(transition.delay * 1000),
        ])
    }
}

class MLNForegroundStyleLayer: MLNStyleLayer {
    var sourceIdentifier: String? { sourceID }
}

class MLNVectorStyleLayer: MLNForegroundStyleLayer {
    var sourceLayerIdentifier: String? {
        get { spec["source-layer"] as? String }
        set {
            if let newValue { spec["source-layer"] = newValue } else { spec.removeValue(forKey: "source-layer") }
            style?.layerNeedsReplacing(self)
        }
    }

    var predicate: NSPredicate? {
        get { spec["filter"].map { MLNJSONPredicate(json: $0) } }
        set {
            let json: Any? = newValue.map { WebMapJSON.filter($0) }
            if let json { spec["filter"] = json } else { spec.removeValue(forKey: "filter") }
            style?.layerChanged(self, command: ["op": "filter", "id": identifier, "f": json ?? NSNull()])
        }
    }
}

final class MLNBackgroundStyleLayer: MLNStyleLayer {
    convenience init(identifier: String) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "background", nil))
    }

    var backgroundColor: NSExpression! { get { paint("background-color") } set { setPaint("background-color", newValue) } }
    var backgroundOpacity: NSExpression! { get { paint("background-opacity") } set { setPaint("background-opacity", newValue) } }
    var backgroundPattern: NSExpression! { get { paint("background-pattern") } set { setPaint("background-pattern", newValue) } }
}

final class MLNLineStyleLayer: MLNVectorStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "line", source))
    }

    var lineCap: NSExpression! { get { layout("line-cap") } set { setLayout("line-cap", newValue) } }
    var lineJoin: NSExpression! { get { layout("line-join") } set { setLayout("line-join", newValue) } }
    var lineMiterLimit: NSExpression! { get { layout("line-miter-limit") } set { setLayout("line-miter-limit", newValue) } }
    var lineRoundLimit: NSExpression! { get { layout("line-round-limit") } set { setLayout("line-round-limit", newValue) } }
    var lineSortKey: NSExpression! { get { layout("line-sort-key") } set { setLayout("line-sort-key", newValue) } }
    var lineColor: NSExpression! { get { paint("line-color") } set { setPaint("line-color", newValue) } }
    var lineWidth: NSExpression! { get { paint("line-width") } set { setPaint("line-width", newValue) } }
    var lineOpacity: NSExpression! { get { paint("line-opacity") } set { setPaint("line-opacity", newValue) } }
    var lineGapWidth: NSExpression! { get { paint("line-gap-width") } set { setPaint("line-gap-width", newValue) } }
    var lineOffset: NSExpression! { get { paint("line-offset") } set { setPaint("line-offset", newValue) } }
    var lineBlur: NSExpression! { get { paint("line-blur") } set { setPaint("line-blur", newValue) } }
    var lineDashPattern: NSExpression! { get { paint("line-dasharray") } set { setPaint("line-dasharray", newValue) } }
    var linePattern: NSExpression! { get { paint("line-pattern") } set { setPaint("line-pattern", newValue) } }
    var lineGradient: NSExpression! { get { paint("line-gradient") } set { setPaint("line-gradient", newValue) } }
    var lineTranslation: NSExpression! { get { paint("line-translate") } set { setPaint("line-translate", newValue) } }
}

final class MLNFillStyleLayer: MLNVectorStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "fill", source))
    }

    var fillSortKey: NSExpression! { get { layout("fill-sort-key") } set { setLayout("fill-sort-key", newValue) } }
    var fillColor: NSExpression! { get { paint("fill-color") } set { setPaint("fill-color", newValue) } }
    var fillOpacity: NSExpression! { get { paint("fill-opacity") } set { setPaint("fill-opacity", newValue) } }
    var fillOutlineColor: NSExpression! { get { paint("fill-outline-color") } set { setPaint("fill-outline-color", newValue) } }
    var fillPattern: NSExpression! { get { paint("fill-pattern") } set { setPaint("fill-pattern", newValue) } }
    var fillTranslation: NSExpression! { get { paint("fill-translate") } set { setPaint("fill-translate", newValue) } }
    var fillAntialiased: NSExpression! { get { paint("fill-antialias") } set { setPaint("fill-antialias", newValue) } }
}

final class MLNFillExtrusionStyleLayer: MLNVectorStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "fill-extrusion", source))
    }

    var fillExtrusionColor: NSExpression! { get { paint("fill-extrusion-color") } set { setPaint("fill-extrusion-color", newValue) } }
    var fillExtrusionOpacity: NSExpression! { get { paint("fill-extrusion-opacity") } set { setPaint("fill-extrusion-opacity", newValue) } }
    var fillExtrusionHeight: NSExpression! { get { paint("fill-extrusion-height") } set { setPaint("fill-extrusion-height", newValue) } }
    var fillExtrusionBase: NSExpression! { get { paint("fill-extrusion-base") } set { setPaint("fill-extrusion-base", newValue) } }
    var fillExtrusionPattern: NSExpression! { get { paint("fill-extrusion-pattern") } set { setPaint("fill-extrusion-pattern", newValue) } }
    var fillExtrusionTranslation: NSExpression! { get { paint("fill-extrusion-translate") } set { setPaint("fill-extrusion-translate", newValue) } }
    var fillExtrusionHasVerticalGradient: NSExpression! {
        get { paint("fill-extrusion-vertical-gradient") }
        set { setPaint("fill-extrusion-vertical-gradient", newValue) }
    }
    var fillExtrusionOpacityTransition: MLNTransition {
        get { transition("fill-extrusion-opacity-transition") }
        set { setTransition("fill-extrusion-opacity-transition", newValue) }
    }
}

final class MLNCircleStyleLayer: MLNVectorStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "circle", source))
    }

    var circleSortKey: NSExpression! { get { layout("circle-sort-key") } set { setLayout("circle-sort-key", newValue) } }
    var circleRadius: NSExpression! { get { paint("circle-radius") } set { setPaint("circle-radius", newValue) } }
    var circleColor: NSExpression! { get { paint("circle-color") } set { setPaint("circle-color", newValue) } }
    var circleOpacity: NSExpression! { get { paint("circle-opacity") } set { setPaint("circle-opacity", newValue) } }
    var circleBlur: NSExpression! { get { paint("circle-blur") } set { setPaint("circle-blur", newValue) } }
    var circleStrokeWidth: NSExpression! { get { paint("circle-stroke-width") } set { setPaint("circle-stroke-width", newValue) } }
    var circleStrokeColor: NSExpression! { get { paint("circle-stroke-color") } set { setPaint("circle-stroke-color", newValue) } }
    var circleStrokeOpacity: NSExpression! { get { paint("circle-stroke-opacity") } set { setPaint("circle-stroke-opacity", newValue) } }
    var circleTranslation: NSExpression! { get { paint("circle-translate") } set { setPaint("circle-translate", newValue) } }
    var circlePitchAlignment: NSExpression! { get { paint("circle-pitch-alignment") } set { setPaint("circle-pitch-alignment", newValue) } }
    var circleScaleAlignment: NSExpression! { get { paint("circle-pitch-scale") } set { setPaint("circle-pitch-scale", newValue) } }
}

final class MLNHeatmapStyleLayer: MLNVectorStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "heatmap", source))
    }

    var heatmapRadius: NSExpression! { get { paint("heatmap-radius") } set { setPaint("heatmap-radius", newValue) } }
    var heatmapWeight: NSExpression! { get { paint("heatmap-weight") } set { setPaint("heatmap-weight", newValue) } }
    var heatmapIntensity: NSExpression! { get { paint("heatmap-intensity") } set { setPaint("heatmap-intensity", newValue) } }
    var heatmapColor: NSExpression! { get { paint("heatmap-color") } set { setPaint("heatmap-color", newValue) } }
    var heatmapOpacity: NSExpression! { get { paint("heatmap-opacity") } set { setPaint("heatmap-opacity", newValue) } }
}

final class MLNSymbolStyleLayer: MLNVectorStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "symbol", source))
    }

    // Layout
    var iconImageName: NSExpression! { get { layout("icon-image") } set { setLayout("icon-image", newValue) } }
    var iconScale: NSExpression! { get { layout("icon-size") } set { setLayout("icon-size", newValue) } }
    var iconRotation: NSExpression! { get { layout("icon-rotate") } set { setLayout("icon-rotate", newValue) } }
    var iconRotationAlignment: NSExpression! { get { layout("icon-rotation-alignment") } set { setLayout("icon-rotation-alignment", newValue) } }
    var iconPitchAlignment: NSExpression! { get { layout("icon-pitch-alignment") } set { setLayout("icon-pitch-alignment", newValue) } }
    var iconAllowsOverlap: NSExpression! { get { layout("icon-allow-overlap") } set { setLayout("icon-allow-overlap", newValue) } }
    var iconIgnoresPlacement: NSExpression! { get { layout("icon-ignore-placement") } set { setLayout("icon-ignore-placement", newValue) } }
    var iconOptional: NSExpression! { get { layout("icon-optional") } set { setLayout("icon-optional", newValue) } }
    var iconOffset: NSExpression! { get { layout("icon-offset") } set { setLayout("icon-offset", newValue) } }
    var iconAnchor: NSExpression! { get { layout("icon-anchor") } set { setLayout("icon-anchor", newValue) } }
    var iconPadding: NSExpression! { get { layout("icon-padding") } set { setLayout("icon-padding", newValue) } }
    var iconTextFit: NSExpression! { get { layout("icon-text-fit") } set { setLayout("icon-text-fit", newValue) } }
    var iconTextFitPadding: NSExpression! { get { layout("icon-text-fit-padding") } set { setLayout("icon-text-fit-padding", newValue) } }
    var keepsIconUpright: NSExpression! { get { layout("icon-keep-upright") } set { setLayout("icon-keep-upright", newValue) } }
    var text: NSExpression! { get { layout("text-field") } set { setLayout("text-field", newValue) } }
    var textFontNames: NSExpression! { get { layout("text-font") } set { setLayout("text-font", newValue) } }
    var textFontSize: NSExpression! { get { layout("text-size") } set { setLayout("text-size", newValue) } }
    var textAnchor: NSExpression! { get { layout("text-anchor") } set { setLayout("text-anchor", newValue) } }
    var textOffset: NSExpression! { get { layout("text-offset") } set { setLayout("text-offset", newValue) } }
    var textRadialOffset: NSExpression! { get { layout("text-radial-offset") } set { setLayout("text-radial-offset", newValue) } }
    var textVariableAnchor: NSExpression! { get { layout("text-variable-anchor") } set { setLayout("text-variable-anchor", newValue) } }
    var textAllowsOverlap: NSExpression! { get { layout("text-allow-overlap") } set { setLayout("text-allow-overlap", newValue) } }
    var textIgnoresPlacement: NSExpression! { get { layout("text-ignore-placement") } set { setLayout("text-ignore-placement", newValue) } }
    var textOptional: NSExpression! { get { layout("text-optional") } set { setLayout("text-optional", newValue) } }
    var textJustification: NSExpression! { get { layout("text-justify") } set { setLayout("text-justify", newValue) } }
    var textLetterSpacing: NSExpression! { get { layout("text-letter-spacing") } set { setLayout("text-letter-spacing", newValue) } }
    var textLineHeight: NSExpression! { get { layout("text-line-height") } set { setLayout("text-line-height", newValue) } }
    var maximumTextWidth: NSExpression! { get { layout("text-max-width") } set { setLayout("text-max-width", newValue) } }
    var maximumTextAngle: NSExpression! { get { layout("text-max-angle") } set { setLayout("text-max-angle", newValue) } }
    var textPadding: NSExpression! { get { layout("text-padding") } set { setLayout("text-padding", newValue) } }
    var textRotation: NSExpression! { get { layout("text-rotate") } set { setLayout("text-rotate", newValue) } }
    var textRotationAlignment: NSExpression! { get { layout("text-rotation-alignment") } set { setLayout("text-rotation-alignment", newValue) } }
    var textPitchAlignment: NSExpression! { get { layout("text-pitch-alignment") } set { setLayout("text-pitch-alignment", newValue) } }
    var textTransform: NSExpression! { get { layout("text-transform") } set { setLayout("text-transform", newValue) } }
    var keepsTextUpright: NSExpression! { get { layout("text-keep-upright") } set { setLayout("text-keep-upright", newValue) } }
    var textWritingModes: NSExpression! { get { layout("text-writing-mode") } set { setLayout("text-writing-mode", newValue) } }
    var symbolPlacement: NSExpression! { get { layout("symbol-placement") } set { setLayout("symbol-placement", newValue) } }
    var symbolSpacing: NSExpression! { get { layout("symbol-spacing") } set { setLayout("symbol-spacing", newValue) } }
    var symbolSortKey: NSExpression! { get { layout("symbol-sort-key") } set { setLayout("symbol-sort-key", newValue) } }
    var symbolZOrder: NSExpression! { get { layout("symbol-z-order") } set { setLayout("symbol-z-order", newValue) } }
    var symbolAvoidsEdges: NSExpression! { get { layout("symbol-avoid-edges") } set { setLayout("symbol-avoid-edges", newValue) } }

    // Paint
    var textColor: NSExpression! { get { paint("text-color") } set { setPaint("text-color", newValue) } }
    var textHaloColor: NSExpression! { get { paint("text-halo-color") } set { setPaint("text-halo-color", newValue) } }
    var textHaloWidth: NSExpression! { get { paint("text-halo-width") } set { setPaint("text-halo-width", newValue) } }
    var textHaloBlur: NSExpression! { get { paint("text-halo-blur") } set { setPaint("text-halo-blur", newValue) } }
    var textOpacity: NSExpression! { get { paint("text-opacity") } set { setPaint("text-opacity", newValue) } }
    var textTranslation: NSExpression! { get { paint("text-translate") } set { setPaint("text-translate", newValue) } }
    var iconColor: NSExpression! { get { paint("icon-color") } set { setPaint("icon-color", newValue) } }
    var iconHaloColor: NSExpression! { get { paint("icon-halo-color") } set { setPaint("icon-halo-color", newValue) } }
    var iconHaloWidth: NSExpression! { get { paint("icon-halo-width") } set { setPaint("icon-halo-width", newValue) } }
    var iconHaloBlur: NSExpression! { get { paint("icon-halo-blur") } set { setPaint("icon-halo-blur", newValue) } }
    var iconOpacity: NSExpression! { get { paint("icon-opacity") } set { setPaint("icon-opacity", newValue) } }
    var iconTranslation: NSExpression! { get { paint("icon-translate") } set { setPaint("icon-translate", newValue) } }
}

final class MLNRasterStyleLayer: MLNForegroundStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "raster", source))
    }

    var rasterOpacity: NSExpression! { get { paint("raster-opacity") } set { setPaint("raster-opacity", newValue) } }
    var rasterFadeDuration: NSExpression! { get { paint("raster-fade-duration") } set { setPaint("raster-fade-duration", newValue) } }
    var maximumRasterBrightness: NSExpression! { get { paint("raster-brightness-max") } set { setPaint("raster-brightness-max", newValue) } }
    var minimumRasterBrightness: NSExpression! { get { paint("raster-brightness-min") } set { setPaint("raster-brightness-min", newValue) } }
    var rasterSaturation: NSExpression! { get { paint("raster-saturation") } set { setPaint("raster-saturation", newValue) } }
    var rasterContrast: NSExpression! { get { paint("raster-contrast") } set { setPaint("raster-contrast", newValue) } }
    var rasterHueRotation: NSExpression! { get { paint("raster-hue-rotate") } set { setPaint("raster-hue-rotate", newValue) } }
    var rasterResamplingMode: NSExpression! { get { paint("raster-resampling") } set { setPaint("raster-resampling", newValue) } }
}

final class MLNHillshadeStyleLayer: MLNForegroundStyleLayer {
    convenience init(identifier: String, source: MLNSource) {
        self.init(spec: MLNStyleLayer.baseSpec(identifier, "hillshade", source))
    }

    var hillshadeExaggeration: NSExpression! { get { paint("hillshade-exaggeration") } set { setPaint("hillshade-exaggeration", newValue) } }
    var hillshadeShadowColor: NSExpression! { get { paint("hillshade-shadow-color") } set { setPaint("hillshade-shadow-color", newValue) } }
    var hillshadeHighlightColor: NSExpression! { get { paint("hillshade-highlight-color") } set { setPaint("hillshade-highlight-color", newValue) } }
    var hillshadeAccentColor: NSExpression! { get { paint("hillshade-accent-color") } set { setPaint("hillshade-accent-color", newValue) } }
    var hillshadeIlluminationDirection: NSExpression! {
        get { paint("hillshade-illumination-direction") }
        set { setPaint("hillshade-illumination-direction", newValue) }
    }
}

// MARK: - Style

/// One loaded style document. A new document is a new object, as with MapLibre Native, so the
/// layer classes that key their state by `ObjectIdentifier(style)` reinstall on each load.
final class MLNStyle: NSObject {
    weak var mapView: MLNMapView?
    let generation: Int
    private var root: [String: Any]
    private var layerList: [MLNStyleLayer] = []
    private var sourceList: [MLNSource] = []
    private var imageTable: [String: UIImage] = [:]
    private var encodedImages: [String: (image: UIImage, payload: [String: Any])] = [:]

    init(document: [String: Any], generation: Int) {
        self.generation = generation
        var root = document
        root.removeValue(forKey: "layers")
        root.removeValue(forKey: "sources")
        self.root = root
        super.init()
        let sources = document["sources"] as? [String: Any] ?? [:]
        for id in sources.keys.sorted() {
            guard let spec = sources[id] as? [String: Any] else { continue }
            let source = MLNSource.make(identifier: id, spec: spec)
            source.style = self
            sourceList.append(source)
        }
        for case let spec as [String: Any] in document["layers"] as? [Any] ?? [] {
            let layer = MLNStyleLayer.make(spec: spec)
            layer.style = self
            layerList.append(layer)
        }
    }

    var name: String? { root["name"] as? String }

    var layers: [MLNStyleLayer] { layerList }

    var sources: [MLNSource] { sourceList }

    private var isAttached: Bool { mapView?.style === self }

    func layer(withIdentifier identifier: String) -> MLNStyleLayer? {
        layerList.first { $0.identifier == identifier }
    }

    func source(withIdentifier identifier: String) -> MLNSource? {
        sourceList.first { $0.identifier == identifier }
    }

    // MARK: Sources

    func addSource(_ source: MLNSource) {
        guard self.source(withIdentifier: source.identifier) == nil else { return }
        source.style = self
        sourceList.append(source)
        send(["op": "addSource", "id": source.identifier, "spec": source.pageSpec()])
        (source as? MLNShapeSource)?.markSent()
        for (index, layer) in layerList.enumerated() where !layer.isLive && layer.sourceID == source.identifier {
            activate(layer, at: index)
        }
    }

    func removeSource(_ source: MLNSource) {
        guard let index = sourceList.firstIndex(where: { $0 === source || $0.identifier == source.identifier }) else {
            return
        }
        // A source still drawn by a layer stays, as MapLibre Native refuses to remove it.
        guard !layerList.contains(where: { $0.sourceID == source.identifier }) else { return }
        sourceList.remove(at: index)
        source.style = nil
        send(["op": "removeSource", "id": source.identifier])
    }

    func sourceDataChanged(_ source: MLNShapeSource) {
        guard isAttached, sourceList.contains(where: { $0 === source }) else { return }
        if let command = source.dataCommandIfChanged() {
            send(command)
        }
    }

    // MARK: Layers

    func addLayer(_ layer: MLNStyleLayer) {
        insert(layer, at: layerList.count)
    }

    func insertLayer(_ layer: MLNStyleLayer, below sibling: MLNStyleLayer) {
        let index = layerList.firstIndex { $0 === sibling } ?? layerList.count
        insert(layer, at: index)
    }

    func insertLayer(_ layer: MLNStyleLayer, above sibling: MLNStyleLayer) {
        let index = layerList.firstIndex { $0 === sibling }.map { $0 + 1 } ?? layerList.count
        insert(layer, at: index)
    }

    func insertLayer(_ layer: MLNStyleLayer, at index: UInt) {
        insert(layer, at: Int(index))
    }

    private func insert(_ layer: MLNStyleLayer, at requested: Int) {
        // MapLibre Native throws for a duplicate identifier; the app never relies on that.
        guard !layerList.contains(where: { $0 === layer || $0.identifier == layer.identifier }) else { return }
        let index = max(0, min(requested, layerList.count))
        layer.style = self
        layer.isLive = false
        layerList.insert(layer, at: index)
        activate(layer, at: index)
    }

    func removeLayer(_ layer: MLNStyleLayer) {
        guard let index = layerList.firstIndex(where: { $0 === layer }) else { return }
        layerList.remove(at: index)
        if layer.isLive {
            send(["op": "removeLayer", "id": layer.identifier])
        }
        layer.isLive = false
        layer.style = nil
    }

    private func canBeLive(_ layer: MLNStyleLayer) -> Bool {
        guard let source = layer.sourceID else { return true }
        return self.source(withIdentifier: source) != nil
    }

    private func nextLiveIdentifier(after index: Int) -> String? {
        guard index + 1 < layerList.count else { return nil }
        return layerList[(index + 1)...].first(where: \.isLive)?.identifier
    }

    private func activate(_ layer: MLNStyleLayer, at index: Int) {
        guard isAttached, canBeLive(layer) else { return }
        var command: [String: Any] = ["op": "addLayer", "spec": layer.spec]
        if let before = nextLiveIdentifier(after: index) { command["before"] = before }
        layer.isLive = true
        send(command)
    }

    func layerChanged(_ layer: MLNStyleLayer, command: [String: Any]) {
        guard layer.isLive, layer.style === self else { return }
        send(command)
    }

    /// A change GL JS cannot apply in place (the source layer): the layer is added again at the
    /// same position.
    func layerNeedsReplacing(_ layer: MLNStyleLayer) {
        guard layer.isLive, let index = layerList.firstIndex(where: { $0 === layer }) else { return }
        send(["op": "removeLayer", "id": layer.identifier])
        layer.isLive = false
        activate(layer, at: index)
    }

    // MARK: Images

    func setImage(_ image: UIImage, forName name: String) {
        imageTable[name] = image
        guard isAttached else { return }
        if let payload = imagePayload(name) { send(payload) }
    }

    func image(forName name: String) -> UIImage? {
        imageTable[name]
    }

    func removeImage(forName name: String) {
        imageTable.removeValue(forKey: name)
        encodedImages.removeValue(forKey: name)
        send(["op": "removeImage", "name": name])
    }

    private func imagePayload(_ name: String) -> [String: Any]? {
        guard let image = imageTable[name] else { return nil }
        if let cached = encodedImages[name], cached.image === image { return cached.payload }
        guard var payload = WebMapImages.rgba(image) else { return nil }
        payload["op"] = "image"
        payload["name"] = name
        encodedImages[name] = (image, payload)
        return payload
    }

    /// Every image, for a page that lost them (a fresh document after a web content crash).
    func allImageCommands() -> [[String: Any]] {
        imageTable.keys.sorted().compactMap(imagePayload)
    }

    // MARK: Document

    /// The whole document as the page loads it: root keys, every source and every layer whose
    /// source exists, with the page's URLs. Marks those layers live.
    func pageDocument() -> [String: Any] {
        var document = root
        if let sprite = root["sprite"] as? String {
            document["sprite"] = WebMapURLs.page(sprite)
        } else if let sprites = root["sprite"] as? [[String: Any]] {
            document["sprite"] = sprites.map { entry -> [String: Any] in
                var copy = entry
                if let url = entry["url"] as? String { copy["url"] = WebMapURLs.page(url) }
                return copy
            }
        }
        if let glyphs = root["glyphs"] as? String {
            document["glyphs"] = WebMapURLs.page(glyphs)
        }
        var sources: [String: Any] = [:]
        for source in sourceList {
            sources[source.identifier] = source.pageSpec()
            (source as? MLNShapeSource)?.markSent()
        }
        document["sources"] = sources
        var layers: [[String: Any]] = []
        for layer in layerList {
            layer.isLive = canBeLive(layer)
            if layer.isLive { layers.append(layer.spec) }
        }
        document["layers"] = layers
        if document["version"] == nil { document["version"] = 8 }
        return document
    }

    private func send(_ command: [String: Any]) {
        guard isAttached else { return }
        mapView?.webSend(command)
    }
}

// MARK: - Image encoding

enum WebMapImages {
    /// The image as straight-alpha RGBA, the form `map.addImage` takes without an async decode.
    static func rgba(_ image: UIImage) -> [String: Any]? {
        let scale = max(image.scale, 1)
        let width = Int((image.size.width * scale).rounded())
        let height = Int((image.size.height * scale).rounded())
        guard width > 0, height > 0, width * height <= 4096 * 4096 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: scale, y: -scale)
            UIGraphicsPushContext(context)
            image.draw(in: CGRect(origin: .zero, size: image.size))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else { return nil }
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            pixels[index] = UInt8(min(255, Int(pixels[index]) * 255 / alpha))
            pixels[index + 1] = UInt8(min(255, Int(pixels[index + 1]) * 255 / alpha))
            pixels[index + 2] = UInt8(min(255, Int(pixels[index + 2]) * 255 / alpha))
        }
        return [
            "w": width,
            "h": height,
            "ratio": Double(scale),
            "sdf": image.renderingMode == .alwaysTemplate,
            "b64": Data(pixels).base64EncodedString(),
        ]
    }

    /// A view drawn into a bitmap at screen scale, for an annotation marker.
    static func snapshot(_ view: UIView) -> UIImage? {
        let size = view.bounds.size
        guard size.width >= 1, size.height >= 1 else { return nil }
        view.layoutIfNeeded()
        prepare(view)
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    private static func prepare(_ view: UIView) {
        view.layer.setNeedsDisplay()
        view.layer.displayIfNeeded()
        for subview in view.subviews { prepare(subview) }
    }
}
