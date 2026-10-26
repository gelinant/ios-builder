import MapLibre
import UIKit

/// The optional map overlays. Every source is an in-memory `MLNShapeSource`: a layer never adds a
/// remote style URL, so a downloaded offline style keeps `remote=0` while these switches are on.
final class MapLayers {
    static let sourceIdentifiers = [
        "vela-paint-src", "vela-speed-src", "vela-alpr-src",
        "vela-controls-src", "vela-fuel-src", "vela-bridge-src",
    ]

    private static let paintedLayers = [
        "vela-paint-median", "vela-paint-center", "vela-paint-lane",
        "vela-paint-bike", "vela-paint-crosswalk", "vela-paint-stop",
    ]

    private static let controlKinds = [
        ("SIGNAL", UIColor(rgb: 0xF2A33A)),
        ("STOP", UIColor(rgb: 0xD93025)),
        ("RAIL_CROSSING", UIColor(rgb: 0x2F7BF0)),
        ("SPEED_HUMP", UIColor(rgb: 0x7A8794)),
    ]

    private var current = MapLayerData.empty
    private var offline = false
    private var lastZoom = 0.0
    private var poiOriginals: [String: NSPredicate] = [:]

    func apply(_ data: MapLayerData, style: MLNStyle, offline: Bool) {
        current = data
        self.offline = offline
        ensureSources(style)
        updateShapes(style)
        ensureLayers(style)
        applyPoiFilter(style)
        updateVisibility(zoom: lastZoom, style: style)
    }

    /// Per camera-idle only. Changing a layer's `isVisible` is cheap; no shape is rebuilt.
    func updateVisibility(zoom: Double, style: MLNStyle) {
        lastZoom = zoom
        let painted = current.paintedRoads && zoom >= 16.0
        for id in Self.paintedLayers { layer(style, id)?.isVisible = painted }
        layer(style, "vela-speed")?.isVisible = current.speedCameras && zoom >= 13.5
        layer(style, "vela-alpr")?.isVisible = current.alprCameras && zoom >= 13.5
        for (kind, _) in Self.controlKinds {
            layer(style, "vela-controls-\(kind.lowercased())")?.isVisible =
                current.trafficControls && zoom >= 16.0
        }
        layer(style, "vela-fuel")?.isVisible = current.fuelPrices
        layer(style, "vela-fuel-label")?.isVisible = current.fuelPrices
        layer(style, "vela-bridge-open")?.isVisible = current.bridgeOpenings
        layer(style, "vela-bridge-planned")?.isVisible = current.bridgeOpenings

        let packed = current.poiDensity == "compact"
        let groups: [(String, Double)] = [
            ("poi_r1", 15.0), ("poi_r7", 17.0), ("poi_r20", 18.0), ("poi_transit", 0.0),
        ]
        for (id, base) in groups {
            let minimum = packed && id != "poi_transit" ? base + 1.0 : base
            let transit = id != "poi_transit" || current.showTransit
            layer(style, id)?.isVisible = current.showPlaces && transit && zoom >= minimum
        }
    }

    private func ensureSources(_ style: MLNStyle) {
        for id in Self.sourceIdentifiers where style.source(withIdentifier: id) == nil {
            style.addSource(MLNShapeSource(identifier: id, shape: nil, options: nil))
        }
    }

    private func updateShapes(_ style: MLNStyle) {
        setShape(style, "vela-paint-src", current.paintedMarks.compactMap { mark in
            guard mark.coordinates.count >= 2 else { return nil }
            var coordinates = mark.coordinates.map(\.coordinate)
            let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
            feature.attributes = ["kind": mark.kind]
            return feature
        })
        setPoints(style, "vela-speed-src", current.speedPoints, text: false)
        setPoints(style, "vela-alpr-src", current.alprPoints, text: false)
        setPoints(style, "vela-controls-src", current.controlPoints, text: false)
        setPoints(style, "vela-fuel-src", current.fuelPoints, text: true)

        let bridges = current.bridgePoints.map { bridge -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = bridge.coordinate.coordinate
            feature.attributes = ["open": NSNumber(value: bridge.openNow)]
            return feature
        }
        (style.source(withIdentifier: "vela-bridge-src") as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: bridges)
    }

    private func setPoints(_ style: MLNStyle, _ id: String, _ points: [LayerPin], text: Bool) {
        let features = points.map { pin -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = pin.coordinate.coordinate
            if text {
                feature.attributes = ["text": pin.text]
            } else {
                feature.attributes = ["kind": pin.kind]
            }
            return feature
        }
        (style.source(withIdentifier: id) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: features)
    }

    private func setShape(_ style: MLNStyle, _ id: String, _ features: [MLNShape & MLNFeature]) {
        (style.source(withIdentifier: id) as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: features)
    }

    private func ensureLayers(_ style: MLNStyle) {
        let anchor = labelLayer(style)
        func add(_ layer: MLNStyleLayer) {
            if let anchor {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }

        if layer(style, Self.paintedLayers[0]) == nil {
            guard let source = style.source(withIdentifier: "vela-paint-src") else { return }
            let median = line("vela-paint-median", source, color: UIColor(rgb: 0xDDE3EC), width: 4)
            let center = line("vela-paint-center", source, color: UIColor(rgb: 0xF2C200), width: 2)
            center.predicate = NSPredicate(format: "kind == %@", "CENTER")
            let lane = line("vela-paint-lane", source, color: .white, width: 1)
            lane.predicate = NSPredicate(format: "kind == %@", "LANE")
            lane.lineDasharray = NSExpression(forConstantValue: [3.0, 4.0])
            let bike = line("vela-paint-bike", source, color: UIColor(rgb: 0x86CFA0), width: 2)
            bike.predicate = NSPredicate(format: "kind == %@", "BIKE")
            let crossing = line("vela-paint-crosswalk", source, color: .white, width: 5)
            crossing.predicate = NSPredicate(format: "kind == %@", "CROSSWALK")
            crossing.lineDasharray = NSExpression(forConstantValue: [2.0, 2.0])
            let stop = line("vela-paint-stop", source, color: .white, width: 3)
            stop.predicate = NSPredicate(format: "kind == %@", "STOP")
            for layer in [median, center, lane, bike, crossing, stop] { add(layer) }
        }

        if layer(style, "vela-speed") == nil, let source = style.source(withIdentifier: "vela-speed-src") {
            add(circle("vela-speed", source, color: UIColor(rgb: 0xD93025), radius: 5))
        }
        if layer(style, "vela-alpr") == nil, let source = style.source(withIdentifier: "vela-alpr-src") {
            add(circle("vela-alpr", source, color: UIColor(rgb: 0x6C3FC5), radius: 5))
        }
        if layer(style, "vela-controls-signal") == nil,
           let source = style.source(withIdentifier: "vela-controls-src") {
            for (kind, color) in Self.controlKinds {
                let control = circle("vela-controls-\(kind.lowercased())", source, color: color, radius: 4)
                control.predicate = NSPredicate(format: "kind == %@", kind)
                add(control)
            }
        }
        if layer(style, "vela-fuel") == nil, let source = style.source(withIdentifier: "vela-fuel-src") {
            add(circle("vela-fuel", source, color: UIColor(rgb: 0x1B7F3A), radius: 4))
            let label = MLNSymbolStyleLayer(identifier: "vela-fuel-label", source: source)
            label.text = NSExpression(forKeyPath: "text")
            label.textFont = NSExpression(forConstantValue: offline ? ["Noto Sans Regular"] : ["Roboto Medium"])
            label.textSize = NSExpression(forConstantValue: 10)
            label.textColor = NSExpression(forConstantValue: UIColor(rgb: 0x144D25))
            label.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            label.textHaloWidth = NSExpression(forConstantValue: 1.5)
            label.textAllowsOverlap = NSExpression(forConstantValue: false)
            label.textIgnoresPlacement = NSExpression(forConstantValue: false)
            add(label)
        }
        if layer(style, "vela-bridge-open") == nil,
           let source = style.source(withIdentifier: "vela-bridge-src") {
            let open = circle("vela-bridge-open", source, color: UIColor(rgb: 0xD93025), radius: 6)
            open.predicate = NSPredicate(format: "open == YES")
            let planned = circle("vela-bridge-planned", source, color: UIColor(rgb: 0xE0A030), radius: 6)
            planned.predicate = NSPredicate(format: "open == NO")
            add(open)
            add(planned)
        }
    }

    private func circle(_ id: String, _ source: MLNSource, color: UIColor, radius: Double) -> MLNCircleStyleLayer {
        let layer = MLNCircleStyleLayer(identifier: id, source: source)
        layer.circleRadius = NSExpression(forConstantValue: radius)
        layer.circleColor = NSExpression(forConstantValue: color)
        layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        layer.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
        return layer
    }

    private func line(_ id: String, _ source: MLNSource, color: UIColor, width: Double) -> MLNLineStyleLayer {
        let layer = MLNLineStyleLayer(identifier: id, source: source)
        layer.lineColor = NSExpression(forConstantValue: color)
        layer.lineWidth = NSExpression(forConstantValue: width)
        layer.lineCap = NSExpression(forConstantValue: "round")
        layer.lineJoin = NSExpression(forConstantValue: "round")
        return layer
    }

    private func applyPoiFilter(_ style: MLNStyle) {
        let ids = ["poi_r1", "poi_r7", "poi_r20", "poi_transit"]
        for id in ids {
            guard let vector = style.layers.first(where: { $0.identifier == id }) as? MLNVectorStyleLayer else {
                continue
            }
            if poiOriginals[id] == nil { poiOriginals[id] = vector.predicate }
            if current.poiFiltered {
                let allowed = id == "poi_transit"
                    ? current.visiblePoiClasses.filter { Self.transitClasses.contains($0) }
                    : current.visiblePoiClasses
                let filter = NSPredicate(format: "%K IN %@", "class", allowed)
                vector.predicate = poiOriginals[id].map {
                    NSCompoundPredicate(andPredicateWithSubpredicates: [$0, filter])
                } ?? filter
            } else if let original = poiOriginals[id] {
                vector.predicate = original
            }
        }
    }

    private static let transitClasses = [
        "bus", "rail", "railway", "tram", "airport", "ferry_terminal",
        "subway", "station", "halt", "bus_station",
    ]

    /// First label layer after the bridges, so markings stay over the road and under street names.
    private func labelLayer(_ style: MLNStyle) -> MLNStyleLayer? {
        let all = style.layers
        let lastBridge = all.lastIndex(where: { $0.identifier.hasPrefix("bridge") }) ?? -1
        return all[(lastBridge + 1)...].first(where: { $0 is MLNSymbolStyleLayer })
            ?? all.first(where: { $0 is MLNSymbolStyleLayer })
    }

    private func layer(_ style: MLNStyle, _ id: String) -> MLNStyleLayer? {
        style.layers.first { $0.identifier == id }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1)
    }
}
