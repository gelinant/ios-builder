import CoreLocation
import MapLibre
import UIKit

/// The optional map overlays. Every source is an in-memory `MLNShapeSource`: a layer never adds a
/// remote style URL, so a downloaded offline style keeps `remote=0` while these switches are on.
final class MapLayers {
    static let sourceIdentifiers = [
        "vela-paint-src", "vela-speed-src", "vela-alpr-src", "vela-alpr-cone-src",
        "vela-controls-src", "vela-fuel-src", "vela-bridge-src",
        "vela-poi-src",
    ]

    /// The plate-camera direction wedge. It shares the ALPR switch and zoom gate with the dots;
    /// only cameras whose pack or Overpass answer carries a bearing produce a shape.
    static let alprConeLayerId = "vela-alpr-cone"
    static let alprConeSourceId = "vela-alpr-cone-src"

    /// Same floor as the ALPR dot layer. Camera cones never appear where the dot is hidden.
    static let cameraMinZoom = CameraCones.minZoom

    /// The bundled Vela pack's symbol layer. It is an in-memory shape source like the overlays, so
    /// it also draws over a downloaded region and adds no remote URL to the offline style.
    static let velaPoiLayerId = "vela-poi"
    static let velaPoiMinZoom = 15.0

    private static let paintedLayers = [
        "vela-paint-median", "vela-paint-center", "vela-paint-lane",
        "vela-paint-bike", "vela-paint-crosswalk", "vela-paint-stop",
    ]

    /// Every style layer identifier this class can add. MAP-TAP reads it, so a layer added here
    /// without a tap rule fails `MapTapRegistryTests` instead of becoming silently untappable.
    static let layerIdentifiers: [String] = paintedLayers + [
        "vela-speed", alprConeLayerId, "vela-alpr",
        "vela-controls-signal", "vela-controls-stop",
        "vela-controls-rail_crossing", "vela-controls-speed_hump",
        "vela-fuel", "vela-fuel-label",
        "vela-bridge-open", "vela-bridge-planned",
        velaPoiLayerId,
    ]

    /// The Liberty POI layers the sheet filters and MAP-TAP taps as places.
    static let tilePoiLayerIdentifiers = ["poi_r1", "poi_r7", "poi_r20", "poi_transit"]

    private static let controlKinds = [
        ("SIGNAL", UIColor(rgb: 0xF2A33A)),
        ("STOP", UIColor(rgb: 0xD93025)),
        ("RAIL_CROSSING", UIColor(rgb: 0x2F7BF0)),
        ("SPEED_HUMP", UIColor(rgb: 0x7A8794)),
    ]

    private var current = MapLayerData.empty
    private var offline = false
    private var lastZoom = 0.0
    private var coneZoomBucket = -1.0
    private var poiOriginals: [String: NSPredicate] = [:]

    func apply(_ data: MapLayerData, style: MLNStyle, offline: Bool) {
        current = data
        self.offline = offline
        ensureSources(style)
        updateShapes(style)
        ensureLayers(style)
        applyPoiFilter(style)
        applyVelaPoiFilter(style)
        applyPoiSizes(style)
        // A switch or a new answer can change the camera set without a zoom change.
        updateConeShapes(style, zoom: max(lastZoom, Self.cameraMinZoom))
        updateVisibility(zoom: lastZoom, style: style)
        updateCameraDebug()
    }

    /// The camera family this apply draws. `auto` follows the style: the live query online, the
    /// pack inside a downloaded region. A stale pack is not a fallback: it draws nothing.
    private var cameraMode: CameraSource { CameraSource.normalize(current.cameraSource) }

    private var usesPack: Bool {
        cameraMode.drawsPack(offline: offline) && current.packCovers && !current.packStale
    }

    private func cameraPoints(live: [LayerPin], pack: [LayerPin]) -> [LayerPin] {
        if cameraMode.drawsLive(offline: offline) { return live }
        return usesPack ? pack : []
    }

    private func updateCameraDebug() {
        let count = usesPack ? current.packSpeedPoints.count + current.packAlprPoints.count : 0
        CameraPackDebug.line = CameraPackDebug.describe(
            mode: cameraMode, offline: offline,
            packName: current.packName, packDate: current.packDate,
            packCovers: current.packCovers, packStale: current.packStale, count: count)
        let cameras = current.alprCameras
            ? cameraPoints(live: current.alprPoints, pack: current.packAlprPoints)
            : []
        let oriented = cameras.filter { $0.bearing != nil }.count
        CameraPackDebug.cones = "oriented=\(oriented) unoriented=\(cameras.count - oriented)"
    }

    /// Per camera-idle only. Changing a layer's `isVisible` is cheap; no shape is rebuilt except
    /// the camera wedges, whose ground length depends on the zoom bucket.
    func updateVisibility(zoom: Double, style: MLNStyle) {
        lastZoom = zoom
        let bucket = (zoom * 2).rounded() / 2
        if bucket != coneZoomBucket {
            coneZoomBucket = bucket
            updateConeShapes(style, zoom: max(zoom, Self.cameraMinZoom))
        }
        let painted = current.paintedRoads && zoom >= 16.0
        for id in Self.paintedLayers { layer(style, id)?.isVisible = painted }
        let cameras = zoom >= Self.cameraMinZoom
        layer(style, "vela-speed")?.isVisible = current.speedCameras && cameras
        layer(style, "vela-alpr")?.isVisible = current.alprCameras && cameras
        layer(style, Self.alprConeLayerId)?.isVisible =
            CameraCones.visible(zoom: zoom, layerOn: current.alprCameras)
        for (kind, _) in Self.controlKinds {
            layer(style, "vela-controls-\(kind.lowercased())")?.isVisible =
                current.trafficControls && zoom >= 16.0
        }
        layer(style, "vela-fuel")?.isVisible = current.fuelPrices
        layer(style, "vela-fuel-label")?.isVisible = current.fuelPrices
        layer(style, "vela-bridge-open")?.isVisible = current.bridgeOpenings
        layer(style, "vela-bridge-planned")?.isVisible = current.bridgeOpenings

        // The source picks which family draws: the basemap's four Liberty layers, the bundled
        // Vela pack, or both. The master "Show places" switch and the categories still apply.
        let tiles = current.poiSource != "vela"
        let packed = current.poiDensity == "compact"
        let groups: [(String, Double)] = [
            ("poi_r1", 15.0), ("poi_r7", 17.0), ("poi_r20", 18.0), ("poi_transit", 0.0),
        ]
        for (id, base) in groups {
            let minimum = packed && id != "poi_transit" ? base + 1.0 : base
            let transit = id != "poi_transit" || current.showTransit
            layer(style, id)?.isVisible = tiles && current.showPlaces && transit && zoom >= minimum
        }
        let vela = current.poiSource != "tiles"
        layer(style, Self.velaPoiLayerId)?.isVisible =
            vela && current.showPlaces && zoom >= Self.velaPoiMinZoom
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
        setPoints(style, "vela-speed-src",
                  cameraPoints(live: current.speedPoints, pack: current.packSpeedPoints), text: false)
        setPoints(style, "vela-alpr-src",
                  cameraPoints(live: current.alprPoints, pack: current.packAlprPoints), text: false)
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

        let places = VelaPoiPack.all.map { poi -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = CLLocationCoordinate2D(latitude: poi.lat, longitude: poi.lng)
            feature.attributes = [
                "group": poi.group,
                "name": poi.name,
                "icon": VelaPoiImages.imageName(for: poi.group),
            ]
            return feature
        }
        (style.source(withIdentifier: "vela-poi-src") as? MLNShapeSource)?.shape =
            MLNShapeCollectionFeature(shapes: places)
    }

    /// Builds one world-space wedge per oriented plate camera. The polygon turns with the map by
    /// construction, and its ground length follows `CameraCones.groundLengthM`, so a high zoom
    /// shows a short honest wedge instead of a stretched bitmap. A camera without a bearing
    /// contributes no shape; its dot stays.
    private func updateConeShapes(_ style: MLNStyle, zoom: Double) {
        guard let source = style.source(withIdentifier: Self.alprConeSourceId) as? MLNShapeSource else {
            return
        }
        let cameras = current.alprCameras
            ? cameraPoints(live: current.alprPoints, pack: current.packAlprPoints)
            : []
        let wedges = cameras.compactMap { pin -> MLNPolygonFeature? in
            guard pin.kind == "alpr", let bearing = pin.bearing else { return nil }
            var coordinates = CameraCones.wedge(
                lat: pin.coordinate.lat, lng: pin.coordinate.lng, bearingDeg: bearing,
                lengthM: CameraCones.groundLengthM(
                    zoom: max(zoom, Self.cameraMinZoom),
                    latitudeDeg: pin.coordinate.lat)).map(\.coordinate)
            guard coordinates.count >= 3 else { return nil }
            let feature = MLNPolygonFeature(
                coordinates: &coordinates, count: UInt(coordinates.count))
            feature.attributes = ["bearing": NSNumber(value: bearing)]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: wedges)
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
            lane.lineDashPattern = NSExpression(forConstantValue: [3.0, 4.0])
            let bike = line("vela-paint-bike", source, color: UIColor(rgb: 0x86CFA0), width: 2)
            bike.predicate = NSPredicate(format: "kind == %@", "BIKE")
            let crossing = line("vela-paint-crosswalk", source, color: .white, width: 5)
            crossing.predicate = NSPredicate(format: "kind == %@", "CROSSWALK")
            crossing.lineDashPattern = NSExpression(forConstantValue: [2.0, 2.0])
            let stop = line("vela-paint-stop", source, color: .white, width: 3)
            stop.predicate = NSPredicate(format: "kind == %@", "STOP")
            for layer in [median, center, lane, bike, crossing, stop] { add(layer) }
        }

        if layer(style, "vela-speed") == nil, let source = style.source(withIdentifier: "vela-speed-src") {
            add(circle("vela-speed", source, color: UIColor(rgb: 0xD93025), radius: 5))
        }
        if layer(style, Self.alprConeLayerId) == nil,
           let source = style.source(withIdentifier: Self.alprConeSourceId) {
            let cone = MLNFillStyleLayer(identifier: Self.alprConeLayerId, source: source)
            cone.fillColor = NSExpression(forConstantValue: UIColor(rgb: 0x7B1FA2))
            cone.fillOpacity = NSExpression(forConstantValue: 0.32)
            add(cone)
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
            label.textFontNames = NSExpression(forConstantValue: offline ? ["Noto Sans Regular"] : ["Roboto Medium"])
            label.textFontSize = NSExpression(forConstantValue: 10)
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
        if layer(style, Self.velaPoiLayerId) == nil,
           let source = style.source(withIdentifier: "vela-poi-src") {
            let poi = MLNSymbolStyleLayer(identifier: Self.velaPoiLayerId, source: source)
            poi.iconImageName = NSExpression(forKeyPath: "icon")
            poi.iconAllowsOverlap = NSExpression(forConstantValue: false)
            poi.iconIgnoresPlacement = NSExpression(forConstantValue: false)
            poi.text = NSExpression(forKeyPath: "name")
            poi.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            poi.textColor = NSExpression(forConstantValue: UIColor(rgb: 0x202124))
            poi.textHaloColor = NSExpression(forConstantValue: UIColor.white)
            poi.textHaloWidth = NSExpression(forConstantValue: 1.4)
            poi.textAnchor = NSExpression(forConstantValue: "top")
            poi.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 0.9)))
            poi.textAllowsOverlap = NSExpression(forConstantValue: false)
            poi.textIgnoresPlacement = NSExpression(forConstantValue: false)
            add(poi)
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

    /// The pack carries the sheet group as a feature property, so the five category switches
    /// filter it without a second copy of the OSM class lists. A filter with no group left
    /// (`visiblePoiGroups` empty while `poiFiltered` is true) keeps the predicate and draws none.
    private func applyVelaPoiFilter(_ style: MLNStyle) {
        guard let symbol = style.layers.first(where: { $0.identifier == Self.velaPoiLayerId })
            as? MLNSymbolStyleLayer else { return }
        symbol.predicate = current.poiFiltered
            ? NSPredicate(format: "group IN %@", current.visiblePoiGroups)
            : nil
    }

    private static let transitClasses = [
        "bus", "rail", "railway", "tram", "airport", "ferry_terminal",
        "subway", "station", "halt", "bus_station",
    ]

    /// Android's `poiIconScale` (MapScreen passes the Settings multiplier to both icon and label
    /// sizes). Liberty's four POI layers ship with constant sizes; those constants are the base,
    /// multiplied by the setting. A style that changed them would make the multiplier relative to
    /// Liberty, which is the only style these layers exist on.
    private static let poiBaseSizes: [String: (icon: Double, text: Double)] = [
        "poi_r1": (icon: 0.5, text: 12),
        "poi_r7": (icon: 0.5, text: 12),
        "poi_r20": (icon: 0.5, text: 12),
        "poi_transit": (icon: 0.7, text: 12),
    ]

    private func applyPoiSizes(_ style: MLNStyle) {
        let scale = current.poiIconScale
        for (id, base) in Self.poiBaseSizes {
            guard let symbol = style.layers.first(where: { $0.identifier == id }) as? MLNSymbolStyleLayer else {
                continue
            }
            symbol.iconScale = NSExpression(forConstantValue: base.icon * scale)
            symbol.textFontSize = NSExpression(forConstantValue: base.text * scale)
        }
        // The bundled pack uses its own 28 pt marker at 1.0 and the same label size as the tile
        // layers, so one slider sizes both families whatever the source.
        if let symbol = style.layers.first(where: { $0.identifier == Self.velaPoiLayerId })
            as? MLNSymbolStyleLayer {
            symbol.iconScale = NSExpression(forConstantValue: scale)
            symbol.textFontSize = NSExpression(forConstantValue: 12 * scale)
        }
    }

    /// First label layer after the bridges, so markings stay over the road and under street names.
    static func labelAnchor(in style: MLNStyle) -> MLNStyleLayer? {
        let all = style.layers
        let lastBridge = all.lastIndex(where: { $0.identifier.hasPrefix("bridge") }) ?? -1
        return all[(lastBridge + 1)...].first(where: { $0 is MLNSymbolStyleLayer })
            ?? all.first(where: { $0 is MLNSymbolStyleLayer })
    }

    /// First label layer after the bridges, so markings stay over the road and under street names.
    private func labelLayer(_ style: MLNStyle) -> MLNStyleLayer? {
        Self.labelAnchor(in: style)
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
