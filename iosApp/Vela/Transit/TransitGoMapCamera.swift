import CoreLocation
import SwiftUI
import UIKit
import VelaCore

/// GO's map: the current step's frame, the line near the user and its estimated vehicles, and
/// the camera rule. The rule itself lives in `TransitGoMap` (Kotlin, JVM tested): fit the user,
/// the step's target and the leg between them; refit on a new step or when the user or the
/// target leaves the safe area; after a pan or a pinch, wait until the user has left the map
/// alone for `resumeDelay` seconds, or until Recenter.
final class TransitGoMapModel: NSObject, ObservableObject, MLNMapViewDelegate {
    /// True while the camera waits for the user, after a pan or a pinch. Recenter shows then.
    @Published private(set) var paused = false
    @Published private(set) var debugLine = "go_map=0"
    /// The estimated dots drawn on GO's map; the map says "Estimated" whenever it is not zero.
    @Published private(set) var vehicleCount = 0

    let trip: TransitItinerary?
    /// The map exists only for an itinerary with coordinates; a plan without them keeps the
    /// full-height card.
    let hasMap: Bool
    static let resumeDelay: TimeInterval = 8
    /// Room around the framed box, in points, so the pin and the puck are not on the edge.
    static let padding = UIEdgeInsets(top: 44, left: 36, bottom: 36, right: 36)

    weak var mapView: MLNMapView?
    private let feed: TransitGoVehicleFeed
    private let lines = TransitLinesLayer()
    private let vehicleLayer = TransitVehicleLayer()
    private var frame: TransitGoMapFrame?
    private var line: TransitGoMapLine?
    private var state: TransitGoState?
    private var user: LatLng?
    private var stepKey = ""
    private var lineKey = ""
    private var resume: DispatchWorkItem?
    private var legShape: MLNPolyline?
    private var targetPin: MLNPointAnnotation?
    private var refits = 0
    private var styleReady = false

    init(trip: TransitItinerary?, budget: TransitRequestBudget?,
         fixture: ((Int64) -> [TransitVehicle])? = nil) {
        self.trip = trip
        hasMap = Self.hasCoordinates(trip)
        feed = TransitGoVehicleFeed(budget: budget, fixture: fixture)
        super.init()
        feed.onChange = { [weak self] in self?.vehiclesChanged() }
    }

    /// True when the itinerary carries at least one coordinate GO can frame.
    static func hasCoordinates(_ trip: TransitItinerary?) -> Bool {
        guard let trip else { return false }
        return TransitGoMap.shared.frame(trip: trip, legIndex: 0, phase: "WALK", user: nil).box != nil
    }

    /// The vehicle the rail follows: the line's estimated vehicle nearest the user, or nearest the
    /// ride's current stop without a fix. It is an estimate, like every point it comes from.
    var vehicleHint: TransitGoVehicleHint? {
        guard let line, let state, state.phase == "RIDE" else { return nil }
        let vehicle = TransitGoMap.shared.hintVehicle(
            vehicles: feed.vehicles, user: user, fallback: line.boardStop)
        return vehicle.map {
            TransitGoVehicleHint(line: $0.label, fraction: $0.fraction,
                                 fromStop: $0.fromStopName, toStop: $0.nextStopName)
        }
    }

    // MARK: Inputs

    /// Called with every machine snapshot. Only a new leg or phase refits; a new stop on the same
    /// ride keeps the camera unless a point left the safe area.
    func update(state: TransitGoState?) {
        self.state = state
        guard let trip, let state else { return }
        let key = "\(state.legIndex)|\(state.phase)"
        let stepChanged = key != stepKey
        stepKey = key
        recompute(trip: trip, state: state)
        if stepChanged {
            fit(animated: refits > 0)
        } else {
            refitIfNeeded()
        }
    }

    func updateUser(_ location: CLLocation?) {
        guard let location, CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        user = LatLng(lat: location.coordinate.latitude, lng: location.coordinate.longitude)
        guard let trip, let state else { return }
        recompute(trip: trip, state: state)
        refitIfNeeded()
    }

    /// A pan or a pinch on the map: the camera stops following until the map has been left alone.
    func userMovedMap() {
        paused = true
        resume?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recenter() }
        resume = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resumeDelay, execute: work)
        publishDebug()
    }

    func recenter() {
        resume?.cancel()
        resume = nil
        paused = false
        fit(animated: true)
    }

    /// The representable hands its view over once; the first fit waits for a real size.
    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
        mapView.delegate = self
        DispatchQueue.main.async { [weak self] in
            guard let self, let trip = self.trip, let state = self.state else { return }
            self.recompute(trip: trip, state: state)
            if self.refits == 0 { self.fit(animated: false) }
        }
    }

    func stop() {
        resume?.cancel()
        feed.pause()
    }

    // MARK: Rules

    private func recompute(trip: TransitItinerary, state: TransitGoState) {
        frame = TransitGoMap.shared.frame(
            trip: trip, legIndex: state.legIndex, phase: state.phase, user: user)
        let near = TransitGoMap.shared.nearLine(
            trip: trip, legIndex: state.legIndex, phase: state.phase, user: user,
            radiusMeters: TransitGoMap.shared.NEAR_LINE_METERS)
        let box = near.flatMap { TransitGoMap.shared.requestBox(line: $0, user: user) }
        feed.follow(line: near?.label ?? "", box: box)
        let key = near.map { "\($0.legIndex)|\($0.label)" } ?? ""
        if key != lineKey {
            lineKey = key
            line = near
            drawLine()
        }
        drawLeg()
        publishDebug()
    }

    private func refitIfNeeded() {
        guard !paused, let mapView, let frame else { return }
        let visible = Self.box(mapView.visibleCoordinateBounds)
        if TransitGoMap.shared.needsRefit(
            visible: visible, user: user, target: frame.target, inset: TransitGoMap.shared.SAFE_INSET) {
            fit(animated: true)
        }
    }

    private func fit(animated: Bool) {
        guard !paused, let mapView, let box = frame?.box, mapView.bounds.width > 0 else { return }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: box.south, longitude: box.west),
            ne: CLLocationCoordinate2D(latitude: box.north, longitude: box.east))
        mapView.setVisibleCoordinateBounds(
            bounds, edgePadding: Self.padding, animated: animated, completionHandler: nil)
        refits += 1
        publishDebug()
    }

    // MARK: Drawing

    private func drawLeg() {
        guard let mapView else { return }
        let coordinates = (frame?.leg ?? []).map(Self.coordinate)
        if legShape?.coordinates.map(\.latitude) != coordinates.map(\.latitude)
            || legShape?.coordinates.map(\.longitude) != coordinates.map(\.longitude) {
            if let legShape { mapView.removeAnnotation(legShape) }
            legShape = nil
            if coordinates.count >= 2 {
                var points = coordinates
                let shape = MLNPolyline(coordinates: &points, count: UInt(points.count))
                mapView.addAnnotation(shape)
                legShape = shape
            }
        }
        let target = frame?.target.map(Self.coordinate)
        if let pin = targetPin, let target, pin.coordinate.latitude == target.latitude,
           pin.coordinate.longitude == target.longitude {
            return
        }
        if let targetPin { mapView.removeAnnotation(targetPin) }
        targetPin = nil
        if let target {
            let pin = MLNPointAnnotation()
            pin.coordinate = target
            pin.title = state?.targetName.isEmpty == false ? state?.targetName : nil
            mapView.addAnnotation(pin)
            targetPin = pin
        }
    }

    private func drawLine() {
        let drawn = line.map {
            [TransitLinesLayer.Line(
                label: $0.label, colorHex: $0.colorHex, live: false, delayLevel: "none",
                coordinates: $0.path.map(Self.coordinate))]
        } ?? []
        let style = styleReady ? mapView?.style : nil
        if let style { removeDots(style) }
        lines.set(drawn, on: style)
        feedVehiclesToLayer()
    }

    private func vehiclesChanged() {
        feedVehiclesToLayer()
        publishDebug()
    }

    private func feedVehiclesToLayer() {
        let drawn = (line == nil ? [] : feed.vehicles).map {
            TransitVehicleLayer.Vehicle(
                id: $0.id, label: $0.label, colorHex: $0.colorHex, bearing: $0.bearing,
                coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng),
                estimated: $0.estimated, direction: $0.headsign)
        }
        vehicleLayer.set(drawn, on: nil)
        if styleReady, let style = mapView?.style { applyVehicles(style) }
        if vehicleCount != drawn.count { vehicleCount = drawn.count }
    }

    /// GO's vehicles: the shared symbol layer, plus a plain disk in the line color under it, so a
    /// dot stays visible at a glance even where the symbol's glyph or chevron is not drawn.
    /// `TransitLinesLayer.apply` also installs the main map's vehicle singleton on this style;
    /// GO's layer uses the same identifiers, so this pass, always run after it, replaces those.
    private func applyVehicles(_ style: MLNStyle) {
        removeDots(style)
        vehicleLayer.apply(to: style)
        guard vehicleLayer.drawnCount > 0,
              let source = style.source(withIdentifier: TransitVehicleLayer.layerPrefix),
              let symbol = style.layer(withIdentifier: Self.vehicleSymbolId) else { return }
        let dot = MLNCircleStyleLayer(identifier: Self.dotLayerId, source: source)
        dot.circleRadius = NSExpression(forConstantValue: 9)
        dot.circleColor = NSExpression(
            forConstantValue: line.flatMap { UIColor(transitHex: $0.colorHex) } ?? UIColor.systemBlue)
        dot.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        dot.circleStrokeWidth = NSExpression(forConstantValue: 2)
        style.insertLayer(dot, below: symbol)
    }

    /// The disk shares the vehicle source; the page keeps a source while a layer uses it, so the
    /// disk must go before any pass that replaces that source.
    private func removeDots(_ style: MLNStyle) {
        if let dot = style.layer(withIdentifier: Self.dotLayerId) { style.removeLayer(dot) }
    }

    private static let dotLayerId = "vela-go-vehicle-dot"
    private static let vehicleSymbolId = "vela-transit-vehicles-symbol"

    // MARK: MLNMapViewDelegate

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        styleReady = true
        removeDots(style)
        lines.apply(to: style)
        applyVehicles(style)
        publishDebug()
    }

    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        updateUser(userLocation?.location)
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
        // The page's first report comes after layout: the first frame can use the real size.
        if refits == 0 { fit(animated: false) }
        publishDebug()
    }

    func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat { 5 }

    func mapView(_ mapView: MLNMapView, alphaForShapeAnnotation annotation: MLNShape) -> CGFloat { 0.9 }

    func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
        if state?.phase == "RIDE", let hex = line?.colorHex {
            return UIColor(transitHex: hex) ?? .systemBlue
        }
        return .systemBlue
    }

    func mapView(_ mapView: MLNMapView, annotationCanShowCallout annotation: MLNAnnotation) -> Bool { true }

    // MARK: Debug

    /// `go_map_fit=1` when the user (with a fix) and the target are inside the visible bounds the
    /// map reports; `go_vehicles` counts the dots installed in GO's own vehicle layer.
    private func publishDebug() {
        var fit = 0
        var user = 0
        if let mapView, let target = frame?.target {
            let visible = Self.box(mapView.visibleCoordinateBounds)
            let userInside = self.user.map { visible.contains(point: $0) } ?? true
            fit = visible.contains(point: target) && userInside ? 1 : 0
            user = self.user == nil ? 0 : 1
        }
        let line = self.line?.label ?? "none"
        let next = "go_map=\(hasMap ? 1 : 0) go_map_style=\(styleReady ? 1 : 0)"
            + " go_map_target=\(frame?.targetKind ?? "none") go_map_user=\(user) go_map_fit=\(fit)"
            + " go_map_refits=\(refits) go_map_paused=\(paused ? 1 : 0)"
            + " go_line=\(line) go_lines=\(lines.drawnCount) go_vehicles=\(vehicleLayer.drawnCount)"
            + " go_vehicles_estimated=\(vehicleLayer.allEstimated ? 1 : 0)"
            + " go_vehicle_hint=\(vehicleHint == nil ? 0 : 1)"
            + " go_dots=\(mapView?.style?.layer(withIdentifier: Self.dotLayerId) == nil ? 0 : 1)"
            + " " + (mapView?.webMapDebugLine ?? "web_ready=0")
        if next != debugLine { debugLine = next }
    }

    private static func box(_ bounds: MLNCoordinateBounds) -> TransitGoMapBox {
        TransitGoMapBox(south: bounds.sw.latitude, west: bounds.sw.longitude,
                        north: bounds.ne.latitude, east: bounds.ne.longitude)
    }

    private static func coordinate(_ point: LatLng) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
    }
}
