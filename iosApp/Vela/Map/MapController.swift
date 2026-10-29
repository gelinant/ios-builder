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
    /// A tapped Transitous stop icon.
    var onTransitStopTap: ((TransitStopMarker) -> Void)?
    /// An empty-map long press, ready for reverse geocoding.
    var onMapLongPress: ((CLLocationCoordinate2D) -> Void)?
    /// A direct pan gesture detaches only the navigation camera, never the guidance loop.
    var onNavigationPan: (() -> Void)?

    private weak var mapView: MLNMapView?
    private var navigationCamera = false
    private var navigationFollowing = false
    private var resultPins: [MLNPointAnnotation] = []
    private var savedPins: [MLNPointAnnotation] = []
    private var transitPins: [MLNPointAnnotation] = []
    private var transitStops: [TransitStopMarker] = []
    private var droppedPin: MLNPointAnnotation?
    private let routes = RouteLayers()
    private let layers = MapLayers()
    private let rasters = MapRasterLayers()
    private let savedLayer = SavedMarkerLayer()
    private let savedShapeLayer = SavedShapeLayer()
    private var savedShapes: [SavedMapShape] = []
    private var savedShapesTask: Task<Void, Never>?
    private var layerData = MapLayerData.empty
    private let offline: OfflineStore?
    private let savedStore: SavedStore?
    private var activeOfflineArchive: String?
    private var currentStyleURL: URL?
    private var offlinePickGeneration = 0
    private var styleObserver: NSObjectProtocol?
    private var worldFocusObserver: NSObjectProtocol?

    init(
        offline: OfflineStore? = AppGraph.session.offline,
        saved: SavedStore? = AppGraph.session.saved
    ) {
        self.offline = offline
        // Every stored property must be set before an observer closure can capture self.
        self.savedStore = saved
        styleObserver = NotificationCenter.default.addObserver(
            forName: MapStyleSettings.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.offlinePickGeneration += 1
            self.refreshOfflineStyle(generation: self.offlinePickGeneration)
        }
        // World-layer rows ask for a recenter without holding the controller (WLD-1).
        worldFocusObserver = NotificationCenter.default.addObserver(
            forName: WorldLayers.focusNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.focusWorldLayer(note)
        }
        // A list's lines and areas change on their own edits, not through the marker feed that
        // MapScreen publishes, so the shape layer watches the saved facet itself.
        if let saved {
            savedShapesTask = Task { @MainActor [weak self] in
                for await state in saved.state {
                    self?.showSavedShapes(state.mapShapes())
                }
            }
        }
    }

    deinit {
        if let styleObserver {
            NotificationCenter.default.removeObserver(styleObserver)
        }
        if let worldFocusObserver {
            NotificationCenter.default.removeObserver(worldFocusObserver)
        }
        savedShapesTask?.cancel()
    }

    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
    }

    /// Picks the first style before MapLibre creates its glyph and sprite managers, which matters
    /// when the process starts without a network.
    func initialStyleURL() -> URL {
        let center = LaunchOptions.current.camera.center
        let options = MapStyleSettings.current()
        let picked = makeOfflineStyle(latitude: center.latitude, longitude: center.longitude,
                                      options: options)
        currentStyleURL = picked?.url
            ?? (try? MapStyleBuilder.onlineStyleURL(options: options))
            ?? MapDefaults.styleURL
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
        let options = MapStyleSettings.current()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let picked = self.makeOfflineStyle(latitude: center.latitude, longitude: center.longitude,
                                               options: options)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.offlinePickGeneration else { return }
                let nextURL = picked?.url
                    ?? (try? MapStyleBuilder.onlineStyleURL(options: options))
                    ?? MapDefaults.styleURL
                guard nextURL != self.currentStyleURL else { return }
                self.currentStyleURL = nextURL
                self.activeOfflineArchive = picked?.archive
                self.offlineMapStatus = picked.map { self.status(archive: $0.archive, style: $0.url) } ?? ""
                self.mapView?.styleURL = nextURL
            }
        }
    }

    private func makeOfflineStyle(latitude: Double, longitude: Double,
                                  options: MapStyleOptions) -> (archive: String, url: URL)? {
        guard let offline,
              let archive = offline.localBasemapPath(lat: latitude, lng: longitude),
              FileManager.default.fileExists(
                atPath: offline.glyphsPath + "/Noto Sans Regular/0-255.pbf") else { return nil }
        guard let url = try? OfflineStyleFactory.makeStyle(
            archivePath: archive, glyphsPath: offline.glyphsPath, spritesPath: offline.spritesPath,
            options: options
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
            // WLD-1: the one world-layer socket. It returns at once while no layer is installed.
            WorldLayersHub.shared.viewportChanged(
                viewport, style: mapView?.style, offline: activeOfflineArchive != nil)
        }
        scheduleOfflineStyleRefresh()
        if let mapView, let style = mapView.style {
            layers.updateVisibility(zoom: mapView.zoomLevel, style: style)
        }
        if let mapView {
            savedLayer.applyZoom(mapView.zoomLevel, on: mapView)
        }
    }

    /// Recenters on a world-layer row that carries a coordinate; posted by `WorldLayers.focus`.
    private func focusWorldLayer(_ note: Notification) {
        guard let lat = note.userInfo?[WorldLayers.latitudeKey] as? Double,
              let lng = note.userInfo?[WorldLayers.longitudeKey] as? Double,
              let mapView else { return }
        mapView.setCenter(CLLocationCoordinate2D(latitude: lat, longitude: lng),
                          zoomLevel: max(mapView.zoomLevel, 12), animated: false)
    }

    /// Applies the layer sheet's data. Stored before the style is ready and replayed on each load.
    func applyLayers(_ data: MapLayerData) {
        layerData = data
        guard let style = mapView?.style else { return }
        let offline = activeOfflineArchive != nil
        layers.apply(data, style: style, offline: offline)
        rasters.apply(data, style: style, offline: offline, config: .live())
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

    /// Replaces the saved-place pins without moving the camera. The pins come from the shared
    /// store so each carries its list's colour and icon; [markers] stays the Swift mirror's feed,
    /// which is also what a tap's index reads.
    func showSaved(_ markers: [SavedMapMarker]) {
        guard let mapView else { return }
        let pins = savedStore?.mapPins() ?? markers.map(Self.fallbackPin)
        savedLayer.show(pins, on: mapView)
        savedPins = savedLayer.annotations
        savedLayer.applyZoom(mapView.zoomLevel, on: mapView)
    }

    /// The list's lines and areas. Called on every saved-state publish and by the style load.
    private func showSavedShapes(_ shapes: [SavedMapShape]) {
        savedShapes = shapes
        savedShapeLayer.show(shapes, on: mapView?.style)
    }

    private static func fallbackPin(_ marker: SavedMapMarker) -> SavedMapPin {
        SavedMapPin(
            key: marker.id,
            placeId: marker.placeId,
            listId: marker.listId,
            name: marker.name,
            lat: marker.latitude,
            lng: marker.longitude,
            color: Int32(bitPattern: marker.color),
            icon: "bookmark",
            parking: marker.parking)
    }

    func focus(onSaved marker: SavedMapMarker) {
        focus(latitude: marker.latitude, longitude: marker.longitude)
    }

    /// Replaces the Transitous stop icons without moving the camera. Their board opens on tap.
    func showTransitStops(_ markers: [TransitStopMarker]) {
        guard let mapView else { return }
        if !transitPins.isEmpty { mapView.removeAnnotations(transitPins) }
        transitStops = markers
        transitPins = markers.map { marker in
            let pin = MLNPointAnnotation()
            pin.coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
            pin.title = marker.name
            return pin
        }
        if !transitPins.isEmpty { mapView.addAnnotations(transitPins) }
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
        } else if let index = transitPins.firstIndex(where: { $0 === annotation }), index < transitStops.count {
            onTransitStopTap?(transitStops[index])
        }
    }

    func canShowCallout(_ annotation: MLNAnnotation) -> Bool {
        !savedPins.contains { $0 === annotation } && !transitPins.contains { $0 === annotation }
    }

    /// A small colored disk for saved places, rather than the search results' large pins. Transit
    /// stop icons carry their feed's mode glyph, never a fabricated operator mark.
    func annotationView(for annotation: MLNAnnotation) -> MLNAnnotationView? {
        if let index = transitPins.firstIndex(where: { $0 === annotation }), index < transitStops.count {
            let view = MLNAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
            view.backgroundColor = UIColor.systemBackground
            view.layer.cornerRadius = 12
            view.layer.borderWidth = 1.5
            view.layer.borderColor = UIColor.systemTeal.cgColor
            let glyph = UIImageView(image: UIImage(systemName: transitStops[index].symbol))
            glyph.tintColor = .systemTeal
            glyph.contentMode = .scaleAspectFit
            glyph.frame = view.bounds.insetBy(dx: 5, dy: 5)
            view.addSubview(glyph)
            return view
        }
        guard savedPins.contains(where: { $0 === annotation }) else { return nil }
        return savedLayer.view(for: annotation, zoom: mapView?.zoomLevel ?? 0)
    }

    /// Keeps the camera's center above a panel covering the bottom `inset` points.
    func setBottomInset(_ inset: CGFloat) {
        guard let mapView, mapView.contentInset.bottom != inset else { return }
        mapView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: inset, right: 0)
    }

    func styleDidLoad(_ style: MLNStyle) {
        MapStyleImages.install(in: style)
        if let archive = activeOfflineArchive,
           style.source(withIdentifier: OfflineStyleFactory.sourceId) == nil {
            let configuration = "pmtiles://" + URL(fileURLWithPath: archive).absoluteString
            let source = MLNVectorTileSource(
                identifier: OfflineStyleFactory.sourceId, configurationURLString: configuration)
            style.addSource(source)
        }
        routes.apply(to: style)
        let offline = activeOfflineArchive != nil
        layers.apply(layerData, style: style, offline: offline)
        rasters.apply(layerData, style: style, offline: offline, config: .live())
        // After the rasters, so a drawing stays above a satellite image, as on Android.
        savedShapeLayer.show(savedShapes, on: style)
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
        var annotations = resultPins + transitPins
        if let droppedPin { annotations.append(droppedPin) }
        if let annotation = closestAnnotation(to: point, in: annotations, on: mapView) {
            mapView.selectAnnotation(annotation, animated: false, completionHandler: nil)
            return
        }
        // Saved pins use the shared tap rule (Android's 22 pt box), tested on the JVM.
        if let index = savedPinIndex(at: point), index < savedPins.count {
            mapView.selectAnnotation(savedPins[index], animated: false, completionHandler: nil)
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

    /// The saved pin under a tap, through the shared projection rather than the annotation's own
    /// frame: a pin shrinks far out, so the touch box must not follow the view's rectangle.
    private func savedPinIndex(at point: CGPoint) -> Int? {
        guard let mapView, let savedStore, !savedPins.isEmpty else { return nil }
        let bounds = mapView.bounds
        let centre = mapView.convert(CGPoint(x: bounds.midX, y: bounds.midY), toCoordinateFrom: mapView)
        let camera = SavedMapCamera(
            centerLat: centre.latitude,
            centerLng: centre.longitude,
            zoom: mapView.zoomLevel,
            width: Double(bounds.width),
            height: Double(bounds.height))
        let index = savedStore.nearestPin(x: Double(point.x), y: Double(point.y), camera: camera)
        return index >= 0 && index < savedPins.count ? Int(index) : nil
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
