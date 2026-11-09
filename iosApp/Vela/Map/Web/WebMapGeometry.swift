import CoreLocation
import Foundation
import UIKit

// The shapes, features and annotation types of the map. The main map renders with MapLibre GL JS
// (WebMapView.swift); these classes keep the names and the subset of the MapLibre Native API the
// app was written against, and convert to and from GeoJSON for the page.

struct MLNCoordinateBounds {
    var sw: CLLocationCoordinate2D
    var ne: CLLocationCoordinate2D

    init(sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D) {
        self.sw = sw
        self.ne = ne
    }
}

/// Anything drawn at a coordinate: a pin, a shape, the user location.
protocol MLNAnnotation: AnyObject {
    var coordinate: CLLocationCoordinate2D { get }
    var title: String? { get }
    var subtitle: String? { get }
}

/// A rendered or source feature: a shape that carries attributes and an identifier.
protocol MLNFeature: MLNAnnotation {
    var identifier: Any? { get set }
    var attributes: [String: Any] { get set }
}

extension MLNFeature {
    func attribute(forKey key: String) -> Any? {
        attributes[key]
    }

    func geoJSONDictionary() -> [String: Any] {
        (self as? MLNShape)?.geoJSONFeature() ?? [:]
    }
}

class MLNShape: NSObject, MLNAnnotation {
    var title: String?
    var subtitle: String?
    /// The map that draws this shape as an annotation, told when a point annotation moves.
    weak var webMapOwner: MLNMapView?

    var coordinate: CLLocationCoordinate2D { kCLLocationCoordinate2DInvalid }

    /// The GeoJSON geometry, or nil for a shape that has none.
    func geoJSONGeometry() -> [String: Any]? { nil }

    /// A GeoJSON Feature with this shape's geometry and, for a feature, its attributes and id.
    func geoJSONFeature() -> [String: Any] {
        var feature: [String: Any] = [
            "type": "Feature",
            "geometry": geoJSONGeometry() ?? NSNull(),
            "properties": [String: Any](),
        ]
        if let shapeFeature = self as? MLNFeature {
            feature["properties"] = GeoJSON.sanitize(shapeFeature.attributes)
            if let id = shapeFeature.identifier {
                if let number = id as? NSNumber {
                    feature["id"] = number
                } else if let text = id as? String {
                    feature["id"] = text
                }
            }
        }
        return feature
    }
}

class MLNPointAnnotation: MLNShape {
    private var storedCoordinate = kCLLocationCoordinate2DInvalid

    override init() {
        super.init()
    }

    override var coordinate: CLLocationCoordinate2D {
        get { storedCoordinate }
        set {
            storedCoordinate = newValue
            webMapOwner?.annotationDidMove(self)
        }
    }

    override func geoJSONGeometry() -> [String: Any]? {
        guard CLLocationCoordinate2DIsValid(storedCoordinate) else { return nil }
        return ["type": "Point", "coordinates": GeoJSON.position(storedCoordinate)]
    }
}

final class MLNPointFeature: MLNPointAnnotation, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

class MLNMultiPoint: MLNShape {
    private(set) var coordinates: [CLLocationCoordinate2D]

    required init(coordinates: UnsafePointer<CLLocationCoordinate2D>, count: UInt) {
        self.coordinates = Array(UnsafeBufferPointer(start: coordinates, count: Int(count)))
        super.init()
    }

    init(coordinateArray: [CLLocationCoordinate2D]) {
        coordinates = coordinateArray
        super.init()
    }

    var pointCount: UInt { UInt(coordinates.count) }

    func setCoordinates(_ coordinates: UnsafeMutablePointer<CLLocationCoordinate2D>, count: UInt) {
        self.coordinates = Array(UnsafeBufferPointer(start: coordinates, count: Int(count)))
        webMapOwner?.annotationDidMove(self)
    }

    override var coordinate: CLLocationCoordinate2D {
        guard !coordinates.isEmpty else { return kCLLocationCoordinate2DInvalid }
        return coordinates[coordinates.count / 2]
    }

    var overlayBounds: MLNCoordinateBounds {
        GeoJSON.bounds(of: coordinates)
    }
}

class MLNPointCollection: MLNMultiPoint {
    override func geoJSONGeometry() -> [String: Any]? {
        ["type": "MultiPoint", "coordinates": coordinates.map(GeoJSON.position)]
    }
}

final class MLNPointCollectionFeature: MLNPointCollection, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

class MLNPolyline: MLNMultiPoint {
    override func geoJSONGeometry() -> [String: Any]? {
        guard coordinates.count >= 2 else { return nil }
        return ["type": "LineString", "coordinates": coordinates.map(GeoJSON.position)]
    }
}

final class MLNPolylineFeature: MLNPolyline, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

class MLNPolygon: MLNMultiPoint {
    private(set) var interiorPolygons: [MLNPolygon]?

    required init(coordinates: UnsafePointer<CLLocationCoordinate2D>, count: UInt) {
        super.init(coordinates: coordinates, count: count)
    }

    convenience init(coordinates: UnsafePointer<CLLocationCoordinate2D>, count: UInt,
                     interiorPolygons: [MLNPolygon]?) {
        self.init(coordinates: coordinates, count: count)
        self.interiorPolygons = interiorPolygons
    }

    init(rings: [[CLLocationCoordinate2D]]) {
        super.init(coordinateArray: rings.first ?? [])
        let holes = rings.dropFirst().map { MLNPolygon(rings: [$0]) }
        interiorPolygons = holes.isEmpty ? nil : Array(holes)
    }

    func rings() -> [[CLLocationCoordinate2D]] {
        [coordinates] + (interiorPolygons ?? []).map(\.coordinates)
    }

    override func geoJSONGeometry() -> [String: Any]? {
        guard coordinates.count >= 3 else { return nil }
        return ["type": "Polygon", "coordinates": rings().map(GeoJSON.ring)]
    }
}

final class MLNPolygonFeature: MLNPolygon, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

class MLNMultiPolyline: MLNShape {
    let polylines: [MLNPolyline]

    init(polylines: [MLNPolyline]) {
        self.polylines = polylines
        super.init()
    }

    override var coordinate: CLLocationCoordinate2D {
        polylines.first?.coordinate ?? kCLLocationCoordinate2DInvalid
    }

    override func geoJSONGeometry() -> [String: Any]? {
        ["type": "MultiLineString",
         "coordinates": polylines.map { $0.coordinates.map(GeoJSON.position) }]
    }
}

final class MLNMultiPolylineFeature: MLNMultiPolyline, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

class MLNMultiPolygon: MLNShape {
    let polygons: [MLNPolygon]

    init(polygons: [MLNPolygon]) {
        self.polygons = polygons
        super.init()
    }

    override var coordinate: CLLocationCoordinate2D {
        polygons.first?.coordinate ?? kCLLocationCoordinate2DInvalid
    }

    override func geoJSONGeometry() -> [String: Any]? {
        ["type": "MultiPolygon", "coordinates": polygons.map { $0.rings().map(GeoJSON.ring) }]
    }
}

final class MLNMultiPolygonFeature: MLNMultiPolygon, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

class MLNShapeCollection: MLNShape {
    let shapes: [MLNShape]

    init(shapes: [MLNShape]) {
        self.shapes = shapes
        super.init()
    }

    override var coordinate: CLLocationCoordinate2D {
        shapes.first?.coordinate ?? kCLLocationCoordinate2DInvalid
    }

    override func geoJSONGeometry() -> [String: Any]? {
        ["type": "GeometryCollection", "geometries": shapes.compactMap { $0.geoJSONGeometry() }]
    }
}

final class MLNShapeCollectionFeature: MLNShapeCollection, MLNFeature {
    var identifier: Any?
    var attributes: [String: Any] = [:]
}

/// The location the map shows with its puck.
final class MLNUserLocation: NSObject, MLNAnnotation {
    var location: CLLocation?
    var heading: CLHeading?
    var title: String? = "You Are Here"
    var subtitle: String?
    var isUpdating = false

    var coordinate: CLLocationCoordinate2D {
        location?.coordinate ?? kCLLocationCoordinate2DInvalid
    }
}

/// A view drawn for a point annotation. The page draws a bitmap of it, refreshed whenever the
/// view's frame, offset or content is invalidated.
class MLNAnnotationView: UIView {
    var annotation: MLNAnnotation?
    let reuseIdentifier: String?
    var isSelected = false
    var isDraggable = false
    var scalesWithViewingDistance = false
    var rotatesToMatchCamera = false
    weak var webMapOwner: MLNMapView?

    var centerOffset: CGVector = .zero {
        didSet { invalidateWebMarker() }
    }

    init(annotation: MLNAnnotation?, reuseIdentifier: String?) {
        self.annotation = annotation
        self.reuseIdentifier = reuseIdentifier
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        reuseIdentifier = nil
        super.init(coder: coder)
    }

    override var frame: CGRect {
        didSet { invalidateWebMarker() }
    }

    override func setNeedsDisplay() {
        super.setNeedsDisplay()
        invalidateWebMarker()
    }

    func invalidateWebMarker() {
        webMapOwner?.annotationViewDidChange(self)
    }
}

/// GeoJSON helpers shared by the sources, the annotations and the rendered features.
enum GeoJSON {
    static func position(_ coordinate: CLLocationCoordinate2D) -> [Double] {
        [finite(coordinate.longitude), finite(coordinate.latitude)]
    }

    /// A closed ring, as GeoJSON requires; MapLibre Native accepted open rings.
    static func ring(_ coordinates: [CLLocationCoordinate2D]) -> [[Double]] {
        var positions = coordinates.map(position)
        if let first = positions.first, let last = positions.last, first != last {
            positions.append(first)
        }
        return positions
    }

    static func finite(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    static func bounds(of coordinates: [CLLocationCoordinate2D]) -> MLNCoordinateBounds {
        guard let first = coordinates.first else {
            return MLNCoordinateBounds(sw: kCLLocationCoordinate2DInvalid, ne: kCLLocationCoordinate2DInvalid)
        }
        var sw = first
        var ne = first
        for c in coordinates {
            sw.latitude = min(sw.latitude, c.latitude)
            sw.longitude = min(sw.longitude, c.longitude)
            ne.latitude = max(ne.latitude, c.latitude)
            ne.longitude = max(ne.longitude, c.longitude)
        }
        return MLNCoordinateBounds(sw: sw, ne: ne)
    }

    /// A source's whole data: always a FeatureCollection, so the page has one shape to expect.
    static func featureCollection(_ shape: MLNShape?) -> [String: Any] {
        let features = shape.map(flatten) ?? []
        return ["type": "FeatureCollection", "features": features]
    }

    private static func flatten(_ shape: MLNShape) -> [[String: Any]] {
        if let nested = shape as? MLNShapeCollection {
            return nested.shapes.flatMap(flatten)
        }
        guard shape.geoJSONGeometry() != nil else { return [] }
        return [shape.geoJSONFeature()]
    }

    /// JSON-safe attribute values. A value JSONSerialization cannot write becomes its description.
    static func sanitize(_ attributes: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in attributes {
            if let clean = sanitizeValue(value) { out[key] = clean }
        }
        return out
    }

    static func sanitizeValue(_ value: Any) -> Any? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number }
            let double = number.doubleValue
            return double.isFinite ? number : nil
        case let text as String:
            return text
        case let array as [Any]:
            return array.compactMap(sanitizeValue)
        case let dictionary as [String: Any]:
            return sanitize(dictionary)
        case is NSNull:
            return NSNull()
        case let color as UIColor:
            return WebMapJSON.color(color)
        default:
            return String(describing: value)
        }
    }

    // MARK: - From the page

    /// A rendered feature from the page's query: `{l, id, p, g}`.
    static func feature(from json: [String: Any]) -> MLNFeature? {
        guard let geometry = json["g"] as? [String: Any] else { return nil }
        let attributes = json["p"] as? [String: Any] ?? [:]
        let identifier: Any? = json["id"].flatMap { $0 is NSNull ? nil : $0 }
        guard var shape = makeFeature(geometry) else { return nil }
        shape.attributes = attributes
        shape.identifier = identifier
        return shape
    }

    private static func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
        guard let pair = value as? [Any], pair.count >= 2,
              let lng = (pair[0] as? NSNumber)?.doubleValue,
              let lat = (pair[1] as? NSNumber)?.doubleValue else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private static func line(_ value: Any?) -> [CLLocationCoordinate2D] {
        (value as? [Any] ?? []).compactMap(coordinate)
    }

    private static func makeFeature(_ geometry: [String: Any]) -> MLNFeature? {
        let type = geometry["type"] as? String ?? ""
        let coordinates = geometry["coordinates"]
        switch type {
        case "Point":
            guard let c = coordinate(coordinates) else { return nil }
            let point = MLNPointFeature()
            point.coordinate = c
            return point
        case "MultiPoint":
            return MLNPointCollectionFeature(coordinateArray: line(coordinates))
        case "LineString":
            return MLNPolylineFeature(coordinateArray: line(coordinates))
        case "MultiLineString":
            let lines = (coordinates as? [Any] ?? []).map { MLNPolyline(coordinateArray: line($0)) }
            return MLNMultiPolylineFeature(polylines: lines)
        case "Polygon":
            let rings = (coordinates as? [Any] ?? []).map(line)
            return MLNPolygonFeature(rings: rings)
        case "MultiPolygon":
            let polygons = (coordinates as? [Any] ?? []).map { polygon in
                MLNPolygon(rings: (polygon as? [Any] ?? []).map(line))
            }
            return MLNMultiPolygonFeature(polygons: polygons)
        default:
            return nil
        }
    }
}
