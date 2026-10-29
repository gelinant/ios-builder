import MapLibre
import UIKit
import VelaCore

/// The templates and limits of the two keyless Google rasters, read from `:core-common` through
/// `MapSession`. Nothing here is a string literal of its own: Android and iOS load the same URL.
struct MapRasterConfig {
    let trafficURL: String
    let satelliteURL: String
    let satelliteDeepURL: String
    let trafficMaxZoom: Int
    let satelliteMaxZoom: Int
    let satelliteDeepMaxZoom: Int
    let satelliteDeepMinZoom: Double
    let trafficOpacity: Double
    let satelliteBrightnessMax: Double
    let satelliteSaturation: Double

    static func live() -> MapRasterConfig {
        let session = AppGraph.session
        return MapRasterConfig(
            trafficURL: session.rasterTrafficUrl(),
            satelliteURL: session.rasterSatelliteUrl(),
            satelliteDeepURL: session.rasterSatelliteDeepUrl(),
            trafficMaxZoom: Int(session.rasterTrafficMaxZoom()),
            satelliteMaxZoom: Int(session.rasterSatelliteMaxZoom()),
            satelliteDeepMaxZoom: Int(session.rasterSatelliteDeepMaxZoom()),
            satelliteDeepMinZoom: session.rasterSatelliteDeepMinZoom(),
            trafficOpacity: session.rasterTrafficOpacity(),
            satelliteBrightnessMax: session.rasterSatelliteBrightnessMax(),
            satelliteSaturation: session.rasterSatelliteSaturation())
    }
}

/// The raster layers actually present in the live style, read by the debug line. Set on the main
/// thread by `MapRasterLayers.apply`; the Debug UI scenarios assert it, so a switch that changes
/// Kotlin state without inserting its MapLibre layer cannot pass.
enum MapRasterDebug {
    static var layers = "none"
}

/// The Google traffic overlay and the satellite basemap, as MapLibre raster sources.
///
/// Satellite is drawn above the vector map's geometry and below its labels, so a tile that fails
/// to load exposes Liberty underneath rather than a blank screen; that is the fallback. The deep
/// zoom layer past Esri's maximum is Google's own imagery, faded in over a zoom level exactly as
/// Android does. Traffic sits above satellite and above buildings, below every label.
///
/// Both layers are network-only. [plan] returns nothing while a downloaded region owns the style,
/// so no Google raster URL ever reaches the offline style or a tile request from a downloaded map.
final class MapRasterLayers {
    struct Plan: Equatable {
        var traffic = false
        var satellite = false
        var deep = false

        static func make(traffic: Bool, satellite: Bool, offline: Bool) -> Plan {
            guard !offline else { return Plan() }
            return Plan(traffic: traffic, satellite: satellite, deep: satellite)
        }
    }

    static let trafficSource = "vela-traffic-src"
    static let trafficLayer = "vela-traffic"
    static let satelliteSource = "vela-sat-src"
    static let satelliteLayer = "vela-sat"
    static let satelliteRoadsLayer = "vela-sat-roads"
    static let satelliteDeepSource = "vela-sat-deep-src"
    static let satelliteDeepLayer = "vela-sat-deep"

    /// Every source that this class can put in the style. None of them is in
    /// `MapLayers.sourceIdentifiers`, whose test pins the local-only overlays.
    static let remoteSourceIdentifiers = [
        trafficSource, satelliteSource, satelliteDeepSource,
    ]

    /// Every style layer this class can add. MAP-TAP registers them as intentionally inert.
    static let layerIdentifiers = [
        trafficLayer, satelliteLayer, satelliteRoadsLayer, satelliteDeepLayer,
    ]

    private(set) var lastPlan = Plan()

    func apply(_ data: MapLayerData, style: MLNStyle, offline: Bool, config: MapRasterConfig) {
        let plan = Plan.make(traffic: data.trafficOn, satellite: data.satelliteOn, offline: offline)
        lastPlan = plan
        applySatellite(plan, style: style, config: config)
        applyTraffic(plan, style: style, config: config)
        var present: [String] = []
        if style.layer(withIdentifier: Self.trafficLayer) != nil { present.append("traffic") }
        if style.layer(withIdentifier: Self.satelliteLayer) != nil { present.append("satellite") }
        if style.layer(withIdentifier: Self.satelliteDeepLayer) != nil { present.append("deep") }
        MapRasterDebug.layers = present.isEmpty ? "none" : present.joined(separator: ",")
    }

    // MARK: - Traffic

    private func applyTraffic(_ plan: Plan, style: MLNStyle, config: MapRasterConfig) {
        guard plan.traffic else {
            removeLayer(Self.trafficLayer, style: style)
            removeSource(Self.trafficSource, style: style)
            return
        }
        guard style.layer(withIdentifier: Self.trafficLayer) == nil else { return }
        if style.source(withIdentifier: Self.trafficSource) == nil {
            let source = MLNRasterTileSource(
                identifier: Self.trafficSource,
                tileURLTemplates: [config.trafficURL],
                options: [
                    .tileSize: 256,
                    .maximumZoomLevel: config.trafficMaxZoom,
                    .attributionInfos: [Self.googleAttribution],
                ])
            style.addSource(source)
        }
        guard let source = style.source(withIdentifier: Self.trafficSource) else { return }
        let layer = MLNRasterStyleLayer(identifier: Self.trafficLayer, source: source)
        layer.rasterOpacity = NSExpression(forConstantValue: config.trafficOpacity)
        layer.rasterFadeDuration = NSExpression(forConstantValue: 900)
        insertBelowLabels(layer, style: style)
    }

    // MARK: - Satellite

    private func applySatellite(_ plan: Plan, style: MLNStyle, config: MapRasterConfig) {
        guard plan.satellite else {
            removeLayer(Self.satelliteDeepLayer, style: style)
            removeSource(Self.satelliteDeepSource, style: style)
            removeLayer(Self.satelliteRoadsLayer, style: style)
            removeLayer(Self.satelliteLayer, style: style)
            removeSource(Self.satelliteSource, style: style)
            return
        }
        let base = ensureSatelliteBase(style: style, config: config)
        if let base {
            applyGhostRoads(style: style)
            applyDeepSatellite(plan, base: base, style: style, config: config)
        }
    }

    private func ensureSatelliteBase(style: MLNStyle, config: MapRasterConfig) -> MLNStyleLayer? {
        if let existing = style.layer(withIdentifier: Self.satelliteLayer) { return existing }
        if style.source(withIdentifier: Self.satelliteSource) == nil {
            let source = MLNRasterTileSource(
                identifier: Self.satelliteSource,
                tileURLTemplates: [config.satelliteURL],
                options: [
                    .tileSize: 256,
                    .maximumZoomLevel: config.satelliteMaxZoom,
                    .attributionInfos: [Self.esriAttribution],
                ])
            style.addSource(source)
        }
        guard let source = style.source(withIdentifier: Self.satelliteSource) else { return nil }
        let layer = MLNRasterStyleLayer(identifier: Self.satelliteLayer, source: source)
        layer.maximumRasterBrightness = NSExpression(forConstantValue: config.satelliteBrightnessMax)
        layer.rasterSaturation = NSExpression(forConstantValue: config.satelliteSaturation)
        let anchor = MapLayers.labelAnchor(in: style)
        if let anchor {
            style.insertLayer(layer, below: anchor)
        } else {
            style.addLayer(layer)
        }
        return layer
    }

    /// Google hybrid's ghost road network: the basemap's own transportation lines in translucent
    /// white over the photo, so the map stays navigable through tree cover. Above the imagery,
    /// below the labels.
    private func applyGhostRoads(style: MLNStyle) {
        guard style.layer(withIdentifier: Self.satelliteRoadsLayer) == nil else { return }
        guard let source = style.sources.compactMap({ $0 as? MLNVectorTileSource }).first else { return }
        let layer = MLNLineStyleLayer(identifier: Self.satelliteRoadsLayer, source: source)
        layer.sourceLayerIdentifier = "transportation"
        layer.lineColor = NSExpression(forConstantValue: UIColor(white: 1, alpha: 0.55))
        layer.lineWidth = NSExpression(forConstantValue: 2.0)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.predicate = NSPredicate(
            format: "%K IN %@", "class",
            ["motorway", "trunk", "primary", "secondary", "tertiary",
             "minor", "street", "street_limited", "service"])
        insertBelowLabels(layer, style: style)
    }

    private func applyDeepSatellite(
        _ plan: Plan, base: MLNStyleLayer, style: MLNStyle, config: MapRasterConfig
    ) {
        guard plan.deep, style.layer(withIdentifier: Self.satelliteDeepLayer) == nil else { return }
        if style.source(withIdentifier: Self.satelliteDeepSource) == nil {
            let source = MLNRasterTileSource(
                identifier: Self.satelliteDeepSource,
                tileURLTemplates: [config.satelliteDeepURL],
                options: [
                    .tileSize: 256,
                    .maximumZoomLevel: config.satelliteDeepMaxZoom,
                ])
            style.addSource(source)
        }
        guard let source = style.source(withIdentifier: Self.satelliteDeepSource) else { return }
        let layer = MLNRasterStyleLayer(identifier: Self.satelliteDeepLayer, source: source)
        layer.maximumRasterBrightness = NSExpression(forConstantValue: config.satelliteBrightnessMax)
        layer.rasterSaturation = NSExpression(forConstantValue: config.satelliteSaturation)
        layer.minimumZoomLevel = Float(config.satelliteDeepMinZoom)
        let fade: [Any] = [
            "interpolate", ["linear"], ["zoom"],
            config.satelliteDeepMinZoom, 0,
            Double(config.satelliteMaxZoom) + 0.6, 1,
        ]
        layer.rasterOpacity = NSExpression(mglJSONObject: fade)
        style.insertLayer(layer, above: base)
    }

    // MARK: - Helpers

    private func insertBelowLabels(_ layer: MLNStyleLayer, style: MLNStyle) {
        if let anchor = MapLayers.labelAnchor(in: style) {
            style.insertLayer(layer, below: anchor)
        } else {
            style.addLayer(layer)
        }
    }

    private func removeLayer(_ id: String, style: MLNStyle) {
        guard let layer = style.layer(withIdentifier: id) else { return }
        style.removeLayer(layer)
    }

    private func removeSource(_ id: String, style: MLNStyle) {
        guard let source = style.source(withIdentifier: id) else { return }
        style.removeSource(source)
    }

    private static var esriAttribution: MLNAttributionInfo {
        MLNAttributionInfo(
            title: NSAttributedString(string: "Esri, Maxar, Earthstar Geographics"),
            url: URL(string: "https://www.esri.com"))
    }

    private static var googleAttribution: MLNAttributionInfo {
        MLNAttributionInfo(
            title: NSAttributedString(string: "Traffic: Google"),
            url: URL(string: "https://www.google.com/maps"))
    }
}
