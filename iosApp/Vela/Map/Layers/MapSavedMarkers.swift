import CoreLocation
import MapLibre
import UIKit
import VelaCore

/// The saved places and parking spot as map annotations. Android draws a coloured disc with the
/// place's or the list's icon; this layer keeps the same zoom rule and tap box, and every value it
/// paints comes from the shared saved store, never from a second copy.
///
/// MAP-TAP reuses `nearestPin` for the hit test, so the drawn disc and the touch box stay the same
/// size at every zoom even though MapLibre's annotation view does not scale on its own.
final class SavedMarkerLayer {
    private(set) var annotations: [MLNPointAnnotation] = []
    private var pins: [SavedMapPin] = []

    func show(_ pins: [SavedMapPin], on mapView: MLNMapView) {
        if !annotations.isEmpty {
            mapView.removeAnnotations(annotations)
        }
        self.pins = pins
        annotations = pins.map { pin in
            let annotation = MLNPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(latitude: pin.lat, longitude: pin.lng)
            annotation.title = pin.name.isEmpty ? nil : pin.name
            return annotation
        }
        if !annotations.isEmpty {
            mapView.addAnnotations(annotations)
        }
    }

    /// Resizes the discs and shows or hides their names, as Android does at 3, 8 and 14.
    func applyZoom(_ zoom: Double, on mapView: MLNMapView) {
        for annotation in annotations {
            guard let view = mapView.view(for: annotation) as? SavedPinView else { continue }
            if let index = index(of: annotation) {
                view.configure(pins[index], zoom: zoom)
            }
        }
    }

    func view(for annotation: MLNAnnotation, zoom: Double) -> MLNAnnotationView? {
        guard let index = index(of: annotation) else { return nil }
        let view = SavedPinView(annotation: annotation, reuseIdentifier: nil)
        view.configure(pins[index], zoom: zoom)
        return view
    }

    private func index(of annotation: MLNAnnotation) -> Int? {
        annotations.firstIndex { $0 === annotation }
    }
}

/// A disc with the place's colour and icon, and its name under it once the camera is close enough.
private final class SavedPinView: MLNAnnotationView {
    private let disc = UIImageView()
    private let label = UILabel()

    override init(annotation: MLNAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        disc.contentMode = .center
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textAlignment = .center
        label.textColor = .label
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.78)
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        addSubview(disc)
        addSubview(label)
        isAccessibilityElement = true
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func configure(_ pin: SavedMapPin, zoom: Double) {
        let diameter = CGFloat(SavedMap.shared.pinDiameter(zoom: zoom))
        disc.image = SavedPinArt.image(pin: pin, diameter: diameter)
        let showLabel = SavedMap.shared.showsNames(zoom: zoom) && !pin.name.isEmpty
        label.text = pin.name
        label.isHidden = !showLabel
        let labelHeight: CGFloat = showLabel ? 17 : 0
        let labelWidth = showLabel
            ? min(190, label.sizeThatFits(CGSize(width: 190, height: labelHeight)).width + 8)
            : 0
        let width = max(diameter, labelWidth)
        frame = CGRect(x: 0, y: 0, width: width, height: diameter + labelHeight)
        disc.frame = CGRect(x: (width - diameter) / 2, y: 0, width: diameter, height: diameter)
        label.frame = CGRect(x: 0, y: diameter, width: width, height: labelHeight)
        centerOffset = CGVector(dx: 0, dy: labelHeight / 2)
        accessibilityLabel = pin.name.isEmpty ? "Saved place" : pin.name
        accessibilityIdentifier = "saved-pin"
    }
}

/// The disc bitmap: the exact stored colour, a white ring, then the icon. No icon is guessed when
/// the stored key has no SF Symbol; the disc keeps a plain white dot instead.
private enum SavedPinArt {
    static func image(pin: SavedMapPin, diameter: CGFloat) -> UIImage {
        let side = max(diameter, 8)
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let path = UIBezierPath(ovalIn: rect)
            context.cgContext.setFillColor(UIColor(argb: UInt32(bitPattern: pin.color)).cgColor)
            context.cgContext.addPath(path.cgPath)
            context.cgContext.fillPath()
            context.cgContext.setStrokeColor(UIColor.white.cgColor)
            context.cgContext.setLineWidth(max(1, side * 0.07))
            context.cgContext.addPath(path.cgPath)
            context.cgContext.strokePath()
            drawIcon(pin.icon, in: rect, context: context)
        }
    }

    private static func drawIcon(_ key: String, in rect: CGRect, context: UIGraphicsImageRendererContext) {
        if key.hasPrefix("emoji:") {
            let text = String(key.dropFirst("emoji:".count))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: rect.width * 0.52),
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(
                at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attributes)
            return
        }
        let symbol = key.isEmpty ? "bookmark.fill" : key
        let configuration = UIImage.SymbolConfiguration(pointSize: max(7, rect.width * 0.52), weight: .semibold)
        guard let glyph = UIImage(systemName: symbol, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else {
            context.cgContext.setFillColor(UIColor.white.cgColor)
            context.cgContext.fillEllipse(in: rect.insetBy(dx: rect.width * 0.34, dy: rect.width * 0.34))
            return
        }
        glyph.draw(at: CGPoint(x: rect.midX - glyph.size.width / 2,
                               y: rect.midY - glyph.size.height / 2))
    }
}

/// The saved lists' lines and areas. One layer family per shape keeps every stored colour and
/// width exact; the names draw from z12 through a point feature, so an area's name sits at its
/// first point instead of being repeated along every outline.
final class SavedShapeLayer {
    /// Prefix shared by the line, fill and label layers and by their sources. MAP-TAP registers
    /// the prefix, so every shape layer is tappable without a list of generated identifiers.
    static let layerSourcePrefix = "vela-saved-shape"
    static let layerPrefix = layerSourcePrefix

    private var shapes: [SavedMapShape] = []

    func show(_ shapes: [SavedMapShape], on style: MLNStyle?) {
        self.shapes = shapes
        guard let style else { return }
        remove(style)
        guard !shapes.isEmpty else { return }
        let anchor = MapLayers.labelAnchor(in: style)
        for (index, shape) in shapes.enumerated() {
            let coordinates = Self.coordinates(shape)
            guard coordinates.count >= 2 else { continue }
            let base = "\(Self.layerSourcePrefix)-\(index)"
            let source = MLNShapeSource(identifier: "\(base)-src", shape: nil, options: nil)
            style.addSource(source)
            let attributes: [String: Any] = [
                "listId": shape.listId,
                "index": NSNumber(value: shape.index),
                "name": shape.name,
                "closed": NSNumber(value: shape.closed),
            ]
            var polyline = coordinates
            let line = MLNPolylineFeature(coordinates: &polyline, count: UInt(polyline.count))
            line.attributes = attributes
            var features: [MLNShape & MLNFeature] = [line]
            if shape.closed, coordinates.count >= 3 {
                var polygon = coordinates
                let fill = MLNPolygonFeature(coordinates: &polygon, count: UInt(polygon.count))
                fill.attributes = attributes
                features.append(fill)
            }
            let labelPoint = MLNPointFeature()
            labelPoint.coordinate = coordinates[0]
            labelPoint.attributes = attributes.merging(["labelOnly": NSNumber(value: true)]) { _, new in new }
            features.append(labelPoint)
            source.shape = MLNShapeCollectionFeature(shapes: features)

            if shape.closed, let fillColor = shape.fillColor {
                let fill = MLNFillStyleLayer(identifier: "\(base)-fill", source: source)
                fill.fillColor = NSExpression(
                    forConstantValue: UIColor(argb: UInt32(bitPattern: fillColor.int32Value)))
                fill.fillOpacity = NSExpression(forConstantValue: NSNumber(value: shape.fillOpacity))
                fill.predicate = NSPredicate(format: "closed == YES")
                insert(fill, below: anchor, in: style)
            }
            let outline = MLNLineStyleLayer(identifier: "\(base)-line", source: source)
            outline.lineColor = NSExpression(
                forConstantValue: UIColor(argb: UInt32(bitPattern: shape.lineColor)))
            outline.lineOpacity = NSExpression(
                forConstantValue: NSNumber(value: shape.lineOpacity))
            outline.lineWidth = NSExpression(
                forConstantValue: NSNumber(value: max(1, shape.width)))
            outline.lineCap = NSExpression(forConstantValue: "round")
            outline.lineJoin = NSExpression(forConstantValue: "round")
            insert(outline, below: anchor, in: style)

            let label = MLNSymbolStyleLayer(identifier: "\(base)-label", source: source)
            label.predicate = NSPredicate(format: "labelOnly == YES")
            label.text = NSExpression(forKeyPath: "name")
            label.textFontNames = NSExpression(forConstantValue: ["Noto Sans Regular"])
            label.textFontSize = NSExpression(forConstantValue: 11)
            label.textColor = NSExpression(forConstantValue: UIColor.label)
            label.textHaloColor = NSExpression(forConstantValue: UIColor.systemBackground)
            label.textHaloWidth = NSExpression(forConstantValue: 1.4)
            label.minimumZoomLevel = Float(SavedMap.shared.shapeLabelZoom())
            insert(label, below: anchor, in: style)
        }
    }

    private func remove(_ style: MLNStyle) {
        for layer in style.layers where layer.identifier.hasPrefix(Self.layerSourcePrefix) {
            style.removeLayer(layer)
        }
        for source in style.sources where source.identifier.hasPrefix(Self.layerSourcePrefix) {
            style.removeSource(source)
        }
    }

    private func insert(_ layer: MLNStyleLayer, below anchor: MLNStyleLayer?, in style: MLNStyle) {
        if let anchor {
            style.insertLayer(layer, below: anchor)
        } else {
            style.addLayer(layer)
        }
    }

    private static func coordinates(_ shape: SavedMapShape) -> [CLLocationCoordinate2D] {
        let count = Int(shape.points.size) / 2
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            out.append(CLLocationCoordinate2D(
                latitude: shape.points.get(index: Int32(index * 2)),
                longitude: shape.points.get(index: Int32(index * 2 + 1))))
        }
        return out
    }
}

private extension UIColor {
    convenience init(argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255)
    }
}
