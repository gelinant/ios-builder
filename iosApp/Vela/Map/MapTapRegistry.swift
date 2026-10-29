import CoreLocation
import Foundation
import MapLibre
import SwiftUI
import UIKit
import VelaCore

/// What a tapped element opens. The handler is the contract: a style layer identifier is never
/// drawn without one, and `MapTapRegistryTests` fails when the two sets differ.
enum MapTapHandler: Equatable {
    case place
    case camera
    case aircraft
    case ship
    case wiki
    case transitStop
    case savedPlace
    case savedShape
    case routeAlternate
    case routeSelected
    case resultPin
    case droppedPin
    case layerFeature
    case none

}

/// One style layer identifier, the handler it routes to, the finger box it accepts and the word
/// its card uses when the feature carries no name of its own.
struct MapTapStyleRule: Equatable {
    let identifier: String
    let handler: MapTapHandler
    let category: String
    let tolerance: CGFloat
}

struct MapTapDynamicRule: Equatable {
    let prefix: String
    let handler: MapTapHandler
    let category: String
    let tolerance: CGFloat
}

/// A tap is published as one typed value, whatever layer produced it. Values the layer did not
/// send stay empty or nil; nothing is filled from a neighbouring feature or a guess.
enum MapTapEvent: Equatable {
    case place(name: String, latitude: Double, longitude: Double, kind: String?, osmId: String?)
    case camera(kind: String, latitude: Double, longitude: Double, bearing: Double?)
    case aircraft(hex: String, callsign: String?, latitude: Double, longitude: Double)
    case ship(mmsi: String, latitude: Double, longitude: Double)
    case wiki(title: String, latitude: Double, longitude: Double)
    case transitStop(TransitStopMarker?)
    case savedPlace(index: Int)
    case savedShape(listId: String, index: Int, name: String, closed: Bool,
                     latitude: Double, longitude: Double)
    case route(index: Int?, latitude: Double, longitude: Double)
    case layerFeature(kind: String, name: String?, identifier: String,
                      latitude: Double, longitude: Double)
    case none

    var kind: String {
        switch self {
        case .place: return "place"
        case .camera: return "camera"
        case .aircraft: return "aircraft"
        case .ship: return "ship"
        case .wiki: return "wiki"
        case .transitStop: return "transitStop"
        case .savedPlace: return "savedPlace"
        case .savedShape: return "savedShape"
        case .route: return "route"
        case .layerFeature: return "layerFeature"
        case .none: return "none"
        }
    }
}

/// One rendered feature and the rule that will handle it. The layer index is MapLibre's z-order,
/// so a higher value is drawn above a lower one.
struct MapTapHit {
    let rule: MapTapStyleRule
    let feature: any MLNFeature
    let layerIndex: Int
}

/// Debug-only trace of the tap path. The values are appended to `layers-debug`, so a UI test can
/// tell a gesture that never fired from a query with no feature and from a routing failure.
enum MapTapDebug {
    static var gestures = 0
    static var point = "-"
    static var layers = 0
    static var features = 0
    static var layer = "-"
    static var identifier = "-"
    static var event = "-"
    static var note = "-"
    static var center = "-"
    static var ids = "-"
    static var detail = "-"
    static var unaudited: [String] = []

    static func gesture(at point: CGPoint) {
        gestures += 1
        self.point = String(format: "%.1f,%.1f", point.x, point.y)
        layers = 0
        features = 0
        layer = "-"
        identifier = "-"
        event = "-"
        note = "gesture"
    }

    static func query(queried: Int, features found: Int, hit: MapTapHit?,
                      center: String = "-", ids: String = "-") {
        layers = queried
        features = found
        self.center = center
        self.ids = ids
        guard let hit else {
            note = "no-hit"
            return
        }
        layer = hit.rule.identifier
        if let value = hit.feature.identifier as? String {
            identifier = value
        } else if let value = hit.feature.identifier as? NSNumber {
            identifier = value.stringValue
        } else {
            identifier = "-"
        }
        note = "hit"
    }

    static func event(_ event: MapTapEvent, note: String) {
        self.event = event.kind
        self.note = note
        switch event {
        case .place(let name, _, _, let kind, _):
            detail = "\(kind ?? "-"):\(name)"
        case .layerFeature(let kind, let name, _, _, _):
            detail = "\(kind):\(name ?? "-")"
        default:
            detail = "-"
        }
    }

    static var line: String {
        "tap=\(gestures) tap_at=\(point) tap_layers=\(layers) tap_features=\(features)"
            + " tap_center=\(center) tap_detail=\(detail) tap_ids=\(ids)"
            + " tap_layer=\(layer) tap_id=\(identifier) tap_event=\(event) tap_note=\(note)"
            + " tap_unaudited=\(unaudited.joined(separator: ","))"
    }
}

/// The one source of truth for map taps. Every identifier a layer class can add is registered
/// here with a handler; the drawn set is read from those same classes, so a future layer fails
/// the unit test until it is registered.
enum MapTapRegistry {
    static let defaultTolerance: CGFloat = 10
    static let denseTolerance: CGFloat = 22

    static let styleRules: [MapTapStyleRule] = makeRules()

    static let dynamicRules: [MapTapDynamicRule] = [
        MapTapDynamicRule(prefix: TransitLinesLayer.layerPrefix, handler: .transitStop,
                          category: "Transit line", tolerance: defaultTolerance),
        MapTapDynamicRule(prefix: SavedShapeLayer.layerPrefix, handler: .savedShape,
                          category: "Saved shape", tolerance: defaultTolerance),
    ]

    /// The style identifiers the app can draw. Read from the layer classes, never from a copy
    /// that can drift from the drawing code.
    static let drawnStyleIdentifiers: Set<String> = {
        var ids = Set<String>()
        ids.formUnion(MapLayers.layerIdentifiers)
        ids.formUnion(MapLayers.tilePoiLayerIdentifiers)
        ids.formUnion(MapRasterLayers.layerIdentifiers)
        ids.formUnion(MapStyleBuilder.layerIdentifiers)
        ids.formUnion(RouteLayers.layerIdentifiers)
        ids.formUnion(TransitReachOverlay.layerIdentifiers)
        ids.formUnion(AviationLayer.mapLayerIdentifiers)
        ids.formUnion(MaritimeLayer.mapLayerIdentifiers)
        ids.formUnion(WikiLayer.mapLayerIdentifiers)
        return ids
    }()

    static let drawnDynamicPrefixes: Set<String> = [
        TransitLinesLayer.layerPrefix, SavedShapeLayer.layerPrefix,
    ]

    static var registeredStyleIdentifiers: Set<String> {
        Set(styleRules.map(\.identifier))
    }

    static var registeredDynamicPrefixes: Set<String> {
        Set(dynamicRules.map(\.prefix))
    }

    /// Annotation channels are not style layers, but they are drawn, so they are named here too.
    static let annotationChannels: [String: MapTapHandler] = [
        "saved-pins": .savedPlace,
        "transit-pins": .transitStop,
        "result-pins": .resultPin,
        "dropped-pin": .droppedPin,
        "user-location": .none,
    ]

    static var drawnAnnotationChannels: Set<String> {
        Set(annotationChannels.keys)
    }

    static func rule(for identifier: String) -> MapTapStyleRule? {
        if let rule = styleRules.first(where: { $0.identifier == identifier }) {
            return rule
        }
        for rule in dynamicRules where identifier.hasPrefix(rule.prefix) {
            return MapTapStyleRule(
                identifier: identifier, handler: rule.handler,
                category: rule.category, tolerance: rule.tolerance)
        }
        return nil
    }

    /// The runtime safety net: an app-owned layer added after this lot is still tappable, and the
    /// fallback opens the minimal card instead of swallowing the tap.
    static func fallbackRule(for identifier: String) -> MapTapStyleRule? {
        guard identifier.hasPrefix("vela-") || identifier.hasPrefix("poi_") else { return nil }
        return MapTapStyleRule(
            identifier: identifier, handler: .layerFeature,
            category: "Map feature", tolerance: defaultTolerance)
    }

    /// Identifiers in the live style that the registry does not know. An empty result is the
    /// invariant the unit test checks against the declared drawn set.
    static func audit(identifiers: [String]) -> [String] {
        identifiers.filter { identifier in
            guard identifier.hasPrefix("vela-") || identifier.hasPrefix("poi_") else {
                return false
            }
            return rule(for: identifier) == nil
        }
    }

    static func audit(style: MLNStyle) {
        MapTapDebug.unaudited = audit(identifiers: style.layers.map(\.identifier))
    }

    /// The topmost rendered feature inside the rule's finger box. Each layer is queried with its
    /// own identifier because MapLibre's feature object carries no layer name; the layer index
    /// then restores the z-order across the queries.
    static func topHit(in mapView: MLNMapView, point: CGPoint) -> MapTapHit? {
        guard let style = mapView.style else {
            MapTapDebug.query(queried: 0, features: 0, hit: nil)
            return nil
        }
        let center = String(format: "%.5f,%.5f", mapView.centerCoordinate.latitude,
                            mapView.centerCoordinate.longitude)
        var best: MapTapHit?
        var queried = 0
        var found = 0
        var queriedIds: [String] = []
        for (index, layer) in style.layers.enumerated() {
            guard layer.isVisible else { continue }
            guard let rule = rule(for: layer.identifier)
                ?? fallbackRule(for: layer.identifier) else { continue }
            guard rule.handler != .none else { continue }
            let box = rule.tolerance
            let rect = CGRect(x: point.x - box, y: point.y - box,
                              width: box * 2, height: box * 2)
            queried += 1
            queriedIds.append(layer.identifier)
            // The point query first: a symbol anchor is exact, and some MapLibre builds return
            // no symbol for a rectangle that only crosses the label. The rectangle then adds
            // the 10/22 point finger tolerance for lines and for a tap beside an icon.
            let feature = mapView.visibleFeatures(
                at: point, styleLayerIdentifiers: [layer.identifier]).first
                ?? mapView.visibleFeatures(in: rect, styleLayerIdentifiers: [layer.identifier]).first
            guard let feature else { continue }
            found += 1
            if best == nil || index > best!.layerIndex {
                best = MapTapHit(rule: rule, feature: feature, layerIndex: index)
            }
        }
        MapTapDebug.query(queried: queried, features: found, hit: best,
                          center: center, ids: queriedIds.joined(separator: ","))
        return best
    }

    /// Turns the rendered feature into the typed event. A point feature keeps its own coordinate;
    /// a line, area or cone uses the finger's coordinate because its geometry centre would name a
    /// place the camera never drew.
    static func event(for hit: MapTapHit, in mapView: MLNMapView?, point: CGPoint) -> MapTapEvent {
        let feature = hit.feature
        let rule = hit.rule
        let coordinate = pointCoordinate(feature, in: mapView, point: point)
        let lat = coordinate.latitude
        let lng = coordinate.longitude
        switch rule.handler {
        case .place:
            let name = string(feature, ["name", "name:latin", "name:en", "title"]) ?? ""
            let kind = string(feature, ["subclass", "class", "group", "kind"])
            let osmId = string(feature, ["osm_id", "osmId"])
            return .place(name: name, latitude: lat, longitude: lng, kind: kind, osmId: osmId)
        case .camera:
            return .camera(kind: rule.category, latitude: lat, longitude: lng,
                           bearing: number(feature, ["bearing", "direction"]))
        case .aircraft:
            return .aircraft(hex: string(feature, ["hex"]) ?? "",
                             callsign: string(feature, ["callsign", "flight", "name"]),
                             latitude: lat, longitude: lng)
        case .ship:
            return .ship(mmsi: string(feature, ["mmsi"]) ?? "", latitude: lat, longitude: lng)
        case .wiki:
            return .wiki(title: string(feature, ["title", "name"]) ?? "",
                         latitude: lat, longitude: lng)
        case .transitStop:
            let title = string(feature, ["label", "name", "title"]) ?? ""
            let marker = TransitStopMarker(
                id: "tap:\(lat),\(lng):\(title)",
                name: title, latitude: lat, longitude: lng,
                modes: [], parentId: nil, siblingIds: [])
            return .transitStop(marker)
        case .savedPlace:
            return .none
        case .savedShape:
            let listId = string(feature, ["listId"]) ?? ""
            let index = int(feature, ["index"]) ?? -1
            return .savedShape(listId: listId, index: index,
                               name: string(feature, ["name"]) ?? "",
                               closed: bool(feature, ["closed"]) ?? false,
                               latitude: lat, longitude: lng)
        case .routeAlternate, .routeSelected:
            return .route(index: int(feature, ["index"]), latitude: lat, longitude: lng)
        case .layerFeature:
            return .layerFeature(
                kind: rule.category,
                name: string(feature, ["name", "title", "text"]),
                identifier: rule.identifier, latitude: lat, longitude: lng)
        case .resultPin, .droppedPin, .none:
            return .none
        }
    }

    // MARK: - Rules

    private static func makeRules() -> [MapTapStyleRule] {
        var rules: [MapTapStyleRule] = []
        func add(_ identifier: String, _ handler: MapTapHandler, _ category: String,
                 _ tolerance: CGFloat = defaultTolerance) {
            rules.append(MapTapStyleRule(
                identifier: identifier, handler: handler,
                category: category, tolerance: tolerance))
        }

        let painted = MapLayers.layerIdentifiers.filter { $0.hasPrefix("vela-paint-") }
        for identifier in painted { add(identifier, .layerFeature, "Painted road") }
        add("vela-speed", .camera, "Speed camera", denseTolerance)
        add("vela-alpr", .camera, "Plate camera", denseTolerance)
        add(MapLayers.alprConeLayerId, .camera, "Plate camera", defaultTolerance)
        for identifier in ["vela-controls-signal", "vela-controls-stop",
                           "vela-controls-rail_crossing", "vela-controls-speed_hump"] {
            add(identifier, .layerFeature, "Traffic control")
        }
        add("vela-fuel", .layerFeature, "Fuel price")
        add("vela-fuel-label", .layerFeature, "Fuel price")
        add("vela-bridge-open", .layerFeature, "Bridge")
        add("vela-bridge-planned", .layerFeature, "Bridge")
        add(MapLayers.velaPoiLayerId, .place, "Place", denseTolerance)
        for identifier in MapLayers.tilePoiLayerIdentifiers {
            add(identifier, .place, "Place", denseTolerance)
        }

        for identifier in MapRasterLayers.layerIdentifiers {
            add(identifier, .none, "Base map")
        }
        for identifier in MapStyleBuilder.layerIdentifiers {
            add(identifier, .none, "Base label")
        }

        for identifier in RouteLayers.layerIdentifiers {
            let handler: MapTapHandler
            if RouteLayers.navigationSymbolIdentifiers.contains(identifier) {
                // Road-ahead arrows and lane glyphs decorate the route; a tap belongs to the
                // line under them, so it keeps the existing route-selection behavior.
                handler = .none
            } else if identifier == RouteLayers.altLayer || identifier == "vela-route-alt-edge" {
                handler = .routeAlternate
            } else {
                handler = .routeSelected
            }
            add(identifier, handler, "Route")
        }

        for identifier in TransitReachOverlay.layerIdentifiers {
            add(identifier, .transitStop, "Transit reach", denseTolerance)
        }

        for identifier in AviationLayer.mapLayerIdentifiers {
            add(identifier, .aircraft, "Aircraft", denseTolerance)
        }
        for identifier in MaritimeLayer.mapLayerIdentifiers {
            add(identifier, .ship, "Ship", denseTolerance)
        }
        for identifier in WikiLayer.mapLayerIdentifiers {
            add(identifier, .wiki, "Wikivoyage", denseTolerance)
        }
        return rules
    }

    // MARK: - Attribute readers

    private static func string(_ feature: any MLNFeature, _ keys: [String]) -> String? {
        for key in keys {
            if let value = feature.attribute(forKey: key) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func number(_ feature: any MLNFeature, _ keys: [String]) -> Double? {
        for key in keys {
            if let value = feature.attribute(forKey: key) as? NSNumber {
                return value.doubleValue
            }
        }
        return nil
    }

    private static func int(_ feature: any MLNFeature, _ keys: [String]) -> Int? {
        for key in keys {
            if let value = feature.attribute(forKey: key) as? NSNumber {
                return value.intValue
            }
        }
        return nil
    }

    private static func bool(_ feature: any MLNFeature, _ keys: [String]) -> Bool? {
        for key in keys {
            if let value = feature.attribute(forKey: key) as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    private static func pointCoordinate(
        _ feature: any MLNFeature, in mapView: MLNMapView?, point: CGPoint
    ) -> CLLocationCoordinate2D {
        if let pointFeature = feature as? MLNPointFeature {
            return pointFeature.coordinate
        }
        guard let mapView else { return CLLocationCoordinate2D() }
        return mapView.convert(point, toCoordinateFrom: mapView)
    }
}

/// The minimal card every kind falls back to. It names the kind, the coordinates and, in one
/// line, what the layer did not send. It is presented from the map controller, not from a sheet
/// that lives in `MapScreen`, so a missing identifier never turns a tap into silence.
enum MapTapCards {
    private static var current: MapTapCardHost?

    static func present(title: String, kind: String, lines: [String]) {
        DispatchQueue.main.async {
            guard current == nil, let top = topController() else { return }
            let host = MapTapCardHost(
                rootView: MapTapCardView(title: title, kind: kind, lines: lines))
            host.modalPresentationStyle = .overFullScreen
            host.view.backgroundColor = .clear
            host.onDisappear = { current = nil }
            current = host
            top.present(host, animated: false)
        }
    }

    static func present(feature kind: String, name: String?, latitude: Double, longitude: Double,
                        missing: String) {
        let title = name?.isEmpty == false ? name! : kind
        present(title: title, kind: kind, lines: [
            "Coordinates: \(coordinate(latitude, longitude))",
            missing,
        ])
    }

    static func present(camera kind: String, pin: LayerPin?, latitude: Double, longitude: Double) {
        var lines = ["Coordinates: \(coordinate(latitude, longitude))"]
        if let text = pin?.text, !text.isEmpty {
            lines.append("Source text: \(text)")
        }
        if let bearing = pin?.bearing {
            lines.append("Direction: \(Int(bearing.rounded())) deg")
        }
        if pin == nil {
            lines.append("The source sent no speed limit or direction for this point.")
        } else if pin?.text.isEmpty == true {
            lines.append("The source sent no speed limit for this camera.")
        }
        present(title: kind, kind: kind, lines: lines)
    }

    static func present(ship mmsi: String, row: WorldLayerRow?,
                        latitude: Double, longitude: Double) {
        let title = row?.title ?? (mmsi.isEmpty ? "Ship" : "Ship \(mmsi)")
        var lines: [String] = []
        if let detail = row?.detail, !detail.isEmpty { lines.append(detail) }
        if !mmsi.isEmpty { lines.append("MMSI: \(mmsi)") } else { lines.append("No MMSI was sent.") }
        lines.append("Coordinates: \(coordinate(latitude, longitude))")
        lines.append("The card shows only the AIS fields the feed sent.")
        present(title: title, kind: "Ship", lines: lines)
    }

    static func present(savedShape: SavedMapShape?, listId: String, index: Int,
                        name: String, closed: Bool, latitude: Double, longitude: Double) {
        let title = name.isEmpty ? (closed ? "Saved area" : "Saved line") : name
        var lines: [String] = []
        if let shape = savedShape {
            lines.append("List: \(shape.listName)")
            lines.append("Points: \(Int(shape.points.size) / 2)")
        } else {
            lines.append("List: \(listId), shape \(index)")
            lines.append("The saved store no longer holds this shape.")
        }
        lines.append("Coordinates: \(coordinate(latitude, longitude))")
        lines.append("Editing a list shape lives in the Saved sheet.")
        present(title: title, kind: closed ? "Saved area" : "Saved line", lines: lines)
    }

    private static func coordinate(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private final class MapTapCardHost: UIHostingController<MapTapCardView> {
    var onDisappear: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear?()
    }
}

private struct MapTapCardView: View {
    let title: String
    let kind: String
    let lines: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .accessibilityIdentifier("map-tap-card-title")
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("map-tap-card-close")
                }
                Text(kind)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("map-tap-card-kind")
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(maxWidth: 340, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 12)
            .padding(24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map-tap-card")
    }
}
