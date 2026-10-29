import CoreLocation
import MapLibre
import UIKit

/// The optional painted-roads pack (Android's `painted-roads` release): a PMTiles file of road
/// markings derived from OpenStreetMap. iOS does not bundle it; the sheet offers it on demand and
/// the map keeps drawing the live OSM marks until it is installed.
enum PaintedPack {
    /// The size of the released California bake, read from the asset's Content-Length. It is a
    /// fixed release object, so the sheet can name the download before the first request.
    static let sizeMB = 66
    static let fileName = "painted-roads.pmtiles"
    /// The pack is a California bake; outside this box its tiles are empty.
    static let south = 32.4
    static let north = 42.1
    static let west = -124.5
    static let east = -114.0

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("painted", isDirectory: true)
    }

    static var fileURL: URL { directory.appendingPathComponent(fileName) }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// The name the sheet and the debug line use: `pack` or `tiles`.
    static var source: String { isInstalled ? "pack" : "tiles" }

    static func covers(latitude: Double, longitude: Double) -> Bool {
        latitude >= south && latitude <= north && longitude >= west && longitude <= east
    }

    /// Explicit user action only; the switch alone never downloads anything.
    static func download(from url: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (temporary, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: temporary, to: fileURL)
    }
}

/// Map-side proof for the sheet: the renderer's apply count, the layer and feature counts it
/// installed, how many of those layers are visible, and the zoom it sized them for.
enum PaintedDebug {
    static var line = "paint_apply=0 paint_layers=0 paint_features=0 paint_vis=0 paint_z=0"
}

/// Draws the painted-road marks: road surface at the width its lanes need, median, bus-lane band,
/// center and lane lines, bike lanes, crosswalks, stop lines and one-way/turn arrows.
///
/// Every mark comes from `PaintedRoads` (live OSM data for the view) or from the optional PMTiles
/// pack. Nothing is invented: a road without a lane count, a cycleway/busway tag or a one-way tag
/// stays bare. Widths are converted from meters at the current zoom (the same 2^z / 59960 rule as
/// Android) so a mark fills its lane from z16.5 to z19. Everything is inserted below the first
/// label layer, so a road name is never covered.
final class PaintedMarksLayer {
    private static let sourceId = "vela-paint-src"
    private static let arrowSourceId = "vela-paint-arrow-src"
    private static let packSourceId = "vela-paint-pack-src"
    private static let packSourceLayer = "paint"
    private static let mPerPointAtZ0 = 59960.0
    /// `PaintedMarks.MIN_ZOOM` in `:ios-shared`, kept as a literal so the renderer has no bridge
    /// call on every viewport. `LayersStoreTest` pins the shared value.
    private static let minZoom = 16.5
    private static let arrowImageHeight = 96.0
    private static let arrowGroundM = 8.0

    private static let lineKinds: [(kind: String, suffix: String)] = [
        ("SURFACE", "surface"), ("MEDIAN", "median"), ("BUS", "bus"),
        ("CENTER", "center"), ("LANE", "lane"), ("BIKE", "bike"),
        ("CROSSWALK", "crosswalk"), ("STOP", "stop"),
    ]

    private var lastWidthBucket = -1.0
    private var imagesInstalled = false
    private var applyCount = 0
    private var lastMarks = 0
    private var lastBuilt = 0
    private var sourceFound = false

    /// Called whenever the sheet's data changes or a style loads. Cheap: the source shape is reset
    /// only from `data`, and layer insertion happens once per style.
    func apply(_ data: MapLayerData, style: MLNStyle, offline: Bool, zoom: Double) {
        ensureSource(style)
        updateShapes(data, style: style)
        installArrowImages(style)
        if PaintedPack.isInstalled {
            ensurePackSource(style)
            ensureLayers(style, pack: true)
        }
        ensureLayers(style, pack: false)
        updateVisibility(data, style: style, zoom: zoom)
        applyCount += 1
        let layers = style.layers.filter { $0.identifier.hasPrefix("vela-paint") }
        let lineShapes = (style.source(withIdentifier: Self.sourceId) as? MLNShapeSource)?
            .shape as? MLNShapeCollectionFeature
        let arrowShapes = (style.source(withIdentifier: Self.arrowSourceId) as? MLNShapeSource)?
            .shape as? MLNShapeCollectionFeature
        let featureCount = (lineShapes?.shapes.count ?? 0) + (arrowShapes?.shapes.count ?? 0)
        PaintedDebug.line = "paint_apply=\(applyCount) paint_layers=\(layers.count)"
            + " paint_features=\(featureCount)"
            + " paint_vis=\(layers.filter { $0.isVisible }.count)"
            + " paint_z=\(String(format: "%.1f", zoom))"
            + " paint_marks=\(lastMarks) paint_built=\(lastBuilt) paint_src=\(sourceFound ? 1 : 0)"
    }

    /// Per camera idle. Only layer visibility and the meter-to-point sizes change between zooms.
    func updateVisibility(_ data: MapLayerData, style: MLNStyle, zoom: Double) {
        let on = data.paintedRoads && zoom + 0.001 >= Self.minZoom
        let pack = PaintedPack.isInstalled
        for (_, suffix) in Self.lineKinds {
            layer(style, "vela-paint-\(suffix)")?.isVisible = on && !pack
            layer(style, "vela-paint-pack-\(suffix)")?.isVisible = on && pack
        }
        layer(style, "vela-paint-arrow")?.isVisible = on && !pack
        layer(style, "vela-paint-pack-arrow")?.isVisible = on && pack

        // The basemap's own one-way arrows are already in every style. They stand in when the
        // pack is absent and the live answer produced no marks (a failed Overpass call), and are
        // restored when the layer is off so the base map stays as it was.
        let fallback = data.paintedRoads && zoom + 0.001 >= Self.minZoom
            && !pack && data.paintedMarks.isEmpty
        for id in ["road_one_way_arrow", "road_one_way_arrow_opposite"] {
            layer(style, id)?.isVisible = data.paintedRoads ? fallback : true
        }
        updateWidths(style, zoom: max(zoom, Self.minZoom))
    }

    private func ensureSource(_ style: MLNStyle) {
        for id in [Self.sourceId, Self.arrowSourceId]
        where style.source(withIdentifier: id) == nil {
            style.addSource(MLNShapeSource(identifier: id, shape: nil, options: nil))
        }
    }

    private func ensurePackSource(_ style: MLNStyle) {
        guard style.source(withIdentifier: Self.packSourceId) == nil else { return }
        let configuration = "pmtiles://" + PaintedPack.fileURL.absoluteString
        style.addSource(MLNVectorTileSource(
            identifier: Self.packSourceId, configurationURLString: configuration))
    }

    /// Points (ARROW) become point features and keep their icon and heading; every other mark is
    /// a polyline. The old renderer dropped one-point features, which is why no arrow ever showed.
    private func updateShapes(_ data: MapLayerData, style: MLNStyle) {
        lastMarks = data.paintedMarks.count
        lastBuilt = 0
        sourceFound = false
        guard let lines = style.source(withIdentifier: Self.sourceId) as? MLNShapeSource,
              let arrows = style.source(withIdentifier: Self.arrowSourceId) as? MLNShapeSource else {
            return
        }
        sourceFound = true
        // Homogeneous collections, like the other shape sources: a mixed array of point and
        // polyline features bridged to an empty collection and nothing was drawn.
        var polylines: [MLNPolylineFeature] = []
        var points: [MLNPointFeature] = []
        for mark in data.paintedMarks {
            if mark.kind == "ARROW" {
                guard let point = mark.coordinates.first else { continue }
                let feature = MLNPointFeature()
                feature.coordinate = point.coordinate
                feature.attributes = [
                    "kind": "ARROW",
                    "icon": mark.icon.isEmpty ? "arrow-through" : mark.icon,
                    "rot": NSNumber(value: mark.rotation),
                ]
                points.append(feature)
                continue
            }
            guard mark.coordinates.count >= 2 else { continue }
            var coordinates = mark.coordinates.map(\.coordinate)
            let feature = MLNPolylineFeature(
                coordinates: &coordinates, count: UInt(coordinates.count))
            feature.attributes = ["kind": mark.kind, "w": NSNumber(value: mark.width)]
            polylines.append(feature)
        }
        lastBuilt = polylines.count + points.count
        lines.shape = MLNShapeCollectionFeature(shapes: polylines)
        arrows.shape = MLNShapeCollectionFeature(shapes: points)
    }

    private func ensureLayers(_ style: MLNStyle, pack: Bool) {
        let prefix = pack ? "vela-paint-pack" : "vela-paint"
        guard layer(style, "\(prefix)-surface") == nil else { return }
        guard let source = style.source(withIdentifier: pack ? Self.packSourceId : Self.sourceId) else {
            return
        }
        let key = pack ? "k" : "kind"
        var previous: MLNStyleLayer?
        func add(_ layer: MLNStyleLayer) {
            if let previous {
                style.insertLayer(layer, above: previous)
            } else if let anchor = MapLayers.labelAnchor(in: style) {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
            previous = layer
        }

        for (kind, suffix) in Self.lineKinds {
            let line = MLNLineStyleLayer(identifier: "\(prefix)-\(suffix)", source: source)
            line.predicate = NSPredicate(format: "%K == %@", key, kind)
            line.lineColor = NSExpression(forConstantValue: color(kind: kind))
            line.lineCap = NSExpression(forConstantValue: "round")
            line.lineJoin = NSExpression(forConstantValue: "round")
            switch kind {
            case "LANE":
                line.lineDashPattern = NSExpression(forConstantValue: [2.0, 2.5])
            case "CROSSWALK":
                line.lineDashPattern = NSExpression(forConstantValue: [1.0, 1.0])
            case "BUS":
                line.lineOpacity = NSExpression(forConstantValue: 0.28)
            case "BIKE":
                line.lineOpacity = NSExpression(forConstantValue: 0.9)
            default:
                break
            }
            if pack && (kind == "SURFACE" || kind == "MEDIAN" || kind == "BUS" || kind == "BIKE"
                || kind == "LANE" || kind == "CENTER") {
                line.lineOffset = offsetExpression(key: "off")
            }
            add(line)
        }

        let arrowSource = style.source(withIdentifier: pack ? Self.packSourceId : Self.arrowSourceId)
            ?? source
        let arrow = MLNSymbolStyleLayer(identifier: "\(prefix)-arrow", source: arrowSource)
        arrow.predicate = NSPredicate(format: "%K == %@", key, "ARROW")
        arrow.iconImageName = NSExpression(forKeyPath: "icon")
        arrow.iconRotation = NSExpression(forKeyPath: "rot")
        arrow.iconRotationAlignment = NSExpression(forConstantValue: "map")
        arrow.iconPitchAlignment = NSExpression(forConstantValue: "map")
        arrow.iconAllowsOverlap = NSExpression(forConstantValue: true)
        arrow.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        add(arrow)
    }

    /// Meter widths become screen points at the current zoom, like Android's `meters` expression.
    private func updateWidths(_ style: MLNStyle, zoom: Double) {
        let bucket = (zoom * 2).rounded() / 2
        guard bucket != lastWidthBucket else { return }
        lastWidthBucket = bucket
        let perMeter = pow(2.0, bucket) / Self.mPerPointAtZ0
        let widths: [String: Double] = [
            "center": max(1.0, 0.3 * perMeter),
            "lane": min(2.4, max(0.8, 0.18 * perMeter)),
            "bike": max(1.2, 1.2 * perMeter),
            "crosswalk": max(2.4, 3.0 * perMeter),
            "stop": max(1.2, 0.6 * perMeter),
        ]
        for (suffix, width) in widths {
            for prefix in ["vela-paint", "vela-paint-pack"] {
                let line = layer(style, "\(prefix)-\(suffix)") as? MLNLineStyleLayer
                line?.lineWidth = NSExpression(forConstantValue: width)
                if prefix == "vela-paint-pack" {
                    line?.lineOffset = scaled(attribute: "off", factor: perMeter)
                }
            }
        }
        for (suffix, attribute) in [("surface", "w"), ("median", "w"), ("bus", "w")] {
            for prefix in ["vela-paint", "vela-paint-pack"] {
                guard let line = layer(style, "\(prefix)-\(suffix)") as? MLNLineStyleLayer else {
                    continue
                }
                line.lineWidth = scaled(attribute: attribute, factor: perMeter)
            }
        }
        let iconSize = max(0.12, Self.arrowGroundM * perMeter / Self.arrowImageHeight)
        for id in ["vela-paint-arrow", "vela-paint-pack-arrow"] {
            (layer(style, id) as? MLNSymbolStyleLayer)?.iconScale =
                NSExpression(forConstantValue: iconSize)
        }
    }

    private func scaled(attribute: String, factor: Double) -> NSExpression {
        NSExpression(forFunction: "multiply:by:", arguments: [
            NSExpression(forKeyPath: attribute),
            NSExpression(forConstantValue: factor),
        ])
    }

    private func offsetExpression(key: String) -> NSExpression {
        let factor = pow(2.0, max(lastWidthBucket, Self.minZoom)) / Self.mPerPointAtZ0
        return scaled(attribute: key, factor: factor)
    }

    private func color(kind: String) -> UIColor {
        switch kind {
        case "SURFACE": return UIColor(rgb: 0xD7DDE5)
        case "MEDIAN": return UIColor(rgb: 0xE4E8EE)
        case "BUS": return UIColor(rgb: 0xB04A3A)
        case "CENTER": return UIColor(rgb: 0xF2C200)
        case "BIKE": return UIColor(rgb: 0x86CFA0)
        default: return .white
        }
    }

    // MARK: - Arrow images

    /// One image per turn combination, drawn here rather than shipped in a sprite. A white outline
    /// under the dark glyph keeps the arrow readable on both pale and dark road surfaces.
    private func installArrowImages(_ style: MLNStyle) {
        guard !imagesInstalled else { return }
        let parts = ["uturn", "left", "through", "right"]
        for mask in 1..<16 {
            let set = parts.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let name = "arrow-" + set.joined(separator: "-")
            style.setImage(arrowImage(parts: Set(set)), forName: name)
        }
        imagesInstalled = true
    }

    private func arrowImage(parts: Set<String>) -> UIImage {
        let size = CGSize(width: 72, height: Self.arrowImageHeight)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let c = context.cgContext
            for pass in 0..<2 {
                let colour = pass == 0 ? UIColor.white : UIColor(rgb: 0x37474F)
                c.setStrokeColor(colour.cgColor)
                c.setFillColor(colour.cgColor)
                c.setLineWidth(pass == 0 ? 16 : 11)
                c.setLineCap(.butt)
                c.setLineJoin(.round)
                drawArrow(c, parts: parts, width: size.width, height: size.height)
            }
        }
    }

    private func drawArrow(_ c: CGContext, parts: Set<String>, width w: CGFloat, height h: CGFloat) {
        let cx = w / 2, base = h * 0.97, fork = h * 0.55, head = w * 0.24
        let stemTop = parts.contains("through") ? h * 0.16 : fork
        c.beginPath()
        c.move(to: CGPoint(x: cx, y: base))
        c.addLine(to: CGPoint(x: cx, y: stemTop))
        c.strokePath()
        if parts.contains("through") { headAt(c, x: cx, y: h * 0.12, angle: -90, size: head) }
        if parts.contains("left") {
            let ex = w * 0.16, ey = fork - h * 0.16
            c.beginPath()
            c.move(to: CGPoint(x: cx, y: fork + h * 0.06))
            c.addQuadCurve(to: CGPoint(x: ex + head * 0.6, y: ey), control: CGPoint(x: cx, y: ey))
            c.strokePath()
            headAt(c, x: ex + head * 0.2, y: ey, angle: 180, size: head)
        }
        if parts.contains("right") {
            let ex = w * 0.84, ey = fork - h * 0.16
            c.beginPath()
            c.move(to: CGPoint(x: cx, y: fork + h * 0.06))
            c.addQuadCurve(to: CGPoint(x: ex - head * 0.6, y: ey), control: CGPoint(x: cx, y: ey))
            c.strokePath()
            headAt(c, x: ex - head * 0.2, y: ey, angle: 0, size: head)
        }
        if parts.contains("uturn") {
            let lx = w * 0.2
            c.beginPath()
            c.move(to: CGPoint(x: cx, y: fork))
            c.addCurve(to: CGPoint(x: lx, y: fork),
                       control1: CGPoint(x: cx, y: h * 0.15),
                       control2: CGPoint(x: lx, y: h * 0.15))
            c.addLine(to: CGPoint(x: lx, y: fork + h * 0.12))
            c.strokePath()
            headAt(c, x: lx, y: fork + h * 0.16, angle: 90, size: head)
        }
    }

    private func headAt(_ c: CGContext, x: CGFloat, y: CGFloat, angle: CGFloat, size: CGFloat) {
        let a = angle * .pi / 180
        c.beginPath()
        c.move(to: CGPoint(x: x + cos(a) * size, y: y + sin(a) * size))
        c.addLine(to: CGPoint(x: x + cos(a + 2.4) * size, y: y + sin(a + 2.4) * size))
        c.addLine(to: CGPoint(x: x + cos(a - 2.4) * size, y: y + sin(a - 2.4) * size))
        c.closePath()
        c.fillPath()
    }

    private func layer(_ style: MLNStyle, _ id: String) -> MLNStyleLayer? {
        style.layers.first { $0.identifier == id }
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
