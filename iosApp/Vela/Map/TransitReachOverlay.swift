import CoreLocation
import MapLibre
import UIKit
import VelaCore

/// The reachability outline on the map: Vela's convex hull of the reachable stop dots, drawn as a
/// translucent fill with the dots on top. It is explicitly NOT an official isochrone polygon; the
/// panel says so in words.
final class TransitReachOverlay {
    private static let fillId = "vela-transit-reach-fill"
    private static let stopsId = "vela-transit-reach-stops"
    private var area: TransitReachArea?

    func set(_ area: TransitReachArea?, on style: MLNStyle?) {
        self.area = area
        if let style { apply(to: style) }
    }

    func apply(to style: MLNStyle) {
        guard let area else {
            clearLayers(style)
            return
        }
        let hull = area.hull.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        let dots = area.stops.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        // A polygon needs three corners; two points are drawn as dots only.
        var corners = hull
        let polygon: MLNShape? = corners.count >= 3
            ? MLNPolygonFeature(coordinates: &corners, count: UInt(corners.count))
            : nil
        let fillSource: MLNShapeSource
        if let existing = style.source(withIdentifier: Self.fillId) as? MLNShapeSource {
            existing.shape = polygon
            fillSource = existing
        } else {
            fillSource = MLNShapeSource(identifier: Self.fillId, shape: polygon, options: nil)
            style.addSource(fillSource)
            let fill = MLNFillStyleLayer(identifier: Self.fillId, source: fillSource)
            fill.fillColor = NSExpression(forConstantValue: UIColor(red: 0.18, green: 0.45, blue: 0.85, alpha: 1))
            fill.fillOpacity = NSExpression(forConstantValue: 0.16)
            fill.fillOutlineColor = NSExpression(forConstantValue: UIColor(red: 0.18, green: 0.45, blue: 0.85, alpha: 1))
            insert(fill, in: style)
        }
        let stopsSource: MLNShapeSource
        if let existing = style.source(withIdentifier: Self.stopsId) as? MLNShapeSource {
            stopsSource = existing
        } else {
            stopsSource = MLNShapeSource(identifier: Self.stopsId, shape: nil, options: nil)
            style.addSource(stopsSource)
            let circles = MLNCircleStyleLayer(identifier: Self.stopsId, source: stopsSource)
            circles.circleRadius = NSExpression(forConstantValue: 3.5)
            circles.circleColor = NSExpression(forConstantValue: UIColor(red: 0.18, green: 0.45, blue: 0.85, alpha: 1))
            circles.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
            circles.circleStrokeWidth = NSExpression(forConstantValue: 1.5)
            insert(circles, in: style)
        }
        let points: [MLNShape & MLNFeature] = dots.map { coordinate in
            let point = MLNPointFeature()
            point.coordinate = coordinate
            return point
        }
        stopsSource.shape = MLNShapeCollectionFeature(shapes: points)
        // The dots stay above the fill even when a style reload re-adds them in another order.
        if let dotsLayer = style.layer(withIdentifier: Self.stopsId),
           let fillLayer = style.layer(withIdentifier: Self.fillId) {
            style.insertLayer(dotsLayer, above: fillLayer)
        }
    }

    private func insert(_ layer: MLNStyleLayer, in style: MLNStyle) {
        if let label = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
            style.insertLayer(layer, below: label)
        } else {
            style.addLayer(layer)
        }
    }

    private func clearLayers(_ style: MLNStyle) {
        if let layer = style.layer(withIdentifier: Self.stopsId) { style.removeLayer(layer) }
        if let layer = style.layer(withIdentifier: Self.fillId) { style.removeLayer(layer) }
        if let source = style.source(withIdentifier: Self.stopsId) { style.removeSource(source) }
        if let source = style.source(withIdentifier: Self.fillId) { style.removeSource(source) }
    }

    func clear(on style: MLNStyle?) {
        area = nil
        if let style { clearLayers(style) }
    }
}

/// The one entry point the map owns. Two lines are all the map lot has to add:
///
///     // MapController.styleDidLoad(_ style: MLNStyle), after routes.apply(to: style)
///     TransitOverlays.apply(to: style)
///
/// and, wherever the two stores' states arrive:
///
///     TransitOverlays.set(lines: liveLines, reach: area, on: mapView.style)
///
/// Nothing else in MapController, MapScreen or Map/ changes.
enum TransitOverlays {
    static let lines = TransitLinesLayer()
    static let reach = TransitReachOverlay()

    static func apply(to style: MLNStyle) {
        lines.apply(to: style)
        reach.apply(to: style)
    }

    /// The feed: `TransitLiveLinesState.lines` and `TransitReachState.area` from the shared stores.
    static func set(lines models: [TransitLiveLine], reach area: TransitReachArea?, on style: MLNStyle?) {
        let drawn = models.flatMap { model in
            model.paths.compactMap { path -> TransitLinesLayer.Line? in
                let coordinates = path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                guard coordinates.count >= 2 else { return nil }
                return TransitLinesLayer.Line(
                    label: model.label,
                    colorHex: model.colorHex,
                    live: model.live,
                    delayLevel: model.delayLevel,
                    coordinates: coordinates)
            }
        }
        lines.set(drawn, on: style)
        reach.set(area, on: style)
    }

    static func clear(on style: MLNStyle?) {
        lines.clear(on: style)
        reach.clear(on: style)
    }
}
