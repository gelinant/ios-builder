import CoreLocation
import MapLibre
import UIKit
import VelaCore

/// The estimated vehicle markers of TRANSIT-INTERP: one in-memory symbol layer, a colored disk
/// with a direction chevron and the line badge under it. It draws descriptors the model already
/// interpolated from live times; it never fetches, so it stays remote-free inside a downloaded
/// region. The API has no vehicle GPS, so [Vehicle.estimated] is always true and is not drawn as
/// a live or GPS mark.
final class TransitVehicleLayer {
    /// One marker. [colorHex] is already resolved (agency color, else mode color).
    struct Vehicle {
        let id: String
        let label: String
        let colorHex: String
        let bearing: Double
        let coordinate: CLLocationCoordinate2D
        let estimated: Bool
    }

    private static let sourceId = "vela-transit-vehicles"
    private static let layerId = "vela-transit-vehicles-symbol"
    private static let imagePrefix = "vela-transit-vehicle"

    private var vehicles: [Vehicle] = []

    func set(_ vehicles: [Vehicle], on style: MLNStyle?) {
        self.vehicles = vehicles
        if let style { apply(to: style) }
    }

    /// Rebuilds the source and the layer after a style load or a new estimate. The layer sits
    /// above the transit lines when they exist, and below the map labels in every case.
    func apply(to style: MLNStyle) {
        remove(on: style)
        guard !vehicles.isEmpty else { return }
        var features: [MLNShape & MLNFeature] = []
        for vehicle in vehicles {
            let image = imageName(for: vehicle.colorHex)
            installImage(vehicle.colorHex, name: image, in: style)
            let point = MLNPointFeature()
            point.coordinate = vehicle.coordinate
            point.attributes = [
                "icon": image,
                "bearing": vehicle.bearing,
                "label": vehicle.label,
                "estimated": vehicle.estimated ? 1 : 0,
            ]
            features.append(point)
        }
        let source = MLNShapeSource(
            identifier: Self.sourceId,
            shape: MLNShapeCollectionFeature(shapes: features),
            options: nil)
        style.addSource(source)
        let layer = MLNSymbolStyleLayer(identifier: Self.layerId, source: source)
        layer.iconImageName = NSExpression(forKeyPath: "icon")
        layer.iconRotation = NSExpression(forKeyPath: "bearing")
        layer.iconRotationAlignment = NSExpression(forConstantValue: "map")
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.text = NSExpression(forKeyPath: "label")
        layer.textFontSize = NSExpression(forConstantValue: 10)
        layer.textColor = NSExpression(forConstantValue: UIColor.label)
        layer.textHaloColor = NSExpression(forConstantValue: UIColor.systemBackground)
        layer.textHaloWidth = NSExpression(forConstantValue: 1.4)
        layer.textAnchor = NSExpression(forConstantValue: "top")
        layer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.0)))
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        insert(layer, in: style)
    }

    func clear(on style: MLNStyle?) {
        vehicles = []
        if let style { remove(on: style) }
    }

    private func insert(_ layer: MLNStyleLayer, in style: MLNStyle) {
        if let line = style.layers.last(where: { $0.identifier.hasPrefix("vela-transit-line") }) {
            style.insertLayer(layer, above: line)
        } else if let label = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
            style.insertLayer(layer, below: label)
        } else {
            style.addLayer(layer)
        }
    }

    private func remove(on style: MLNStyle) {
        if let layer = style.layer(withIdentifier: Self.layerId) { style.removeLayer(layer) }
        if let source = style.source(withIdentifier: Self.sourceId) { style.removeSource(source) }
    }

    private func imageName(for colorHex: String) -> String {
        "\(Self.imagePrefix)-\(colorHex.lowercased().replacingOccurrences(of: "#", with: ""))"
    }

    /// A 26 pt disk in the line color, white border, white chevron pointing up. `iconRotation`
    /// turns it along the stretch, so a tram and a bus show their direction without a second
    /// glyph. Drawn locally, cached by color.
    private func installImage(_ colorHex: String, name: String, in style: MLNStyle) {
        if style.image(forName: name) != nil { return }
        let side: CGFloat = 26
        let size = CGSize(width: side, height: side)
        let fill = UIColor(transitHex: colorHex) ?? .systemBlue
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let circle = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            context.cgContext.setFillColor(fill.cgColor)
            context.cgContext.fillEllipse(in: circle)
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(1.6)
            context.cgContext.strokeEllipse(in: circle)
            // A chevron, drawn as a path so no SF Symbol availability is involved.
            let path = UIBezierPath()
            path.move(to: CGPoint(x: side / 2, y: 6.5))
            path.addLine(to: CGPoint(x: side / 2 + 4.2, y: 13.5))
            path.addLine(to: CGPoint(x: side / 2 - 4.2, y: 13.5))
            path.close()
            UIColor.white.setFill()
            path.fill()
        }
        style.setImage(image, forName: name)
    }
}

/// The vehicle layer's one entry point, next to `TransitOverlays`. `TransitLinesLayer.apply`
/// installs it on the same style pass; the panel calls `set` when the estimates change.
///
///     TransitVehicleOverlays.set(
///         models: [TransitVehicle], on: mapView.style)
///
/// A style load after that pass needs the same `apply(to:)` call the lines already get.
enum TransitVehicleOverlays {
    static let layer = TransitVehicleLayer()

    static func apply(to style: MLNStyle) {
        layer.apply(to: style)
    }

    static func set(models: [TransitVehicle], on style: MLNStyle?) {
        let drawn = models.map { model in
            TransitVehicleLayer.Vehicle(
                id: model.id,
                label: model.label,
                colorHex: model.colorHex,
                bearing: model.bearing,
                coordinate: CLLocationCoordinate2D(latitude: model.lat, longitude: model.lng),
                estimated: model.estimated)
        }
        layer.set(drawn, on: style)
    }

    static func clear(on style: MLNStyle?) {
        layer.clear(on: style)
    }
}
