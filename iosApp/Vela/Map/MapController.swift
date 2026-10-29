import CoreLocation
import Foundation
import MapLibre
import UIKit
import VelaCore

/// Owns the imperative side of the map so SwiftUI views can drive it.
final class MapController: ObservableObject {
    @Published private(set) var isFollowingUser = false
    @Published private(set) var offlineMapStatus = ""
    /// The map's heading in degrees clockwise from north. Zero is north-up.
    @Published private(set) var bearing: Double = 0
    @Published private(set) var zoomLevel: Double = MapDefaults.initialZoom
    /// Real metres covered by one UIKit point at the map's centre latitude.
    @Published private(set) var metersPerPoint: Double = 0
    /// The pin a long press dropped, kept by this controller so the card can dismiss it.
    @Published private(set) var droppedPinCoordinate: CLLocationCoordinate2D?
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
    private var gestureObserver: NSObjectProtocol?
    /// Set while the north lock puts the camera back, so its own region change is not corrected twice.
    private var correctingNorth = false
    /// The line sheet's whole-line request. It draws the feed's shape in the line's color, never a
    /// feed call of its own.
    private var transitLineObserver: NSObjectProtocol?
    /// The style the transit overlays were installed on, so one style load installs them once.
    private var transitStyle: ObjectIdentifier?

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
        // MAP-GESTE: the north lock and the button shape apply at once, without relaunching.
        gestureObserver = NotificationCenter.default.addObserver(
            forName: MapGestureSettings.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyGestureSettings()
        }
        // World-layer rows ask for a recenter without holding the controller (WLD-1).
        worldFocusObserver = NotificationCenter.default.addObserver(
            forName: WorldLayers.focusNotification, object: nil, queue: .main
        ) { [weak self] note in
            self?.focusWorldLayer(note)
        }
        // TRANSIT-WIRE: the line sheet's one map hook. The request already carries the feed's own
        // shape, colour and estimated point, so the map only draws it.
        transitLineObserver = NotificationCenter.default.addObserver(
            forName: .velaTransitLineMapRequest, object: nil, queue: .main
        ) { [weak self] note in
            self?.showTransitLine(note)
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
        if let transitLineObserver {
            NotificationCenter.default.removeObserver(transitLineObserver)
        }
        if let gestureObserver {
            NotificationCenter.default.removeObserver(gestureObserver)
        }
        savedShapesTask?.cancel()
    }

    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
        // The chrome draws its own compass and scale bar, with the bearing and the real metres.
        mapView.compassView.isHidden = true
        mapView.scaleBar.isHidden = true
        // A turn that stops within 12 degrees of north goes back to north, as on Android.
        mapView.toleranceForSnappingToNorth = 12
        applyGestureSettings()
    }

    /// Settings > Map gestures, "Keep north up": no two-finger rotation and a resting camera put
    /// back to north. Programmatic moves (navigation included) still work.
    private func applyGestureSettings() {
        guard let mapView else { return }
        mapView.isRotateEnabled = !MapGestureSettings.shared.keepNorthUp
        if MapGestureSettings.shared.keepNorthUp {
            returnToNorth()
        }
    }

    func returnToNorth() {
        guard let mapView else { return }
        if abs(mapView.direction) > 0.05 {
            correctingNorth = true
            mapView.setDirection(0, animated: LaunchOptions.current.animates)
        }
        bearing = 0
    }

    func zoomIn() {
        guard let mapView else { return }
        mapView.setZoomLevel(min(mapView.zoomLevel + 1, mapView.maximumZoomLevel),
                             animated: LaunchOptions.current.animates)
    }

    func zoomOut() {
        guard let mapView else { return }
        mapView.setZoomLevel(max(mapView.zoomLevel - 1, mapView.minimumZoomLevel),
                             animated: LaunchOptions.current.animates)
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
        let direction = MapGestureSettings.shared.keepNorthUp ? 0 : heading
        mapView.setCenter(coordinate, zoomLevel: zoom, direction: direction, animated: LaunchOptions.current.animates)
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
        if let mapView {
            zoomLevel = mapView.zoomLevel
            bearing = mapView.direction
            let latitude = mapView.centerCoordinate.latitude
            metersPerPoint = mapView.metersPerPoint(atLatitude: latitude)
            if correctingNorth && abs(mapView.direction) <= 0.05 {
                correctingNorth = false
            }
            if MapGestureSettings.shared.keepNorthUp,
               abs(mapView.direction) > 0.05, !correctingNorth {
                returnToNorth()
            }
        }
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
        // `apply` sees `lastZoom`, which is still zero when the first style loads. Reapply the
        // current camera so the POI layers are not left at their style-load visibility.
        layers.updateVisibility(zoom: mapView?.zoomLevel ?? 0, style: style)
        MapTapRegistry.audit(style: style)
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
        let stored = savedStore?.mapPins() ?? []
        // The marker feed can arrive one state ahead of the store's frozen value. Draw the feed
        // rather than an empty map, and let the local hit test below keep the pin tappable.
        let pins = stored.isEmpty && !markers.isEmpty ? markers.map(Self.fallbackPin) : stored
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
        droppedPinCoordinate = pin.coordinate
        mapView.addAnnotation(pin)
    }

    func clearDroppedPin() {
        droppedPinCoordinate = nil
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
        // TRANSIT-WIRE: T-2's colored lines and reach hull, then TRANSIT-INTERP's estimated
        // vehicles on the same style pass. Both sit below the map's labels, so the SwiftUI panels
        // stay above them and the map's own tap handlers are untouched.
        let transitKey = ObjectIdentifier(style)
        if transitStyle != transitKey {
            TransitOverlays.apply(to: style)
            TransitVehicleOverlays.apply(to: style)
            transitStyle = transitKey
        }
        let offline = activeOfflineArchive != nil
        layers.apply(layerData, style: style, offline: offline)
        rasters.apply(layerData, style: style, offline: offline, config: .live())
        // The style can finish loading after the camera was set, so `lastZoom` is not the live
        // zoom. Without this, only `poi_transit` is visible until the next camera move.
        layers.updateVisibility(zoom: mapView?.zoomLevel ?? 0, style: style)
        // After the rasters, so a drawing stays above a satellite image, as on Android.
        savedShapeLayer.show(savedShapes, on: style)
        MapTapRegistry.audit(style: style)
    }

    /// TRANSIT-WIRE: the live panel's two models publish here. The map stores the descriptors in
    /// the layer singletons so a later style load redraws them without another request.
    func showTransitLive(_ models: [TransitLiveLine], reach: TransitReachArea?) {
        TransitOverlays.set(lines: models, reach: reach, on: mapView?.style)
    }

    /// The vehicles tab's own estimates, already interpolated by its model. A nil style keeps them
    /// in the layer, which the next style load applies.
    func showTransitVehicles(_ models: [TransitVehicle]) {
        TransitVehicleOverlays.set(models: models, on: mapView?.style)
    }

    /// The whole line of the line sheet, in the feed's shape or its stop chain, in the feed's color
    /// (or the mode color the sheet already resolved). The request's estimated point is not drawn
    /// by this pass: the vehicle layer keeps whatever the vehicles model last published.
    private func showTransitLine(_ note: Notification) {
        guard let request = note.object as? TransitLineMapRequest else { return }
        let coordinates = request.shape.count >= 2 ? request.shape : request.stops
        guard coordinates.count >= 2 else { return }
        TransitOverlays.lines.set(
            [TransitLinesLayer.Line(
                label: request.label,
                colorHex: request.colorHex,
                live: request.live,
                delayLevel: "none",
                coordinates: coordinates)],
            on: mapView?.style)
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

    /// Takes the routes off the map and puts the result pins back. The navigation group is
    /// cleared by its own lifecycle (`clearNavigationRoute`), so closing the route sheet cannot
    /// wipe a drive that just started.
    func clearRoutes() {
        guard let mapView else { return }
        routes.set([], selected: -1, on: mapView.style)
        let annotations = mapView.annotations ?? []
        let missing = resultPins.filter { pin in !annotations.contains { $0 === pin } }
        if !missing.isEmpty { mapView.addAnnotations(missing) }
    }

    /// The live drive's own route group: traveled and congestion pieces, road-ahead arrows and
    /// the lane row. It replaces the preview line while navigating and is cleared with it.
    func showNavigationRoute(_ draw: NavRouteDraw) {
        routes.setNavigation(draw, on: mapView?.style)
    }

    /// Free driving and the end of a drive leave no navigation line behind.
    func clearNavigationRoute() {
        routes.setNavigation(nil, on: mapView?.style)
    }

    /// A style tap, routed through the one registry. Annotations and the alternate route keep
    /// their existing precedence; every other drawn layer is decided by MapLibre's z-order.
    func handleTap(at point: CGPoint) {
        guard let mapView else { return }
        // A deliberate saved pin outranks a transit stop or a search result under the same finger.
        // Saved pins use the shared tap rule (Android's 22 pt box), tested on the JVM.
        if let index = savedPinIndex(at: point), index < savedPins.count {
            MapTapDebug.note = "saved"
            MapTapDebug.event = "savedPlace"
            MapTapDebug.layer = "saved-pins"
            MapTapDebug.identifier = savedPins[index].title ?? "-"
            MapTapDebug.detail = savedPins[index].title ?? "-"
            mapView.selectAnnotation(savedPins[index], animated: false, completionHandler: nil)
            return
        }
        // Deliberate markers outrank the basemap, then an alternate route outranks its POI labels.
        var annotations = resultPins + transitPins
        if let droppedPin { annotations.append(droppedPin) }
        if let annotation = closestAnnotation(to: point, in: annotations, on: mapView) {
            mapView.selectAnnotation(annotation, animated: false, completionHandler: nil)
            return
        }
        let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
        if let feature = mapView.visibleFeatures(
            in: rect, styleLayerIdentifiers: [RouteLayers.altLayer]).first,
           let index = feature.attribute(forKey: "index") as? NSNumber {
            onRouteTap?(index.intValue)
            return
        }
        guard let hit = MapTapRegistry.topHit(in: mapView, point: point) else {
            // A fallback for a symbol the registry query missed: the same named POI layers, the
            // nearest one inside the dense-symbol box. It never reorders a registered hit.
            if let place = poiUnderFinger(at: point, mapView: mapView) {
                MapTapDebug.note = "fallback"
                MapTapDebug.layer = "fallback-poi"
                MapTapDebug.identifier = place.name
                MapTapDebug.event = "place"
                MapTapDebug.detail = "\(place.kind ?? "-"):\(place.name)"
                onPoiTap?(place.name, place.coordinate, place.kind)
            }
            return
        }
        let event = MapTapRegistry.event(for: hit, in: mapView, point: point)
        MapTapDebug.event(event, note: "routed")
        dispatchTap(event)
    }

    private struct PlaceCandidate {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let kind: String?
        let distance: CGFloat
    }

    private func poiUnderFinger(at point: CGPoint, mapView: MLNMapView) -> PlaceCandidate? {
        let ids = MapLayers.tilePoiLayerIdentifiers + [MapLayers.velaPoiLayerId]
        let box = MapTapRegistry.denseTolerance
        let rect = CGRect(x: point.x - box, y: point.y - box, width: box * 2, height: box * 2)
        let features = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: Set(ids))
        var best: PlaceCandidate?
        for feature in features {
            guard let pointFeature = feature as? MLNPointFeature,
                  let name = Self.name(of: feature) else { continue }
            let screen = mapView.convert(pointFeature.coordinate, toPointTo: mapView)
            let dx = screen.x - point.x
            let dy = screen.y - point.y
            let candidate = PlaceCandidate(
                name: name, coordinate: pointFeature.coordinate,
                kind: Self.attribute(feature, "subclass") ?? Self.attribute(feature, "class")
                    ?? Self.attribute(feature, "group"),
                distance: CGFloat(sqrt(Double(dx * dx + dy * dy))))
            if best == nil || candidate.distance < best!.distance {
                best = candidate
            }
        }
        return best
    }

    private static func name(of feature: any MLNFeature) -> String? {
        for key in ["name", "name:latin", "name:en", "title"] {
            if let value = attribute(feature, key) { return value }
        }
        return nil
    }

    private static func attribute(_ feature: any MLNFeature, _ key: String) -> String? {
        (feature.attribute(forKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Routes a typed tap to the handler that already owns that kind. World layers keep their
    /// cards in their own files, so aircraft and wiki taps use the existing focus notification.
    private func dispatchTap(_ event: MapTapEvent) {
        switch event {
        case .place(let name, let latitude, let longitude, let kind, _):
            guard !name.isEmpty else {
                MapTapCards.present(
                    feature: kind ?? "Place", name: nil,
                    latitude: latitude, longitude: longitude,
                    missing: "The source sent no name for this place.")
                return
            }
            onPoiTap?(name, CLLocationCoordinate2D(latitude: latitude, longitude: longitude), kind)
        case .camera(let kind, let latitude, let longitude, _):
            MapTapCards.present(
                camera: kind, pin: cameraPin(latitude: latitude, longitude: longitude),
                latitude: latitude, longitude: longitude)
        case .aircraft(let hex, let callsign, let latitude, let longitude):
            guard !hex.isEmpty else {
                MapTapCards.present(
                    feature: "Aircraft", name: callsign,
                    latitude: latitude, longitude: longitude,
                    missing: "The feature sent no ICAO hex.")
                return
            }
            // The aviation layer owns the card; this focus notification is its existing hook.
            WorldLayers.focus(latitude: latitude, longitude: longitude)
        case .ship(let mmsi, let latitude, let longitude):
            let row = WorldLayersHub.shared.rows["maritime"]?
                .first { $0.id == "maritime-ship-\(mmsi)" }
            MapTapCards.present(
                ship: mmsi, row: row, latitude: latitude, longitude: longitude)
        case .wiki(let title, let latitude, let longitude):
            guard !title.isEmpty else {
                MapTapCards.present(
                    feature: "Wikivoyage", name: nil,
                    latitude: latitude, longitude: longitude,
                    missing: "The feature sent no article title.")
                return
            }
            WorldLayers.focus(latitude: latitude, longitude: longitude)
        case .transitStop(let marker):
            guard let marker else { return }
            onTransitStopTap?(marker)
        case .savedPlace(let index):
            onSavedTap?(index)
        case .savedShape(let listId, let index, let name, let closed, let latitude, let longitude):
            let shape = savedShapes.first { $0.listId == listId && Int($0.index) == index }
            MapTapCards.present(
                savedShape: shape, listId: listId, index: index, name: name, closed: closed,
                latitude: latitude, longitude: longitude)
        case .route(let index, let latitude, let longitude):
            if let index {
                onRouteTap?(index)
            } else {
                MapTapCards.present(
                    feature: "Route", name: nil, latitude: latitude, longitude: longitude,
                    missing: "The selected route is already drawn; its sheet has no map-tap hook.")
            }
        case .layerFeature(let kind, let name, let identifier, let latitude, let longitude):
            MapTapCards.present(
                feature: kind, name: name, latitude: latitude, longitude: longitude,
                missing: "Layer \(identifier) sent no further data.")
        case .none:
            break
        }
    }

    /// The camera's own pin, matched by the drawn coordinate. The style source carries only the
    /// kind and the bearing, so the speed limit text comes from the same `MapLayerData` that fed
    /// the shape source rather than from a second fetch.
    private func cameraPin(latitude: Double, longitude: Double) -> LayerPin? {
        let pins = layerData.speedPoints + layerData.alprPoints
            + layerData.packSpeedPoints + layerData.packAlprPoints
        var best: LayerPin?
        var bestDistance = 1e-8
        for pin in pins {
            let dLat = pin.coordinate.lat - latitude
            let dLng = pin.coordinate.lng - longitude
            let distance = dLat * dLat + dLng * dLng
            if distance < bestDistance {
                bestDistance = distance
                best = pin
            }
        }
        return best
    }

    /// The saved pin under a tap, through the shared projection rather than the annotation's own
    /// frame: a pin shrinks far out, so the touch box must not follow the view's rectangle.
    private func savedPinIndex(at point: CGPoint) -> Int? {
        guard let mapView, !savedPins.isEmpty else { return nil }
        if let savedStore {
            let bounds = mapView.bounds
            let centre = mapView.convert(CGPoint(x: bounds.midX, y: bounds.midY),
                                         toCoordinateFrom: mapView)
            let camera = SavedMapCamera(
                centerLat: centre.latitude,
                centerLng: centre.longitude,
                zoom: mapView.zoomLevel,
                width: Double(bounds.width),
                height: Double(bounds.height))
            let index = savedStore.nearestPin(x: Double(point.x), y: Double(point.y), camera: camera)
            if index >= 0 && index < savedPins.count { return Int(index) }
        }
        // The shared projection can lag a marker feed by one state. Fall back to the rendered
        // annotation positions, still with the same 22 point finger box.
        var best: Int?
        var bestDistance = CGFloat(22)
        for (offset, pin) in savedPins.enumerated() {
            let screen = mapView.convert(pin.coordinate, toPointTo: mapView)
            let dx = screen.x - point.x
            let dy = screen.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= bestDistance {
                bestDistance = distance
                best = offset
            }
        }
        return best
    }

    func handleLongPress(at point: CGPoint) {
        guard let mapView else { return }
        let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        // A long press is a deliberate act: answer it at once with a haptic and a local pin. No
        // geocoder runs here; the card's "Look up address" is the only path that asks for one.
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showDroppedPin(latitude: coordinate.latitude, longitude: coordinate.longitude,
                       title: "Dropped pin")
        onMapLongPress?(coordinate)
    }

    private func closestAnnotation(to point: CGPoint, in annotations: [MLNPointAnnotation],
                                   on mapView: MLNMapView) -> MLNPointAnnotation? {
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

    var centerCoordinate: CLLocationCoordinate2D? {
        mapView?.centerCoordinate
    }

    private static func contains(_ bounds: MLNCoordinateBounds, _ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= bounds.sw.latitude && c.latitude <= bounds.ne.latitude
            && c.longitude >= bounds.sw.longitude && c.longitude <= bounds.ne.longitude
    }
}
