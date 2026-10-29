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
        /// The stretch's next stop, the direction the panel shows.
        var direction: String = ""
    }

    private static let sourceId = "vela-transit-vehicles"
    private static let layerId = "vela-transit-vehicles-symbol"
    /// An almost invisible circle over each dot. MapLibre does not reliably return a symbol from
    /// `visibleFeatures`, so the tap query reads this circle instead; its 16 pt radius is the
    /// finger box the dot already deserves.
    static let hitLayerId = "vela-transit-vehicles-hit"
    private static let imagePrefix = "vela-transit-vehicle"

    /// The identifier prefix of the vehicle layer. MAP-TAP registers it as a tap family, next to
    /// the line layers: a tap on a dot opens the same line sheet as a tap on its line.
    static let layerPrefix = "vela-transit-vehicles"

    private var vehicles: [Vehicle] = []

    /// The markers actually installed in the style.
    var drawnCount: Int { vehicles.count }

    /// True only when every drawn marker is the estimate Vela computed, never a GPS measurement.
    var allEstimated: Bool { !vehicles.isEmpty && vehicles.allSatisfy(\.estimated) }

    /// The nearest dot in screen points. `visibleFeatures` is not reliable for a symbol, so the
    /// controller uses this geometry as the tap's final fallback.
    func nearest(to point: CGPoint, in mapView: MLNMapView,
                 tolerance: CGFloat = MapTapRegistry.denseTolerance) -> Vehicle? {
        var best: Vehicle?
        var bestDistance = tolerance
        for vehicle in vehicles {
            let screen = mapView.convert(vehicle.coordinate, toPointTo: mapView)
            let distance = hypot(screen.x - point.x, screen.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                best = vehicle
            }
        }
        return best
    }

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
                "direction": vehicle.direction,
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
        // The style's glyph stack. Without an explicit font MapLibre drops the whole symbol,
        // icon included, which left the dots invisible while the layer was present.
        layer.textFont = NSExpression(forConstantValue: ["Noto Sans Regular"])
        layer.textFontSize = NSExpression(forConstantValue: 10)
        layer.textColor = NSExpression(forConstantValue: UIColor.label)
        layer.textHaloColor = NSExpression(forConstantValue: UIColor.systemBackground)
        layer.textHaloWidth = NSExpression(forConstantValue: 1.4)
        layer.textAnchor = NSExpression(forConstantValue: "top")
        layer.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.0)))
        layer.textAllowsOverlap = NSExpression(forConstantValue: true)
        insert(layer, in: style)
        // The query target: a circle is returned by `visibleFeatures` where a symbol is not. It
        // sits directly above the symbol, still below the map labels, and is effectively invisible.
        let hit = MLNCircleStyleLayer(identifier: Self.hitLayerId, source: source)
        hit.circleRadius = NSExpression(forConstantValue: 16)
        hit.circleColor = NSExpression(forConstantValue: UIColor.black.withAlphaComponent(0.01))
        hit.circleStrokeWidth = NSExpression(forConstantValue: 0)
        style.insertLayer(hit, above: layer)
    }

    func clear(on style: MLNStyle?) {
        vehicles = []
        if let style { remove(on: style) }
    }

    private func insert(_ layer: MLNStyleLayer, in style: MLNStyle) {
        // Insert under the topmost label layer, not under the first symbol layer. The first symbol
        // layer can sit below the basemap's fills, where a symbol source is installed but never
        // painted or returned by `visibleFeatures`.
        if let label = style.layers.last(where: { $0 is MLNSymbolStyleLayer }) {
            style.insertLayer(layer, below: label)
        } else {
            style.addLayer(layer)
        }
    }

    private func remove(on style: MLNStyle) {
        if let layer = style.layer(withIdentifier: Self.hitLayerId) { style.removeLayer(layer) }
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
                estimated: model.estimated,
                direction: model.headsign)
        }
        layer.set(drawn, on: style)
    }

    static func clear(on style: MLNStyle?) {
        layer.clear(on: style)
    }
}
