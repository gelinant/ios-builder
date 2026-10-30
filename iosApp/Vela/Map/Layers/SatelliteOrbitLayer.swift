import CoreLocation
import Foundation
import MapLibre
import VelaCore

/// The selected satellite's orbit, drawn as a ground track under the map labels, with a larger
/// marker on the satellite itself. A track crosses the antimeridian, so it is split into segments
/// before it reaches MapLibre: a line joining longitude 179 to -179 would otherwise run across the
/// whole world.
///
/// The same geometry is valid in Mercator and on the globe: the projection changes the screen
/// position of a latitude and longitude, never the coordinate itself.
enum SatelliteOrbitLayer {
    static let sourceId = "vela-satellite-orbit-src"
    static let layerId = "vela-satellite-orbit"
    static let markerSourceId = "vela-satellite-selected-src"
    static let markerLayerId = "vela-satellite-selected"
    static let trackColor = UIColor(red: 0.96, green: 0.62, blue: 0.06, alpha: 1)

    /// Draws the track and a larger marker on the selected satellite. An empty track removes both.
    static func draw(
        track: [SatelliteTrackPoint],
        selectedLat: Double?,
        selectedLng: Double?,
        in style: MLNStyle
    ) {
        let segments = split(track)
        let lines = segments.map { segment -> MLNShape in
            var coordinates = segment
            return MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
        }
        let lineCollection = MLNShapeCollectionFeature(shapes: lines)
        if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
            source.shape = lines.isEmpty ? nil : lineCollection
        } else if !lines.isEmpty {
            style.addSource(MLNShapeSource(
                identifier: sourceId, shape: lineCollection, options: nil))
        }
        if let source = style.source(withIdentifier: sourceId),
           style.layer(withIdentifier: layerId) == nil {
            let layer = MLNLineStyleLayer(identifier: layerId, source: source)
            layer.lineColor = NSExpression(forConstantValue: trackColor)
            layer.lineWidth = NSExpression(forConstantValue: 1.6)
            layer.lineOpacity = NSExpression(forConstantValue: 0.9)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            insertBelowLabels(layer, in: style)
        }
        style.layer(withIdentifier: layerId)?.isVisible = !lines.isEmpty

        if let selectedLat, let selectedLng {
            let marker = MLNPointFeature()
            marker.coordinate = CLLocationCoordinate2D(latitude: selectedLat, longitude: selectedLng)
            if let source = style.source(withIdentifier: markerSourceId) as? MLNShapeSource {
                source.shape = marker
            } else {
                style.addSource(MLNShapeSource(
                    identifier: markerSourceId, shape: marker, options: nil))
            }
            if let source = style.source(withIdentifier: markerSourceId),
               style.layer(withIdentifier: markerLayerId) == nil {
                let layer = MLNCircleStyleLayer(identifier: markerLayerId, source: source)
                layer.circleColor = NSExpression(forConstantValue: trackColor)
                layer.circleRadius = NSExpression(forConstantValue: 7.0)
                layer.circleStrokeWidth = NSExpression(forConstantValue: 2.0)
                layer.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
                insertBelowLabels(layer, in: style)
            }
            style.layer(withIdentifier: markerLayerId)?.isVisible = true
        } else {
            style.layer(withIdentifier: markerLayerId)?.isVisible = false
        }
    }

    static func remove(from style: MLNStyle) {
        for id in [layerId, markerLayerId] {
            if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
        }
        for id in [sourceId, markerSourceId] {
            if let source = style.source(withIdentifier: id) { style.removeSource(source) }
        }
    }

    /// Splits where two consecutive points jump more than half the world in longitude.
    private static func split(_ track: [SatelliteTrackPoint]) -> [[CLLocationCoordinate2D]] {
        var segments: [[CLLocationCoordinate2D]] = []
        var current: [CLLocationCoordinate2D] = []
        for point in track {
            let coordinate = CLLocationCoordinate2D(latitude: point.latDeg, longitude: point.lonDeg)
            if let last = current.last, abs(last.longitude - coordinate.longitude) > 180.0 {
                if current.count >= 2 { segments.append(current) }
                current = []
            }
            current.append(coordinate)
        }
        if current.count >= 2 { segments.append(current) }
        return segments
    }

    private static func insertBelowLabels(_ layer: MLNStyleLayer, in style: MLNStyle) {
        if let anchor = MapLayers.labelAnchor(in: style) {
            style.insertLayer(layer, below: anchor)
        } else {
            style.addLayer(layer)
        }
    }
}
