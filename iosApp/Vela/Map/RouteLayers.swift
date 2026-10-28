import CoreLocation
import MapLibre
import UIKit

/// The routes on the map: alternates faded under the selected one, its live traffic stretches on
/// top, and the trip's two ends and intermediate stops (SPEC 4.8, the preview's colors on the light map). Above the roads
/// and bridges, under the labels.
final class RouteLayers {
    static let altLayer = "vela-route-alt"

    private static let altSource = "vela-route-alt"
    private static let selectedSource = "vela-route-selected"
    private static let trafficSource = "vela-route-traffic"
    private static let endsSource = "vela-route-ends"

    private var lines: [RouteLine] = []
    private var selected = -1
    private var ends: (CLLocationCoordinate2D, CLLocationCoordinate2D)?
    private var stops: [CLLocationCoordinate2D] = []

    func set(_ lines: [RouteLine], selected: Int, on style: MLNStyle?) {
        self.lines = lines
        self.selected = selected
        let active = lines.first(where: { $0.index == selected }) ?? lines.first
        if let first = active?.coordinates.first, let last = active?.coordinates.last {
            ends = (first, last)
        } else {
            ends = nil
        }
        stops = active?.stops ?? []
        if let style { apply(to: style) }
    }

    /// Re-adds the layers after a style load.
    func apply(to style: MLNStyle) {
        ensureLayers(in: style)
        let alt: [MLNShape & MLNFeature] = lines.filter { $0.index != selected && $0.coordinates.count >= 2 }.map { line -> (MLNShape & MLNFeature) in
            var coords = line.coordinates
            let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
            f.attributes = ["index": line.index]
            return f
        }
        (style.source(withIdentifier: Self.altSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: alt)

        var picked: [MLNShape & MLNFeature] = []
        var traffic: [MLNShape & MLNFeature] = []
        if let line = lines.first(where: { $0.index == selected }), line.coordinates.count >= 2 {
            var coords = line.coordinates
            picked.append(MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count)))
            for t in line.traffic where t.coordinates.count >= 2 {
                var tc = t.coordinates
                let f = MLNPolylineFeature(coordinates: &tc, count: UInt(tc.count))
                f.attributes = ["level": t.level]
                traffic.append(f)
            }
        }
        (style.source(withIdentifier: Self.selectedSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: picked)
        (style.source(withIdentifier: Self.trafficSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: traffic)

        var points: [MLNShape & MLNFeature] = []
        if let ends {
            let start = MLNPointFeature()
            start.coordinate = ends.0
            start.attributes = ["end": 0]
            let stop = MLNPointFeature()
            stop.coordinate = ends.1
            stop.attributes = ["end": 1]
            points = [start, stop]
        }
        for coordinate in stops {
            let point = MLNPointFeature()
            point.coordinate = coordinate
            point.attributes = ["end": 2]
            points.append(point)
        }
        (style.source(withIdentifier: Self.endsSource) as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: points)
    }

    private func ensureLayers(in style: MLNStyle) {
        guard style.source(withIdentifier: Self.altSource) == nil else { return }
        let alt = MLNShapeSource(identifier: Self.altSource, shape: nil, options: nil)
        let sel = MLNShapeSource(identifier: Self.selectedSource, shape: nil, options: nil)
        let traffic = MLNShapeSource(identifier: Self.trafficSource, shape: nil, options: nil)
        let endsSource = MLNShapeSource(identifier: Self.endsSource, shape: nil, options: nil)
        [alt, sel, traffic, endsSource].forEach { style.addSource($0) }

        let altLine = line("vela-route-alt", alt, color: UIColor(rgb: 0x7FA9F0), width: 6.3)
        let altEdge = line("vela-route-alt-edge", alt, color: UIColor(rgb: 0x3566C4), width: 1.6)
        altEdge.lineGapWidth = NSExpression(forConstantValue: 6.3)
        let casing = line("vela-route-casing", sel, color: UIColor(rgb: 0x1A57C2), width: 9)
        let main = line("vela-route-selected", sel, color: UIColor(rgb: 0x2F7BF0), width: 6.5)
        var layers: [MLNStyleLayer] = [altLine, altEdge, casing, main]
        let levels: [(String, String, UInt32)] = [
            ("vela-route-traffic-1", "level == 1", 0xF2A33A),
            ("vela-route-traffic-2", "level == 2", 0xE5483B),
            ("vela-route-traffic-3", "level >= 3", 0x9E1C1C),
        ]
        for (id, predicate, rgb) in levels {
            let t = line(id, traffic, color: UIColor(rgb: rgb), width: 6.5)
            t.predicate = NSPredicate(format: predicate)
            layers.append(t)
        }
        let endsLayer = MLNCircleStyleLayer(identifier: "vela-route-ends", source: endsSource)
        endsLayer.circleRadius = NSExpression(forConstantValue: 7)
        endsLayer.circleColor = NSExpression(
            forConditional: NSPredicate(format: "end == 2"),
            trueExpression: NSExpression(forConstantValue: UIColor(rgb: 0xF2A33A)),
            falseExpression: NSExpression(
                forConditional: NSPredicate(format: "end == 1"),
                trueExpression: NSExpression(forConstantValue: UIColor(rgb: 0xD93025)),
                falseExpression: NSExpression(forConstantValue: UIColor.white)))
        endsLayer.circleStrokeColor = NSExpression(
            forConditional: NSPredicate(format: "end != 0"),
            trueExpression: NSExpression(forConstantValue: UIColor.white),
            falseExpression: NSExpression(forConstantValue: UIColor(rgb: 0x1A57C2)))
        endsLayer.circleStrokeWidth = NSExpression(forConstantValue: 3)
        layers.append(endsLayer)

        if let below = labelLayer(in: style) {
            for layer in layers { style.insertLayer(layer, below: below) }
        } else {
            for layer in layers { style.addLayer(layer) }
        }
    }

    private func line(_ id: String, _ source: MLNSource, color: UIColor, width: Double) -> MLNLineStyleLayer {
        let l = MLNLineStyleLayer(identifier: id, source: source)
        l.lineColor = NSExpression(forConstantValue: color)
        l.lineWidth = NSExpression(forConstantValue: width)
        l.lineCap = NSExpression(forConstantValue: "round")
        l.lineJoin = NSExpression(forConstantValue: "round")
        return l
    }

    /// The first symbol layer after the last bridge layer (SPEC 4.8), else the first symbol layer.
    private func labelLayer(in style: MLNStyle) -> MLNStyleLayer? {
        let all = style.layers
        let lastBridge = all.lastIndex(where: { $0.identifier.hasPrefix("bridge") }) ?? -1
        return all[(lastBridge + 1)...].first(where: { $0 is MLNSymbolStyleLayer })
            ?? all.first(where: { $0 is MLNSymbolStyleLayer })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
