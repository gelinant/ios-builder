import CoreLocation
import Foundation
import MapLibre
import UIKit

/// Owns the imperative side of the map so SwiftUI views can drive it.
final class MapController: ObservableObject {
    @Published private(set) var isFollowingUser = false
    private(set) var navigationUpdateCount = 0

    /// Called after each camera move with the visible map.
    var onViewportChange: ((MapViewport) -> Void)?
    /// Called with each user location fix the map receives.
    var onUserLocation: ((CLLocationCoordinate2D) -> Void)?

    /// Called with the index of the alternate route the user tapped.
    var onRouteTap: ((Int) -> Void)?
    /// A direct pan gesture detaches only the navigation camera, never the guidance loop.
    var onNavigationPan: (() -> Void)?

    private weak var mapView: MLNMapView?
    private var navigationCamera = false
    private var navigationFollowing = false
    private var resultPins: [MLNPointAnnotation] = []
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
        if !navigationCamera {
            isFollowingUser = mode != .none
        }
    }

    /// Enters the process-owned drive camera. Fixes come from the filtered location pipeline,
    /// rather than MapLibre's independent location manager.
    func beginNavigation() {
        guard let mapView else { return }
        navigationCamera = true
        navigationFollowing = true
        isFollowingUser = true
        navigationUpdateCount = 0
        mapView.showsUserLocation = true
        mapView.contentInset = UIEdgeInsets(top: 110, left: 0, bottom: 100, right: 0)
        if mapView.zoomLevel < 16 {
            mapView.setZoomLevel(16.5, animated: LaunchOptions.current.animates)
        }
    }

    func setNavigationFollowing(_ on: Bool) {
        guard navigationCamera else { return }
        navigationFollowing = on
        isFollowingUser = on
    }

    func userPanned() {
        guard navigationCamera, navigationFollowing else { return }
        navigationFollowing = false
        isFollowingUser = false
        onNavigationPan?()
    }

    func updateNavigation(coordinate: CLLocationCoordinate2D, speedMps: Double, heading: CLLocationDirection) {
        guard navigationCamera, navigationFollowing, CLLocationCoordinate2DIsValid(coordinate), let mapView else { return }
        let speedZoom = speedMps >= 12 ? 16.0 : 16.7
        let zoom = abs(mapView.zoomLevel - speedZoom) > 0.25 ? speedZoom : mapView.zoomLevel
        mapView.setCenter(coordinate, zoomLevel: zoom, direction: heading, animated: LaunchOptions.current.animates)
        navigationUpdateCount += 1
    }

    func endNavigation() {
        guard let mapView else { return }
        navigationCamera = false
        navigationFollowing = false
        isFollowingUser = false
        mapView.contentInset = .zero
        mapView.setCenter(mapView.centerCoordinate, zoomLevel: mapView.zoomLevel, direction: 0,
                          animated: LaunchOptions.current.animates)
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
        if !resultPins.isEmpty, mapView.annotations?.isEmpty ?? true {
            mapView.addAnnotations(resultPins)
        }
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
