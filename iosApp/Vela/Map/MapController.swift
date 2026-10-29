import CoreLocation
import Foundation
import MapLibre
import UIKit
import VelaCore

/// Settings > Navigation camera. The auto-zoom keys are Android's (`zoom_to_turn`,
/// `zoom_to_turn_floor`); the tilt and lower-third choices are iOS-only because Android keeps
/// those two camera behaviours implicit. The suite is the shared `vela_settings` one.
final class NavCameraSettings: ObservableObject {
    static let shared = NavCameraSettings()
    static let changedNotification = Notification.Name("VelaNavCameraSettingsChanged")

    static let autoZoomKey = "zoom_to_turn"
    static let floorKey = "zoom_to_turn_floor"
    static let tiltKey = "nav_camera_tilt"
    static let lowerThirdKey = "nav_camera_lower_third"

    /// Android's floors: a town, a region, far. The number is the lowest zoom the turn framing
    /// may use, as in `ZoomToTurn.FLOORS`.
    static let floors: [(title: String, value: Double)] = [
        (VelaL10n.text("settings_floor_town"), 12.0), (VelaL10n.text("settings_floor_region"), 10.0), (VelaL10n.text("settings_floor_far"), 8.0),
    ]

    @Published private(set) var autoZoom: Bool
    @Published private(set) var tilt: Bool
    @Published private(set) var lowerThird: Bool
    @Published private(set) var floor: Double

    private let defaults: UserDefaults

    init(defaults: UserDefaults = NavCameraSettings.settingsDefaults()) {
        self.defaults = defaults
        autoZoom = defaults.bool(forKey: Self.autoZoomKey)
        tilt = defaults.object(forKey: Self.tiltKey) == nil
            ? true : defaults.bool(forKey: Self.tiltKey)
        lowerThird = defaults.object(forKey: Self.lowerThirdKey) == nil
            ? true : defaults.bool(forKey: Self.lowerThirdKey)
        let stored = Double(defaults.float(forKey: Self.floorKey))
        floor = Self.floors.contains { $0.value == stored } ? stored : 12.0
        #if DEBUG
        // NavCameraUITests opts in here so the turn framing runs on the fixture drive.
        if ProcessInfo.processInfo.arguments.contains("-VelaNavCameraAutoZoom") {
            autoZoom = true
        }
        #endif
    }

    func setAutoZoom(_ on: Bool) {
        defaults.set(on, forKey: Self.autoZoomKey)
        autoZoom = on
        notify()
    }

    func setTilt(_ on: Bool) {
        defaults.set(on, forKey: Self.tiltKey)
        tilt = on
        notify()
    }

    func setLowerThird(_ on: Bool) {
        defaults.set(on, forKey: Self.lowerThirdKey)
        lowerThird = on
        notify()
    }

    func setFloor(_ value: Double) {
        // Android stores a float; keep the same type so a shared preference file reads both.
        defaults.set(Float(value), forKey: Self.floorKey)
        floor = value
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.changedNotification, object: self)
    }

    static func settingsDefaults() -> UserDefaults {
        UserDefaults(suiteName: SettingsPersistence.settingsSuite) ?? .standard
    }
}

/// The drive camera's arithmetic, ported from Android's `NavFraming` so the car sits in the same
/// place and the next maneuver is framed the same way. Pure values, no MapLibre types.
enum NavCameraFraming {
    /// The car sits this fraction of the map below its centre when the lower-third choice is on:
    /// (1 + pad) / 2, so 72.5 percent down the screen.
    static let lowerThirdPad = 0.45
    static let centerPad = 0.0

    /// The speed zoom is a straight line from a close city view at rest to a wider view at
    /// 30 m/s (108 km/h), Android's `18.5 - speed / 30 * (18.5 - 15.8)`.
    static let zoomAtRest = 18.5
    static let zoomAtSpeed = 15.8
    static let maxSpeedMps = 30.0

    /// MapLibre's iOS cap is 60 degrees; the drive asks for 55 and lies flatter when zoomed out.
    static let wantedTiltDeg = 55.0
    static let maxTiltDeg = 60.0
    static let tiltFullZoom = 15.0
    static let tiltFlatZoom = 12.5

    /// The next maneuver is framed this far under the top chrome's edge, Android's
    /// `TURN_MARGIN_DP`.
    static let turnMarginPoints = 72.0
    static let worldPxAtZoomZero = 512.0
    static let earthCircumferenceM = 40_075_016.686
    static let fieldOfViewRad = 0.6435011087932844
    static let turnYawMaxDeg = 90.0
    static let turnYawBlendLevels = 1.0

    static func speedZoom(_ speedMps: Double) -> Double {
        let share = max(0, min(speedMps, maxSpeedMps)) / maxSpeedMps
        return zoomAtRest - share * (zoomAtRest - zoomAtSpeed)
    }

    /// A small pull-in near the maneuver, always on: the last 250 m tighten the view by 0.35 of a
    /// level. The optional turn framing adds the larger pull-out on top.
    static func proximityZoom(_ base: Double, distanceM: Double) -> Double {
        guard distanceM > 0 else { return base }
        let near = 1 - min(distanceM / 250.0, 1.0)
        return base + 0.35 * near
    }

    static func tiltAt(zoom: Double, wanted: Double = wantedTiltDeg) -> Double {
        let share = (zoom - tiltFlatZoom) / (tiltFullZoom - tiltFlatZoom)
        let cap = wanted * max(0, min(share, 1))
        return min(min(wanted, maxTiltDeg), cap)
    }

    /// Metres in one screen point at [zoom], latitude [latDeg].
    static func metersPerPoint(zoom: Double, latDeg: Double) -> Double {
        earthCircumferenceM * cos(latDeg * .pi / 180)
            / (worldPxAtZoomZero * pow(2.0, zoom))
    }

    /// Ground points reached by [up] screen points above the car, with the camera tilted
    /// [tiltDeg] over a map [height] points tall. Mirrors Android's `NavFraming.groundAhead`.
    static func groundAhead(up: Double, tiltDeg: Double, height: Double) -> Double {
        guard tiltDeg > 0, height > 0 else { return up }
        let p = tiltDeg * .pi / 180
        let d = 0.5 * height / tan(fieldOfViewRad / 2)
        let a = p + atan(up / d)
        if a >= .pi / 2 - 1e-6 { return .infinity }
        return d * cos(p) * tan(a) - d * sin(p)
    }

    /// The zoom at which a point [groundM] metres ahead lands [up] points above the car. NaN when
    /// there is nothing to frame. This is Android's `turnZoom`.
    static func turnZoom(groundM: Double, up: Double, height: Double,
                         tiltDeg: Double, latDeg: Double) -> Double {
        guard groundM > 0, up > 0, height > 0 else { return .nan }
        let groundPoints = groundAhead(up: up, tiltDeg: tiltDeg, height: height)
        guard groundPoints.isFinite, groundPoints > 0 else { return .nan }
        return log2(earthCircumferenceM * cos(latDeg * .pi / 180) * groundPoints
            / (worldPxAtZoomZero * groundM))
    }

    /// The turn zoom with the tilt the camera will actually hold at that zoom. Android bisects the
    /// same fixed point; twelve halvings leave less than 0.001 of a level.
    static func turnZoomFlattening(groundM: Double, up: Double, height: Double,
                                   wantedTilt: Double, latDeg: Double) -> Double {
        let atWanted = turnZoom(groundM: groundM, up: up, height: height,
                                tiltDeg: wantedTilt, latDeg: latDeg)
        if atWanted.isNaN || tiltAt(zoom: atWanted, wanted: wantedTilt) >= wantedTilt - 1e-9 {
            return atWanted
        }
        var low = turnZoom(groundM: groundM, up: up, height: height, tiltDeg: 0, latDeg: latDeg)
        var high = atWanted
        for _ in 0..<12 {
            let mid = (low + high) / 2
            let tilt = tiltAt(zoom: mid, wanted: wantedTilt)
            let candidate = turnZoom(groundM: groundM, up: up, height: height,
                                     tiltDeg: tilt, latDeg: latDeg)
            if candidate > mid { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    /// The drive zoom with turn framing on: never closer than the speed's zoom, never below the
    /// chosen floor.
    static func withTurn(speedZoom: Double, turnZoom: Double, floor: Double) -> Double {
        turnZoom.isNaN ? speedZoom : min(speedZoom, max(turnZoom, floor))
    }

    static func yawWeight(speedZoom: Double, turnZoom: Double) -> Double {
        guard !turnZoom.isNaN, !speedZoom.isNaN else { return 0 }
        return max(0, min((speedZoom - turnZoom) / turnYawBlendLevels, 1))
    }

    /// Degrees to turn off the road heading toward the framed maneuver, at most 90 either way.
    static func turnYaw(headingDeg: Double, toTurnDeg: Double,
                        speedZoom: Double, turnZoom: Double) -> Double {
        let weight = yawWeight(speedZoom: speedZoom, turnZoom: turnZoom)
        guard weight > 0 else { return 0 }
        let off = (toTurnDeg - headingDeg + 540).truncatingRemainder(dividingBy: 360) - 180
        return max(-turnYawMaxDeg, min(off, turnYawMaxDeg)) * weight
    }

    /// Forward bearing of the route segment nearest [coordinate], in route order. Nil when the
    /// drawn line has no usable segment.
    static func routeBearing(on line: [CLLocationCoordinate2D],
                             near coordinate: CLLocationCoordinate2D) -> Double? {
        guard line.count >= 2 else { return nil }
        var bestDistance = Double.greatestFiniteMagnitude
        var bestBearing: Double?
        for index in 0..<(line.count - 1) {
            let start = line[index]
            let end = line[index + 1]
            let dLat = coordinate.latitude - start.latitude
            let dLng = coordinate.longitude - start.longitude
            let distance = dLat * dLat + dLng * dLng
            if distance < bestDistance {
                bestDistance = distance
                bestBearing = bearing(from: start, to: end)
            }
        }
        return bestBearing
    }

    static func bearing(from start: CLLocationCoordinate2D,
                        to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLng = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }
}

/// The step preview's arithmetic: which stretch of the drawn line leads to a tapped maneuver.
/// Pure values so the camera and the highlight agree on the same point.
enum StepFocusGeometry {
    /// How much road before the maneuver is highlighted, and a short tail after it so the
    /// junction itself stays visible under the line's round cap.
    static let leadMeters = 220.0
    static let tailMeters = 40.0
    /// Android's step preview zoom (`VelaMapView`): close enough to read the junction, flat and
    /// north-up so the turn is not hidden by the drive camera's tilt.
    static let zoom = 16.5

    /// The nearest point index of [line] to [target].
    static func nearestIndex(on line: [CLLocationCoordinate2D],
                             to target: CLLocationCoordinate2D) -> Int? {
        guard !line.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, coordinate) in line.enumerated() {
            let dLat = coordinate.latitude - target.latitude
            let dLng = coordinate.longitude - target.longitude
            let distance = dLat * dLat + dLng * dLng
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// The part of [line] that leads to [target] and a short tail after it. Falls back to the
    /// whole line when the route is shorter than the highlight, and to two points when the tap's
    /// point is not on the drawn line at all.
    static func leadingSegment(on line: [CLLocationCoordinate2D],
                               near target: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        guard line.count >= 2, let center = nearestIndex(on: line, to: target) else {
            return line.count >= 2 ? line : []
        }
        var start = center
        var walked = 0.0
        while start > 0 && walked < leadMeters {
            walked += distance(line[start], line[start - 1])
            start -= 1
        }
        var end = center
        walked = 0
        while end < line.count - 1 && walked < tailMeters {
            walked += distance(line[end], line[end + 1])
            end += 1
        }
        let segment = Array(line[start...end])
        return segment.count >= 2 ? segment : []
    }

    private static func distance(_ a: CLLocationCoordinate2D,
                                 _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}

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
    /// After a short pan pause the drive may take the camera back without the driver tapping
    /// Re-center. The model checks pause and preview before it follows this.
    var onNavigationPanResume: (() -> Void)?
    /// Told when the overview opens or closes so the chrome can swap its button.
    var onNavigationOverviewChanged: ((Bool) -> Void)?

    private weak var mapView: MLNMapView?
    private var navigationCamera = false
    private var navigationFollowing = false
    private var navigationOverview = false
    /// The drawn navigation line in route order, used for the overview bounds and the road
    /// bearing under the car.
    private var navigationRouteCoordinates: [CLLocationCoordinate2D] = []
    private var lastNavigationFix: (coordinate: CLLocationCoordinate2D, speed: Double, heading: Double,
                                    distanceToNext: Double, maneuver: CLLocationCoordinate2D?)?
    private var panResumeWork: DispatchWorkItem?
    private var lastCameraFraction = 0.5
    private var lastCameraZoom = MapDefaults.initialZoom
    private var lastCameraTilt = 0.0
    private let overviewGesture = NavCameraGestureTarget()
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
    private var cameraObserver: NSObjectProtocol?
    /// RTE-STEP: the preview sheet's two map requests. The sheet is a plain SwiftUI view with no
    /// controller, so it posts instead of holding the map.
    private var stepFocusObserver: NSObjectProtocol?
    private var routeOverviewObserver: NSObjectProtocol?
    /// The short-lived step highlight, cancelled by the next tap or by leaving the preview.
    private var stepFocusWork: DispatchWorkItem?
    /// Set while the north lock puts the camera back, so its own region change is not corrected twice.
    private var correctingNorth = false
    /// The line sheet's whole-line request. It draws the feed's shape in the line's color, never a
    /// feed call of its own.
    private var transitLineObserver: NSObjectProtocol?
    /// The style the transit overlays were installed on, so one style load installs them once.
    private var transitStyle: ObjectIdentifier?
    /// TRIP-DIAG: the one-shot display link that records the first map frame.
    private var firstFrameProbe: FirstFrameProbe?

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
        // NAV-CAMERA: a settings change applies to the current drive at once.
        cameraObserver = NotificationCenter.default.addObserver(
            forName: NavCameraSettings.changedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyCameraSettings()
        }
        overviewGesture.action = { [weak self] in self?.toggleNavigationOverview() }
        // RTE-STEP: a tap in the steps list frames that maneuver; "Whole route" fits the line
        // again. Neither starts guidance.
        stepFocusObserver = NotificationCenter.default.addObserver(
            forName: RouteStepMapLink.focusRequest, object: nil, queue: .main
        ) { [weak self] note in
            guard let request = note.object as? RouteStepFocusRequest else { return }
            self?.focusRouteStep(request)
        }
        routeOverviewObserver = NotificationCenter.default.addObserver(
            forName: RouteStepMapLink.overviewRequest, object: nil, queue: .main
        ) { [weak self] note in
            guard let request = note.object as? RouteOverviewRequest else { return }
            self?.showRouteOverview(request.line)
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
        if let cameraObserver {
            NotificationCenter.default.removeObserver(cameraObserver)
        }
        if let stepFocusObserver {
            NotificationCenter.default.removeObserver(stepFocusObserver)
        }
        if let routeOverviewObserver {
            NotificationCenter.default.removeObserver(routeOverviewObserver)
        }
        panResumeWork?.cancel()
        stepFocusWork?.cancel()
        savedShapesTask?.cancel()
    }

    func attach(_ mapView: MLNMapView) {
        self.mapView = mapView
        // The chrome draws its own compass and scale bar, with the bearing and the real metres.
        mapView.compassView.isHidden = true
        mapView.scaleBar.isHidden = true
        // A turn that stops within 12 degrees of north goes back to north, as on Android.
        mapView.toleranceForSnappingToNorth = 12
        // A two-finger tap is the gesture for the whole remaining route, as on Android. The
        // overview button does the same thing for one finger.
        let overview = UITapGestureRecognizer(target: overviewGesture,
                                              action: #selector(NavCameraGestureTarget.fire))
        overview.numberOfTouchesRequired = 2
        mapView.addGestureRecognizer(overview)
        applyGestureSettings()
        // TRIP-DIAG: the performance overlay lives inside the map view as a zero-height subview,
        // and the first display commit records the first map frame. Both are inert unless the
        // debug or opt-in overlay is on.
        PerfMonitor.shared.attach(to: mapView)
        firstFrameProbe = FirstFrameProbe {
            DiagnosticsMeasurements.shared.mark(.firstMapFrame)
        }
        if activeOfflineArchive != nil {
            DiagnosticsMeasurements.shared.mark(.offlineRegionLoad)
        }
    }

    private func applyCameraSettings() {
        if navigationOverview {
            return
        }
        if navigationCamera {
            if let fix = lastNavigationFix, navigationFollowing {
                updateNavigation(coordinate: fix.coordinate, speedMps: fix.speed,
                                 heading: fix.heading, distanceToNext: fix.distanceToNext,
                                 maneuver: fix.maneuver)
            } else {
                applyNavigationInsets()
            }
        }
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
        navigationOverview = false
        isFollowingUser = true
        navigationUpdateCount = 0
        mapView.showsUserLocation = true
        _ = applyNavigationInsets()
        if mapView.zoomLevel < 16 {
            mapView.setZoomLevel(16.5, animated: LaunchOptions.current.animates)
        }
    }

    func setNavigationFollowing(_ on: Bool) {
        guard navigationCamera else { return }
        // The overview owns the camera until it closes; a state publish must not reattach it
        // underneath the fitted route.
        if on && navigationOverview { return }
        navigationFollowing = on
        isFollowingUser = on
    }

    func userPanned() {
        guard navigationCamera, !navigationOverview else { return }
        if navigationFollowing {
            navigationFollowing = false
            isFollowingUser = false
            onNavigationPan?()
        }
        schedulePanResume()
    }

    /// Five seconds after the last finger lifts, the model may take the camera back. The model
    /// still refuses while the drive is paused or a step is previewed.
    private func schedulePanResume() {
        panResumeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.navigationCamera, !self.navigationOverview,
                  !self.navigationFollowing else { return }
            self.onNavigationPanResume?()
        }
        panResumeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func updateNavigation(coordinate: CLLocationCoordinate2D, speedMps: Double,
                          heading: CLLocationDirection, distanceToNext: Double = 0,
                          maneuver: CLLocationCoordinate2D? = nil) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        lastNavigationFix = (coordinate, speedMps, heading, distanceToNext, maneuver)
        guard navigationCamera, navigationFollowing, !navigationOverview, let mapView else { return }
        let carY = applyNavigationInsets()
        let settings = NavCameraSettings.shared
        let speed = max(0, min(speedMps, NavCameraFraming.maxSpeedMps))
        var zoom = NavCameraFraming.speedZoom(speed)
        zoom = NavCameraFraming.proximityZoom(zoom, distanceM: distanceToNext)
        var tilt = settings.tilt ? NavCameraFraming.tiltAt(zoom: zoom) : 0
        var direction = MapGestureSettings.shared.keepNorthUp
            ? 0 : (NavCameraFraming.routeBearing(on: navigationRouteCoordinates, near: coordinate)
                   ?? heading)
        if settings.autoZoom, let maneuver, distanceToNext > 0 {
            let topChrome = navigationTopChrome(mapView)
            let up = carY - topChrome - CGFloat(NavCameraFraming.turnMarginPoints)
            let turn = NavCameraFraming.turnZoomFlattening(
                groundM: distanceToNext, up: Double(max(up, 20)),
                height: Double(max(mapView.bounds.height, 1)),
                wantedTilt: settings.tilt ? NavCameraFraming.wantedTiltDeg : 0,
                latDeg: coordinate.latitude)
            let framed = NavCameraFraming.withTurn(
                speedZoom: zoom, turnZoom: turn, floor: settings.floor)
            if framed < zoom {
                // A far turn may pull the camera out while the tilt is still shallow; recompute
                // the riding tilt from the final zoom so the horizon does not creep.
                tilt = settings.tilt ? NavCameraFraming.tiltAt(zoom: framed) : 0
                let yaw = NavCameraFraming.turnYaw(
                    headingDeg: direction,
                    toTurnDeg: NavCameraFraming.bearing(from: coordinate, to: maneuver),
                    speedZoom: zoom, turnZoom: turn)
                direction = (direction + yaw).truncatingRemainder(dividingBy: 360)
                if direction < 0 { direction += 360 }
                zoom = framed
            }
        }
        lastCameraZoom = zoom
        lastCameraTilt = tilt
        // Pitch first, on the camera the map holds, then the target. Reading `camera` after an
        // animated `setCenter` can still return the previous target, which would cancel the
        // animation and jump the map back a fix.
        let camera = mapView.camera
        camera.pitch = CGFloat(tilt)
        mapView.setCamera(camera, animated: false)
        mapView.setCenter(coordinate, zoomLevel: zoom, direction: direction,
                          animated: LaunchOptions.current.animates)
        navigationUpdateCount += 1
    }

    /// Content inset puts the car at the lower third (or the centre) of the map. The top inset
    /// minus the bottom one is the pad fraction times the height, so the visible viewport's centre
    /// lands on that row. Returns the car's screen row in points.
    @discardableResult
    private func applyNavigationInsets() -> CGFloat {
        guard let mapView else { return 0 }
        let height = max(mapView.bounds.height, 1)
        let pad = NavCameraSettings.shared.lowerThird
            ? NavCameraFraming.lowerThirdPad : NavCameraFraming.centerPad
        let bottom: CGFloat = 100
        let top = min(height * 0.75, bottom + CGFloat(pad) * height)
        let inset = UIEdgeInsets(top: top, left: 0, bottom: bottom, right: 0)
        if mapView.contentInset != inset {
            mapView.contentInset = inset
        }
        let carY = height * CGFloat(1 + pad) / 2
        lastCameraFraction = Double(carY / height)
        return carY
    }

    /// The banner's bottom edge on the map. The drive chrome starts under the safe area and the
    /// turn card is about 170 points tall at the default text size.
    private func navigationTopChrome(_ mapView: MLNMapView) -> CGFloat {
        max(mapView.safeAreaInsets.top + 170, 220)
    }

    /// Fits the whole drawn remaining route, flat and north-up. The driving camera stays stored,
    /// so closing the overview returns to the car rather than to the fitted camera.
    func showNavigationOverview() {
        guard navigationCamera, !navigationOverview, let mapView,
              navigationRouteCoordinates.count >= 2 else { return }
        navigationOverview = true
        navigationFollowing = false
        isFollowingUser = false
        panResumeWork?.cancel()
        mapView.contentInset = .zero
        let camera = mapView.camera
        camera.heading = 0
        camera.pitch = 0
        mapView.setCamera(camera, animated: false)
        var south = navigationRouteCoordinates[0].latitude
        var north = south
        var west = navigationRouteCoordinates[0].longitude
        var east = west
        for coordinate in navigationRouteCoordinates {
            south = min(south, coordinate.latitude)
            north = max(north, coordinate.latitude)
            west = min(west, coordinate.longitude)
            east = max(east, coordinate.longitude)
        }
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: south, longitude: west),
            ne: CLLocationCoordinate2D(latitude: north, longitude: east))
        let padding = UIEdgeInsets(
            top: navigateOverviewTop(mapView), left: 24,
            bottom: 140, right: 24)
        mapView.setVisibleCoordinateBounds(
            bounds, edgePadding: padding, animated: LaunchOptions.current.animates,
            completionHandler: nil)
        lastCameraTilt = 0
        onNavigationOverviewChanged?(true)
    }

    private func navigateOverviewTop(_ mapView: MLNMapView) -> CGFloat {
        max(mapView.safeAreaInsets.top + 120, 160)
    }

    /// Leaves the overview and takes the driving camera back without an intermediate camera: the
    /// same fix, road bearing and zoom the drive had before the fit.
    func endNavigationOverview() {
        guard navigationOverview else { return }
        navigationOverview = false
        onNavigationOverviewChanged?(false)
        guard navigationCamera else { return }
        navigationFollowing = true
        isFollowingUser = true
        if let fix = lastNavigationFix {
            updateNavigation(coordinate: fix.coordinate, speedMps: fix.speed,
                             heading: fix.heading, distanceToNext: fix.distanceToNext,
                             maneuver: fix.maneuver)
        } else {
            _ = applyNavigationInsets()
        }
    }

    func toggleNavigationOverview() {
        if navigationOverview {
            endNavigationOverview()
        } else {
            showNavigationOverview()
        }
    }

    func endNavigation() {
        guard let mapView else { return }
        navigationCamera = false
        navigationFollowing = false
        navigationOverview = false
        isFollowingUser = false
        panResumeWork?.cancel()
        navigationRouteCoordinates = []
        lastNavigationFix = nil
        mapView.contentInset = .zero
        let camera = mapView.camera
        camera.pitch = 0
        mapView.setCamera(camera, animated: false)
        mapView.setCenter(mapView.centerCoordinate, zoomLevel: mapView.zoomLevel, direction: 0,
                          animated: LaunchOptions.current.animates)
        onNavigationOverviewChanged?(false)
    }

    /// Camera values the UI scenarios read from the debug line.
    var cameraDebug: String {
        "carpad=\(Int((lastCameraFraction * 100).rounded()))"
            + " camzoom=\(String(format: "%.1f", lastCameraZoom))"
            + " camtilt=\(Int(lastCameraTilt.rounded()))"
            + " camoverview=\(navigationOverview ? 1 : 0)"
            + " camfollow=\(navigationFollowing ? 1 : 0)"
            + " camauto=\(NavCameraSettings.shared.autoZoom ? 1 : 0)"
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
            if navigationOverview {
                lastCameraZoom = mapView.zoomLevel
                lastCameraTilt = Double(mapView.camera.pitch)
            }
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
        DiagnosticsMeasurements.shared.mark(.firstFix)
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
        if activeOfflineArchive != nil {
            DiagnosticsMeasurements.shared.mark(.offlineRegionLoad)
        }
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

    /// RTE-STEP: frames one step's maneuver and lights the stretch leading to it. It never enters
    /// guidance; the drive camera, when one is active, takes the map back on its next fix.
    private func focusRouteStep(_ request: RouteStepFocusRequest) {
        guard let mapView, CLLocationCoordinate2DIsValid(request.target) else { return }
        mapView.userTrackingMode = .none
        isFollowingUser = false
        mapView.contentInset = .zero
        let camera = mapView.camera
        camera.pitch = 0
        mapView.setCamera(camera, animated: false)
        mapView.setCenter(request.target, zoomLevel: StepFocusGeometry.zoom, direction: 0,
                          animated: LaunchOptions.current.animates)
        showStepHighlight(request.target, line: request.line, on: mapView.style)
        NotificationCenter.default.post(
            name: RouteStepMapLink.focusApplied, object: nil,
            userInfo: [
                RouteStepMapLink.indexKey: request.index,
                RouteStepMapLink.zoomKey: StepFocusGeometry.zoom,
            ])
    }

    private func showStepHighlight(_ target: CLLocationCoordinate2D,
                                   line: [CLLocationCoordinate2D], on style: MLNStyle?) {
        let segment = StepFocusGeometry.leadingSegment(on: line, near: target)
        routes.setStepFocus(segment, on: style)
        stepFocusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.routes.setStepFocus([], on: self.mapView?.style)
        }
        stepFocusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// "Whole route" in the steps list: fits the planned line again, above the sheet, flat and
    /// north-up, and clears the step highlight.
    private func showRouteOverview(_ line: [CLLocationCoordinate2D]) {
        guard let mapView, line.count >= 2 else { return }
        stepFocusWork?.cancel()
        routes.setStepFocus([], on: mapView.style)
        mapView.userTrackingMode = .none
        isFollowingUser = false
        let camera = mapView.camera
        camera.pitch = 0
        mapView.setCamera(camera, animated: false)
        var sw = line[0]
        var ne = line[0]
        for coordinate in line {
            sw.latitude = min(sw.latitude, coordinate.latitude)
            sw.longitude = min(sw.longitude, coordinate.longitude)
            ne.latitude = max(ne.latitude, coordinate.latitude)
            ne.longitude = max(ne.longitude, coordinate.longitude)
        }
        let height = max(mapView.bounds.height, 1)
        let padding = UIEdgeInsets(
            top: max(mapView.safeAreaInsets.top + 100, 140), left: 24,
            bottom: max(height * 0.55, 260), right: 24)
        mapView.setVisibleCoordinateBounds(
            MLNCoordinateBounds(sw: sw, ne: ne), edgePadding: padding,
            animated: LaunchOptions.current.animates, completionHandler: nil)
    }

    /// Takes the routes off the map and puts the result pins back. The navigation group is
    /// cleared by its own lifecycle (`clearNavigationRoute`), so closing the route sheet cannot
    /// wipe a drive that just started.
    func clearRoutes() {
        guard let mapView else { return }
        stepFocusWork?.cancel()
        routes.setStepFocus([], on: mapView.style)
        routes.set([], selected: -1, on: mapView.style)
        let annotations = mapView.annotations ?? []
        let missing = resultPins.filter { pin in !annotations.contains { $0 === pin } }
        if !missing.isEmpty { mapView.addAnnotations(missing) }
    }

    /// The live drive's own route group: traveled and congestion pieces, road-ahead arrows and
    /// the lane row. It replaces the preview line while navigating and is cleared with it.
    func showNavigationRoute(_ draw: NavRouteDraw) {
        routes.setNavigation(draw, on: mapView?.style)
        // The pieces are in route order from the traveled cut to the destination, so their
        // concatenation is the remaining line the overview fits and the bearing under the car.
        navigationRouteCoordinates = draw.pieces.flatMap(\.coordinates)
    }

    /// Free driving and the end of a drive leave no navigation line behind.
    func clearNavigationRoute() {
        routes.setNavigation(nil, on: mapView?.style)
        navigationRouteCoordinates = []
    }

    /// A style tap, routed through the one registry. Annotations and the alternate route keep
    /// their existing precedence; every other drawn layer is decided by MapLibre's z-order.
    func handleTap(at point: CGPoint) {
        guard let mapView else { return }
        // While the whole route is shown, a tap is the way back to the drive, as on Android. It
        // never reaches the tap registry, so no POI card opens over the overview.
        if navigationOverview {
            endNavigationOverview()
            return
        }
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

/// A gesture recognizer target that needs no NSObject inheritance on `MapController`.
private final class NavCameraGestureTarget: NSObject {
    var action: (() -> Void)?

    @objc func fire() {
        action?()
    }
}
