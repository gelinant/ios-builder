import CoreLocation
import Foundation
import MapLibre
import UIKit
import VelaCore

/// Owns the imperative side of the map so SwiftUI views can drive it.
final class MapController: ObservableObject {
    @Published private(set) var isFollowingUser = false
    @Published private(set) var offlineMapStatus = ""

    /// Called after each camera move with the visible map.
    var onViewportChange: ((MapViewport) -> Void)?
    /// Called with each user location fix the map receives.
    var onUserLocation: ((CLLocationCoordinate2D) -> Void)?

    /// Called with the index of the alternate route the user tapped.
    var onRouteTap: ((Int) -> Void)?

    private weak var mapView: MLNMapView?
    private var resultPins: [MLNPointAnnotation] = []
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
