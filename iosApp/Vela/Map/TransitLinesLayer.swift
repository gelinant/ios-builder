import CoreLocation
import MapLibre
import UIKit
import VelaCore

/// The colored transit lines of T-2 on the map: one source and one line layer per line color, so a
/// line keeps the agency's `routeColor` or, when the feed gave none, the mode color the panel
/// computed. The layer knows nothing about the feed: it draws the descriptors the live-line store
/// already produced. A live badge is not drawn here; the panel carries the words.
final class TransitLinesLayer {
    /// One drawn stretch. [colorHex] is already resolved (feed or mode), [live] is the feed's own
    /// flag, [delayLevel] is `green`, `amber`, `red` or `none`.
    struct Line {
        let label: String
        let colorHex: String
        let live: Bool
        let delayLevel: String
        let coordinates: [CLLocationCoordinate2D]
    }

    private static let prefix = "vela-transit-line"
    private var lines: [Line] = []

    func set(_ lines: [Line], on style: MLNStyle?) {
        self.lines = lines
        if let style { apply(to: style) }
    }

    /// Replaces the layers after a style load, or after new data arrived.
    func apply(to style: MLNStyle) {
        for layer in style.layers where layer.identifier.hasPrefix(Self.prefix) {
            style.removeLayer(layer)
        }
        for source in style.sources where source.identifier.hasPrefix(Self.prefix) {
            style.removeSource(source)
        }
        let groups = Dictionary(grouping: lines.filter { $0.coordinates.count >= 2 }) { $0.colorHex.lowercased() }
        for (index, entry) in groups.enumerated() {
            let (colorHex, group) = entry
            let id = "\(Self.prefix)-\(index)"
            let features = group.map { line -> MLNShape & MLNFeature in
                var coordinates = line.coordinates
                let feature = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
                feature.attributes = ["live": line.live ? 1 : 0, "delay": line.delayLevel, "label": line.label]
                return feature
            }
            let source = MLNShapeSource(
                identifier: id, shape: MLNShapeCollectionFeature(shapes: features), options: nil)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: id, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor(transitHex: colorHex) ?? .systemBlue)
            layer.lineWidth = NSExpression(forConstantValue: 5)
            layer.lineOpacity = NSExpression(forConstantValue: 0.85)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            // Under the map's labels, like the route layers.
            if let label = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
                style.insertLayer(layer, below: label)
            } else {
                style.addLayer(layer)
            }
        }
    }

    func clear(on style: MLNStyle?) {
        lines = []
        if let style { apply(to: style) }
    }
}

extension UIColor {
    /// `#rrggbb`, the only shape the feed's colors and the mode colors take.
    convenience init?(transitHex: String) {
        var hex = transitHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}
