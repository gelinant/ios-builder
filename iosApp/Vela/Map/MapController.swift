import CoreLocation
import Foundation
import MapLibre
import UIKit

/// Owns the imperative side of the map so SwiftUI views can drive it.
final class MapController: ObservableObject {
    @Published private(set) var isFollowingUser = false

    /// Called after each camera move with the visible map.
    var onViewportChange: ((MapViewport) -> Void)?
    /// Called with each user location fix the map receives.
    var onUserLocation: ((CLLocationCoordinate2D) -> Void)?

    /// Called with the index of the alternate route the user tapped.
    var onRouteTap: ((Int) -> Void)?
    /// Called with the index of the saved marker the user tapped.
    var onSavedTap: ((Int) -> Void)?

    private weak var mapView: MLNMapView?
    private var resultPins: [MLNPointAnnotation] = []
    private var savedPins: [MLNPointAnnotation] = []
    private var savedMarkers: [SavedMapMarker] = []
    private let routes = RouteLayers()

    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
    }

    func showUser() {
        guard let mapView else { return }
        mapView.showsUserLocation = true
        mapView.setUserTrackingMode(.follow, animated: LaunchOptions.current.animates, completionHandler: nil)
    }

    func trackingModeDidChange(_ mode: MLNUserTrackingMode) {
        isFollowingUser = mode != .none
    }

    /// The visible map, or nil before the map has a size.
    func currentViewport() -> MapViewport? {
        guard let mapView, mapView.bounds.width > 0, mapView.bounds.height > 0 else { return nil }
        let bounds = mapView.visibleCoordinateBounds
        return MapViewport(
            south: bounds.sw.latitude, west: bounds.sw.longitude,
            north: bounds.ne.latitude, east: bounds.ne.longitude,
            zoom: mapView.zoomLevel)
    }

    func regionDidChange() {
        if let viewport = currentViewport() {
            onViewportChange?(viewport)
        }
    }

    func userLocationDidUpdate(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        onUserLocation?(coordinate)
    }

    /// Replaces the result pins. The camera moves only when most of them are out of view.
    func showResults(_ rows: [SearchRow], insets: UIEdgeInsets) {
        guard let mapView else { return }
        if !resultPins.isEmpty {
            mapView.removeAnnotations(resultPins)
        }
        resultPins = rows.map { row in
            let pin = MLNPointAnnotation()
            pin.coordinate = CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude)
            pin.title = row.name
            pin.subtitle = row.address
            return pin
        }
        guard !resultPins.isEmpty else { return }
        mapView.addAnnotations(resultPins)
        let visible = mapView.visibleCoordinateBounds
        let inside = resultPins.filter { Self.contains(visible, $0.coordinate) }.count
        if inside * 2 < resultPins.count {
            mapView.showAnnotations(resultPins, edgePadding: insets, animated: LaunchOptions.current.animates, completionHandler: nil)
        }
    }

    /// Centers the map on a result and opens its pin's callout.
    func focus(on row: SearchRow) {
        guard let mapView else { return }
        let target = CLLocationCoordinate2D(latitude: row.latitude, longitude: row.longitude)
        mapView.setCenter(target, zoomLevel: max(mapView.zoomLevel, 15), animated: LaunchOptions.current.animates)
        if let pin = resultPins.first(where: { $0.coordinate.latitude == row.latitude && $0.coordinate.longitude == row.longitude }) {
            mapView.selectAnnotation(pin, animated: false, completionHandler: nil)
        }
    }

    /// Replaces the small saved-place and parking markers without moving the camera.
    func showSaved(_ markers: [SavedMapMarker]) {
        guard let mapView else { return }
        if !savedPins.isEmpty { mapView.removeAnnotations(savedPins) }
        savedMarkers = markers
        savedPins = markers.map { marker in
            let pin = MLNPointAnnotation()
            pin.coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
            pin.title = marker.name
            return pin
        }
        if !savedPins.isEmpty { mapView.addAnnotations(savedPins) }
    }

    func focus(onSaved marker: SavedMapMarker) {
        focus(latitude: marker.latitude, longitude: marker.longitude)
    }

    func focus(latitude: Double, longitude: Double) {
        guard let mapView else { return }
        let target = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        mapView.setCenter(target, zoomLevel: max(mapView.zoomLevel, 15), animated: LaunchOptions.current.animates)
    }

    func didSelectAnnotation(_ annotation: MLNAnnotation) {
        if let index = savedPins.firstIndex(where: { $0 === annotation }) {
            onSavedTap?(index)
        }
    }

    func canShowCallout(_ annotation: MLNAnnotation) -> Bool {
        !savedPins.contains { $0 === annotation }
    }

    /// A small colored disk for saved places, rather than the search results' large pins.
    func annotationView(for annotation: MLNAnnotation) -> MLNAnnotationView? {
        guard let index = savedPins.firstIndex(where: { $0 === annotation }), index < savedMarkers.count else { return nil }
        let view = MLNAnnotationView(annotation: annotation, reuseIdentifier: nil)
        view.frame = CGRect(x: 0, y: 0, width: 14, height: 14)
        let argb = savedMarkers[index].color
        view.backgroundColor = UIColor(
            red: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: CGFloat((argb >> 24) & 0xFF) / 255)
        view.layer.cornerRadius = 7
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.white.cgColor
        return view
    }

    /// Keeps the camera's center above a panel covering the bottom `inset` points.
    func setBottomInset(_ inset: CGFloat) {
        guard let mapView, mapView.contentInset.bottom != inset else { return }
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
    }

    func styleDidLoad(_ style: MLNStyle) {
        routes.apply(to: style)
    }

    /// Draws [lines] with [selected] on top; the camera fits them all when [fit].
    func showRoutes(_ lines: [RouteLine], selected: Int, fit: Bool, insets: UIEdgeInsets) {
        guard let mapView else { return }
        routes.set(lines, selected: selected, on: mapView.style)
        guard fit, let first = lines.first?.coordinates.first else { return }
        if !resultPins.isEmpty {
            mapView.removeAnnotations(resultPins)
        }
        mapView.userTrackingMode = .none
        var sw = first
        var ne = first
        for c in lines.flatMap(\.coordinates) {
            sw.latitude = min(sw.latitude, c.latitude)
            sw.longitude = min(sw.longitude, c.longitude)
            ne.latitude = max(ne.latitude, c.latitude)
            ne.longitude = max(ne.longitude, c.longitude)
        }
        mapView.contentInset = .zero
        mapView.setVisibleCoordinateBounds(MLNCoordinateBounds(sw: sw, ne: ne), edgePadding: insets,
                                           animated: LaunchOptions.current.animates, completionHandler: nil)
    }

    /// Takes the routes off the map and puts the result pins back.
    func clearRoutes() {
        guard let mapView else { return }
        routes.set([], selected: -1, on: mapView.style)
        let annotations = mapView.annotations ?? []
        let missing = resultPins.filter { pin in !annotations.contains { $0 === pin } }
        if !missing.isEmpty { mapView.addAnnotations(missing) }
    }

    func handleTap(at point: CGPoint) {
        guard let mapView, onRouteTap != nil else { return }
        let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
        let hits = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: [RouteLayers.altLayer])
        if let index = hits.first?.attribute(forKey: "index") as? NSNumber {
            onRouteTap?(index.intValue)
        }
    }

    var centerCoordinate: CLLocationCoordinate2D? {
        mapView?.centerCoordinate
    }

    private static func contains(_ bounds: MLNCoordinateBounds, _ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= bounds.sw.latitude && c.latitude <= bounds.ne.latitude
            && c.longitude >= bounds.sw.longitude && c.longitude <= bounds.ne.longitude
    }
}
