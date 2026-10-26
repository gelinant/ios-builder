import CoreLocation
import Foundation
import MapLibre
import UIKit
import VelaCore

/// Owns the imperative side of the map so SwiftUI views can drive it.
final class MapController: ObservableObject {
    @Published private(set) var isFollowingUser = false
    @Published private(set) var offlineMapStatus = ""
    private(set) var navigationUpdateCount = 0

    /// Called after each camera move with the visible map.
    var onViewportChange: ((MapViewport) -> Void)?
    /// Called with each user location fix the map receives.
    var onUserLocation: ((CLLocationCoordinate2D) -> Void)?

    /// Called with the index of the alternate route the user tapped.
    var onRouteTap: ((Int) -> Void)?
    /// Called with the index of the saved marker the user tapped.
    var onSavedTap: ((Int) -> Void)?
    /// Called with the index of a search-result pin.
    var onResultTap: ((Int) -> Void)?
    /// A named OpenFreeMap POI, with its own point and kind.
    var onPoiTap: ((String, CLLocationCoordinate2D, String?) -> Void)?
    /// An empty-map long press, ready for reverse geocoding.
    var onMapLongPress: ((CLLocationCoordinate2D) -> Void)?
    /// A direct pan gesture detaches only the navigation camera, never the guidance loop.
    var onNavigationPan: (() -> Void)?

    private weak var mapView: MLNMapView?
    private var navigationCamera = false
    private var navigationFollowing = false
    private var resultPins: [MLNPointAnnotation] = []
    private var savedPins: [MLNPointAnnotation] = []
    private var droppedPin: MLNPointAnnotation?
    private var savedMarkers: [SavedMapMarker] = []
    private let routes = RouteLayers()
    private let offline: OfflineStore?
    private var activeOfflineArchive: String?
    private var currentStyleURL: URL?
    private var offlinePickGeneration = 0

    init(offline: OfflineStore? = AppGraph.session.offline) {
        self.offline = offline
    }

    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
    }

    /// Picks the first style before MapLibre creates its glyph and sprite managers, which matters
    /// when the process starts without a network.
    func initialStyleURL() -> URL {
        let center = LaunchOptions.current.camera.center
        let picked = makeOfflineStyle(latitude: center.latitude, longitude: center.longitude)
        currentStyleURL = picked?.url ?? MapDefaults.styleURL
        activeOfflineArchive = picked?.archive
        offlineMapStatus = picked.map { status(archive: $0.archive, style: $0.url) } ?? ""
        return currentStyleURL!
    }

    /// Camera-idle selection, debounced so a pan cannot reload the style on every callback.
    func scheduleOfflineStyleRefresh() {
        offlinePickGeneration += 1
        let generation = offlinePickGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.refreshOfflineStyle(generation: generation)
        }
    }

    /// Immediate selection after an install or delete.
    func refreshOfflineStyle() {
        offlinePickGeneration += 1
        refreshOfflineStyle(generation: offlinePickGeneration)
    }

    private func refreshOfflineStyle(generation: Int) {
        let center = centerCoordinate ?? LaunchOptions.current.camera.center
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let picked = self.makeOfflineStyle(latitude: center.latitude, longitude: center.longitude)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.offlinePickGeneration else { return }
                let nextURL = picked?.url ?? MapDefaults.styleURL
                guard nextURL != self.currentStyleURL else { return }
                self.currentStyleURL = nextURL
                self.activeOfflineArchive = picked?.archive
                self.offlineMapStatus = picked.map { self.status(archive: $0.archive, style: $0.url) } ?? ""
                self.mapView?.styleURL = nextURL
            }
        }
    }

    private func makeOfflineStyle(latitude: Double, longitude: Double) -> (archive: String, url: URL)? {
        guard let offline,
              let archive = offline.localBasemapPath(lat: latitude, lng: longitude),
              FileManager.default.fileExists(
                atPath: offline.glyphsPath + "/Noto Sans Regular/0-255.pbf") else { return nil }
        guard let url = try? OfflineStyleFactory.makeStyle(
            archivePath: archive, glyphsPath: offline.glyphsPath, spritesPath: offline.spritesPath
        ) else { return nil }
        return (archive, url)
    }

    private func status(archive: String, style: URL) -> String {
        "archive=\(URL(fileURLWithPath: archive).lastPathComponent) remote=\(OfflineStyleFactory.remoteURLCount(in: style))"
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
        scheduleOfflineStyleRefresh()
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
        focus(latitude: latitude, longitude: longitude, zoom: nil)
    }

    /// Centers on a point, honoring a link's zoom when it named one.
    func focus(latitude: Double, longitude: Double, zoom: Double?) {
        guard let mapView else { return }
        let target = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let level = zoom.map { min(max($0, 1), 21) } ?? max(mapView.zoomLevel, 15)
        mapView.setCenter(target, zoomLevel: level, animated: LaunchOptions.current.animates)
    }

    func showDroppedPin(latitude: Double, longitude: Double, title: String) {
        guard let mapView else { return }
        clearDroppedPin()
        let pin = MLNPointAnnotation()
        pin.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        pin.title = title
        droppedPin = pin
        mapView.addAnnotation(pin)
    }

    func clearDroppedPin() {
        guard let pin = droppedPin else { return }
        mapView?.removeAnnotation(pin)
        droppedPin = nil
    }

    func didSelectAnnotation(_ annotation: MLNAnnotation) {
        if let index = resultPins.firstIndex(where: { $0 === annotation }) {
            onResultTap?(index)
        } else if let index = savedPins.firstIndex(where: { $0 === annotation }) {
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
        if let archive = activeOfflineArchive,
           style.source(withIdentifier: OfflineStyleFactory.sourceId) == nil {
            let configuration = "pmtiles://" + URL(fileURLWithPath: archive).absoluteString
            let source = MLNVectorTileSource(
                identifier: OfflineStyleFactory.sourceId, configurationURLString: configuration)
            style.addSource(source)
        }
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
        guard let mapView else { return }
        // Deliberate markers outrank the basemap, then an alternate route outranks its POI labels.
        var annotations = resultPins + savedPins
        if let droppedPin { annotations.append(droppedPin) }
        if let annotation = closestAnnotation(to: point, in: annotations, on: mapView) {
            mapView.selectAnnotation(annotation, animated: false, completionHandler: nil)
            return
        }
        let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
        let routes = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: [RouteLayers.altLayer])
        if let index = routes.first?.attribute(forKey: "index") as? NSNumber {
            onRouteTap?(index.intValue)
            return
        }
        let layers: Set<String> = ["poi_r1", "poi_r7", "poi_r20", "poi_transit"]
        let underFinger = poiCandidates(mapView.visibleFeatures(at: point, styleLayerIdentifiers: layers), point: point, mapView: mapView)
        let nearby = underFinger.isEmpty
            ? poiCandidates(mapView.visibleFeatures(in: rect, styleLayerIdentifiers: layers), point: point, mapView: mapView)
            : underFinger
        if let hit = nearby.min(by: { $0.distanceSquared < $1.distanceSquared }) {
            onPoiTap?(hit.name, hit.coordinate, hit.kind)
        }
    }

    func handleLongPress(at point: CGPoint) {
        guard let mapView else { return }
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        onMapLongPress?(coordinate)
    }

    private func closestAnnotation(to point: CGPoint, in annotations: [MLNPointAnnotation], on mapView: MLNMapView) -> MLNPointAnnotation? {
        var closest: MLNPointAnnotation?
        var bestDistance = CGFloat(36)
        for annotation in annotations {
            let screen = mapView.convert(annotation.coordinate, toPointTo: mapView)
            let dx = screen.x - point.x
            let dy = screen.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= bestDistance {
                bestDistance = distance
                closest = annotation
            }
        }
        return closest
    }

    private struct PoiCandidate {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let kind: String?
        let distanceSquared: CGFloat
    }

    private func poiCandidates(_ features: [any MLNFeature], point: CGPoint, mapView: MLNMapView) -> [PoiCandidate] {
        features.compactMap { feature in
            guard let pointFeature = feature as? MLNPointFeature,
                  let name = Self.placeName(feature), !name.isEmpty else { return nil }
            let screen = mapView.convert(pointFeature.coordinate, toPointTo: mapView)
            let dx = screen.x - point.x
            let dy = screen.y - point.y
            return PoiCandidate(
                name: name, coordinate: pointFeature.coordinate,
                kind: Self.stringAttribute(feature, key: "subclass") ?? Self.stringAttribute(feature, key: "class"),
                distanceSquared: dx * dx + dy * dy)
        }
    }

    private static func placeName(_ feature: any MLNFeature) -> String? {
        for key in ["name", "name:latin", "name:en"] {
            if let name = stringAttribute(feature, key: key), !name.isEmpty { return name }
        }
        return nil
    }

    private static func stringAttribute(_ feature: any MLNFeature, key: String) -> String? {
        (feature.attribute(forKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var centerCoordinate: CLLocationCoordinate2D? {
        mapView?.centerCoordinate
    }

    private static func contains(_ bounds: MLNCoordinateBounds, _ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= bounds.sw.latitude && c.latitude <= bounds.ne.latitude
            && c.longitude >= bounds.sw.longitude && c.longitude <= bounds.ne.longitude
    }
}
