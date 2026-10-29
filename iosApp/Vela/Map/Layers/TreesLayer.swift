import CoreGraphics
import Foundation
import MapLibre
import UIKit

/// TREES-LAYER: the map's flat canopy. MapLibre Native has no 3D model or billboard primitive, so
/// this is deliberately not a 3D tree: isolated OSM trees become soft discs on the ground, with a
/// light shadow, and forest, wood and park polygons get a local canopy tint and pattern.
///
/// Everything is an in-memory shape source or a repaint of vector layers already present: no URL
/// joins the style, so a downloaded region keeps drawing the polygons and adds no remote host.
enum TreesLayer {
    static let minZoom = 17.0
    static let sourceId = "vela-trees-src"
    static let shadowLayerId = "vela-tree-shadow"
    static let canopyLayerId = "vela-tree-canopy"
    static let canopyFillLayerId = "vela-canopy-fill"
    static let patternName = "vela-canopy-pattern"

    /// The Liberty layers that carry vegetation. Their original paint is restored when the switch
    /// goes off, so the basemap looks exactly as it did before the layer was ever used.
    private static let vegetationIds = ["landcover_wood", "landcover_grass", "park"]

    private struct FillPaint {
        let color: NSExpression?
        let opacity: NSExpression?
        let pattern: NSExpression?
    }

    private static var originals: [ObjectIdentifier: [String: FillPaint]] = [:]
    private static var lastZoomBucket = -1.0
    private static var lastPointCount = -1

    /// The metres one screen point covers, at [zoom] and [latitude]. Same constant as the camera
    /// cones, so a tree and a camera wedge at the same spot agree on ground scale.
    private static let metersPerPointAtEquator = 156_543.03392

    private static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
        let clamped = max(0.0, min(zoom, 24.0))
        let value = metersPerPointAtEquator * cos(latitude * .pi / 180) / pow(2, clamped)
        return value.isFinite && value > 0 ? value : 1.0
    }

    /// Radius in points for one tree. A tagged crown gives its real ground size; without a crown
    /// the disc is a fixed visual mark, never a guessed "large tree". The cap stops a 40 m crown
    /// from covering the street grid at z19.
    static func radius(crownM: Double, zoom: Double, latitude: Double) -> Double {
        if crownM <= 0 {
            return zoom >= 19 ? 5.5 : (zoom >= 18 ? 4.5 : 4.0)
        }
        let raw = (crownM / 2) / metersPerPoint(zoom: zoom, latitude: latitude)
        return min(34.0, max(2.5, raw))
    }

    static func visible(enabled: Bool, zoom: Double) -> Bool {
        enabled && zoom + 0.001 >= minZoom
    }

    /// Rebuilds the point shapes at [zoom], paints or restores the vegetation, and updates the two
    /// circle layers. Called when the layer data changes and on each camera idle.
    static func apply(
        points: [LayerTree], enabled: Bool, zoom: Double, style: MLNStyle
    ) {
        installVegetation(enabled: enabled, style: style)
        updateShapes(points: points, zoom: zoom, style: style)
        setVisible(enabled: enabled, zoom: zoom, style: style)
    }

    /// Cheap per-camera-idle path: the disc radii only depend on the zoom bucket, so a pan with no
    /// zoom change rebuilds nothing.
    static func updateVisibility(
        points: [LayerTree], enabled: Bool, zoom: Double, style: MLNStyle
    ) {
        // Before the first camera report the zoom is 0. A switch flipped while the map is still
        // must not hide the discs until the next gesture: use the gate itself as the floor.
        let effective = zoom > 0 ? zoom : minZoom
        let bucket = (effective * 2).rounded() / 2
        if bucket != lastZoomBucket || points.count != lastPointCount {
            updateShapes(points: points, zoom: effective, style: style)
        }
        setVisible(enabled: enabled, zoom: effective, style: style)
    }

    /// Adds the two circle layers once per loaded style, below the first label layer so street
    /// names stay readable over the canopy.
    static func ensureLayers(style: MLNStyle) {
        guard style.layer(withIdentifier: canopyLayerId) == nil,
              let source = style.source(withIdentifier: sourceId) else { return }
        let anchor = MapLayers.labelAnchor(in: style)

        let shadow = MLNCircleStyleLayer(identifier: shadowLayerId, source: source)
        shadow.circleRadius = NSExpression(forKeyPath: "shadowRadius")
        shadow.circleColor = NSExpression(forConstantValue: UIColor(red: 0.10, green: 0.18,
                                                                   blue: 0.08, alpha: 1))
        shadow.circleOpacity = NSExpression(forConstantValue: 0.22)
        shadow.circleBlur = NSExpression(forConstantValue: 1.1)
        shadow.circleTranslation = NSExpression(
            forConstantValue: NSValue(cgVector: CGVector(dx: 1.4, dy: 1.9)))
        shadow.isVisible = false

        let canopy = MLNCircleStyleLayer(identifier: canopyLayerId, source: source)
        canopy.circleRadius = NSExpression(forKeyPath: "radius")
        canopy.circleColor = NSExpression(forKeyPath: "tone")
        canopy.circleOpacity = NSExpression(forConstantValue: 0.88)
        canopy.circleBlur = NSExpression(forConstantValue: 0.65)
        canopy.circleStrokeColor = NSExpression(forConstantValue: UIColor(red: 0.16, green: 0.30,
                                                                         blue: 0.13, alpha: 1))
        canopy.circleStrokeWidth = NSExpression(forConstantValue: 0.6)
        canopy.circleStrokeOpacity = NSExpression(forConstantValue: 0.45)
        canopy.isVisible = false

        for layer in [shadow, canopy] {
            if let anchor {
                style.insertLayer(layer, below: anchor)
            } else {
                style.addLayer(layer)
            }
        }

        // Urban parks are often `landuse=park` rather than the `park` layer; without this fill a
        // city park stays white. It is inserted under the first road layer so roads keep their
        // casing and labels stay on top.
        if style.layer(withIdentifier: canopyFillLayerId) == nil,
           let base = style.layers.first(where: { $0.identifier == "landcover_wood" })
            as? MLNFillStyleLayer,
           let sourceId = base.sourceIdentifier,
           let source = style.source(withIdentifier: sourceId) {
            let fill = MLNFillStyleLayer(identifier: canopyFillLayerId, source: source)
            fill.sourceLayerIdentifier = "landuse"
            fill.predicate = NSPredicate(
                format: "class IN %@",
                ["park", "forest", "wood", "grass", "meadow", "recreation_ground",
                 "village_green", "scrub", "nature_reserve"])
            fill.fillColor = NSExpression(forConstantValue: UIColor(red: 0.48, green: 0.66,
                                                                   blue: 0.40, alpha: 1))
            fill.fillOpacity = NSExpression(forConstantValue: 0.55)
            fill.isVisible = false
            let road = style.layers.first(where: { $0.identifier == "tunnel_motorway_link_casing" })
                ?? style.layers.first(where: { $0.identifier == "park" })
            if let road {
                style.insertLayer(fill, below: road)
            } else {
                style.addLayer(fill)
            }
        }
    }

    private static func setVisible(enabled: Bool, zoom: Double, style: MLNStyle) {
        let on = visible(enabled: enabled, zoom: zoom)
        style.layer(withIdentifier: canopyLayerId)?.isVisible = on
        style.layer(withIdentifier: shadowLayerId)?.isVisible = on
        style.layer(withIdentifier: canopyFillLayerId)?.isVisible = enabled
    }

    /// Builds one feature per tree, with the radius already in points for this zoom. Attributes are
    /// computed here rather than with a style expression so crown size, the zoom and the latitude
    /// stay in one testable formula.
    private static func updateShapes(points: [LayerTree], zoom: Double, style: MLNStyle) {
        lastZoomBucket = (zoom * 2).rounded() / 2
        lastPointCount = points.count
        guard let source = style.source(withIdentifier: sourceId) as? MLNShapeSource else { return }
        let features = points.map { tree -> MLNPointFeature in
            let feature = MLNPointFeature()
            feature.coordinate = tree.coordinate.coordinate
            let r = radius(crownM: tree.crownM, zoom: zoom, latitude: tree.coordinate.lat)
            feature.attributes = [
                "radius": NSNumber(value: r),
                "shadowRadius": NSNumber(value: r * 1.12),
                "tone": UIColor(red: 0.27, green: 0.44, blue: 0.23, alpha: 1),
            ]
            return feature
        }
        source.shape = features.isEmpty ? nil : MLNShapeCollectionFeature(shapes: features)
    }

    /// Forest and park fills read as canopy from above. The colours are constants, the wood gets a
    /// locally generated speckle so a large forest is not one flat green; both need no request.
    private static func installVegetation(enabled: Bool, style: MLNStyle) {
        let key = ObjectIdentifier(style)
        var paints = originals[key] ?? [:]
        for id in vegetationIds {
            guard let fill = style.layer(withIdentifier: id) as? MLNFillStyleLayer else { continue }
            if paints[id] == nil {
                paints[id] = FillPaint(color: fill.fillColor, opacity: fill.fillOpacity,
                                       pattern: fill.fillPattern)
            }
            if enabled {
                fill.fillColor = NSExpression(forConstantValue: canopyColor(id))
                fill.fillOpacity = NSExpression(forConstantValue: 0.92)
                if id == "landcover_wood" {
                    installPattern(style)
                    fill.fillPattern = NSExpression(forConstantValue: patternName)
                }
            } else if let original = paints[id] {
                fill.fillColor = original.color
                fill.fillOpacity = original.opacity
                fill.fillPattern = original.pattern
            }
        }
        originals[key] = paints
    }

    private static func canopyColor(_ id: String) -> UIColor {
        switch id {
        case "landcover_wood":
            return UIColor(red: 0.33, green: 0.49, blue: 0.29, alpha: 1)
        case "park":
            return UIColor(red: 0.58, green: 0.74, blue: 0.49, alpha: 1)
        default:
            return UIColor(red: 0.66, green: 0.80, blue: 0.57, alpha: 1)
        }
    }

    /// A 64 px tileable speckle, generated in memory once per loaded style. It is decoration, not
    /// a species map: it only breaks the flat fill and gives the wood a canopy texture.
    private static func installPattern(_ style: MLNStyle) {
        guard style.image(forName: patternName) == nil else { return }
        let size = 64
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 33) % 10_000) / 10_000.0
            }
            for _ in 0 ..< 74 {
                let cx = next() * Double(size)
                let cy = next() * Double(size)
                let r = 2.0 + next() * 4.5
                let dark = next() < 0.62
                let color = dark
                    ? UIColor(red: 0.18, green: 0.30, blue: 0.16, alpha: 0.13)
                    : UIColor(red: 0.85, green: 0.93, blue: 0.76, alpha: 0.10)
                cg.setFillColor(color.cgColor)
                // Draw the blob at the nine wrapped positions so the tile has no visible seam.
                for dx in [-size, 0, size] {
                    for dy in [-size, 0, size] {
                        let rect = CGRect(x: cx + Double(dx) - r, y: cy + Double(dy) - r,
                                          width: r * 2, height: r * 2)
                        cg.fillEllipse(in: rect)
                    }
                }
            }
        }
        style.setImage(image, forName: patternName)
    }
}
