import CoreLocation
import Foundation
import OSLog
import UIKit
import VelaCore

/// SwiftUI's mirror of the process-owned `NavStore`. A nil session is a deliberate no-op fallback
/// for the route sheet before navigation is wired into a host.
final class NavModel: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var navigating = false
    @Published private(set) var starting = false
    @Published private(set) var startFailed = false
    @Published private(set) var arrived = false
    @Published private(set) var paused = false
    @Published private(set) var offRoute = false
    @Published private(set) var starved = false
    @Published private(set) var maneuverKind = "STRAIGHT"
    @Published private(set) var maneuverText = ""
    @Published private(set) var nextManeuverText = ""
    @Published private(set) var streetName = ""
    @Published private(set) var distanceToNext = 0.0
    @Published private(set) var remainingDistance = 0.0
    @Published private(set) var remainingSeconds = 0.0
    @Published private(set) var speedMps: Double?
    @Published private(set) var speedLimitKmh: Double?
    @Published private(set) var speeding = false
    @Published private(set) var roadAlertKind: String?
    @Published private(set) var roadAlertCount = 0
    @Published private(set) var loadedCameraGroups = 0
    @Published private(set) var trafficDelaySeconds = 0.0
    @Published private(set) var fasterRouteOffered = false
    @Published private(set) var fasterSavingSeconds = 0.0
    @Published private(set) var imperial = false
    @Published private(set) var destinationName = ""
    @Published private(set) var destinationAddress = ""
    @Published private(set) var tripDistance = 0.0
    @Published private(set) var tripSeconds = 0.0
    @Published private(set) var cameraDetached = false
    @Published private(set) var northUp = false
    @Published private(set) var spokenCount = 0
    @Published private(set) var lastSpoken = ""
    @Published private(set) var voiceMuted = false
    @Published private(set) var activityActive = false
    @Published private(set) var activityEnabled = false
    @Published private(set) var activityRequests = 0
    @Published private(set) var activityUpdates = 0
    @Published private(set) var activityEnds = 0
    @Published private(set) var activityError = false

    private let session: MapSession?
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "Navigation")
    private let location: CoreLocationPipeline?
    private let voice: AppleNavVoice?
    private let activities: NavActivityController
    private var observing: Task<Void, Never>?
    private weak var map: MapController?
    private var shownRouteRevision: Int64 = -1
    private var shownFixSequence: Int64 = -1
    private var latitude: Double?
    private var longitude: Double?
    private var bearing: Double?
    private var deviceHeading: CLLocationDirection?

    init(
        session: MapSession?,
        location: CoreLocationPipeline? = nil,
        voice: AppleNavVoice? = nil,
        activities: NavActivityController? = nil
    ) {
        self.session = session
        self.location = location
        self.voice = voice
        self.activities = activities ?? NavActivityController()
    }

    func start() {
        guard observing == nil else { return }
        activities.start()
        syncActivityDebug()
        imperial = session?.settings?.imperial ?? (Locale.current.measurementSystem == .us)
        session?.nav.setImperial(on: imperial)
        session?.nav.alertText = { kind, count in
            let key: String
            switch kind {
            case "SPEED_CAMERA":
                key = "nav_speed_camera_ahead"
            case "ALPR_CAMERA":
                key = count.intValue > 1 ? "nav_flock_cameras_ahead" : "nav_flock_camera_ahead"
            default:
                key = "nav_speeding_alert"
            }
            return VelaL10n.text(key)
        }
        session?.nav.warningCue = { AppGraph.navHaptics.cameraWarning() }
        location?.onFix = { [weak self] fix, stamp in
            guard let self else { return }
            let accuracy = fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil
            let speed = fix.speed >= 0 ? fix.speed : nil
            let course = fix.course >= 0 ? fix.course : nil
            // Core Location does not expose the provider. Only a valid, accurate fix is allowed to
            // guide, which is the iOS equivalent of Android's GPS-only 50 m gate.
            let guidanceQuality = accuracy != nil && accuracy! <= 50
            self.session?.nav.onFix(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                accuracyM: accuracy ?? .nan,
                speedMps: speed ?? .nan,
                bearingDeg: course ?? .nan,
                elapsedNanos: stamp,
                gnss: guidanceQuality)
        }
        location?.onHeading = { [weak self] heading in
            guard let self else { return }
            self.deviceHeading = heading
            self.updateCamera()
        }
        voice?.onSpeech = { [weak self] count, text in
            self?.spokenCount = count
            self?.lastSpoken = text
        }
        location?.start()
        if let store = session?.nav {
            observing = Task { @MainActor [weak self] in
                for await state in store.state {
                    self?.apply(state)
                }
            }
        }
    }

    func attach(map: MapController) {
        self.map = map
        map.onNavigationPan = { [weak self] in
            self?.session?.nav.panned()
        }
        if active { map.beginNavigation() }
    }

    /// Hook used by the route sheet's Start button. It intentionally does nothing without a store.
    func startIfAvailable() {
        session?.nav.startNavigation()
    }

    func stop() {
        session?.nav.stop()
    }

    func recenter() {
        session?.nav.recenter()
        map?.setNavigationFollowing(true)
        updateCamera(force: true)
    }

    func toggleNorthUp() {
        session?.nav.toggleNorthUp()
    }

    func toggleVoice() {
        guard let voice else { return }
        let muted = !voiceMuted
        voiceMuted = muted
        voice.setMuted(muted)
    }

    func setImperial(_ on: Bool) {
        imperial = on
        session?.nav.setImperial(on: on)
    }

    func acceptFasterRoute() {
        session?.nav.acceptFasterRoute()
    }

    func dismissFasterRoute() {
        session?.nav.dismissFasterRoute()
    }

    var debugLine: String {
        "nav=\(navigating ? 1 : 0) active=\(active ? 1 : 0) starting=\(starting ? 1 : 0)"
            + " left=\(Int(remainingDistance)) eta=\(Int(remainingSeconds)) follow=\(map?.isFollowingUser == true ? 1 : 0)"
            + " camera=\(map?.navigationUpdateCount ?? 0) voice=\(spokenCount) idle=\(UIApplication.shared.isIdleTimerDisabled ? 1 : 0)"
            + " background=\(location?.backgroundUpdatesEnabled == true ? 1 : 0) offroute=\(offRoute ? 1 : 0)"
            + " activity=\(activityActive ? 1 : 0) actenabled=\(activityEnabled ? 1 : 0)"
            + " actrequests=\(activityRequests) actupdates=\(activityUpdates) actended=\(activityEnds)"
            + " acterror=\(activityError ? 1 : 0) limit=\(Int(speedLimitKmh ?? 0))"
            + " speeding=\(speeding ? 1 : 0) alertgroups=\(loadedCameraGroups)"
            + " offer=\(fasterRouteOffered ? 1 : 0) delay=\(Int(trafficDelaySeconds))"
    }

    var voiceDebugLine: String {
        lastSpoken.isEmpty ? "spoken=0" : "spoken=\(spokenCount) text=\(lastSpoken)"
    }

    var roadAlertText: String {
        switch roadAlertKind {
        case "SPEED_CAMERA":
            return VelaL10n.text("nav_speed_camera_ahead")
        case "ALPR_CAMERA":
            return VelaL10n.text(roadAlertCount > 1 ? "nav_flock_cameras_ahead" : "nav_flock_camera_ahead")
        default:
            return VelaL10n.text("nav_speeding_alert")
        }
    }

    private func apply(_ state: NavUiState) {
        let wasActive = active
        let revisionChanged = shownRouteRevision != state.routeRevision
        active = state.active
        navigating = state.navigating
        starting = state.starting
        startFailed = state.startFailed
        arrived = state.arrived
        paused = state.paused
        offRoute = state.offRoute
        starved = state.starved
        maneuverKind = state.maneuver?.type ?? "STRAIGHT"
        maneuverText = state.maneuver?.instruction ?? ""
        nextManeuverText = state.nextManeuver?.instruction ?? ""
        streetName = state.maneuver?.streetName ?? ""
        distanceToNext = state.maneuver?.distanceMeters ?? 0
        remainingDistance = state.remainingDistanceMeters
        remainingSeconds = state.remainingDurationSeconds
        speedMps = state.speedMps?.doubleValue
        speedLimitKmh = state.speedLimitKmh?.doubleValue
        speeding = state.speeding
        roadAlertKind = state.roadAlertKind
        roadAlertCount = Int(state.roadAlertCount)
        loadedCameraGroups = Int(state.loadedCameraGroups)
        trafficDelaySeconds = state.trafficDelaySeconds
        fasterRouteOffered = state.fasterRouteOffered
        fasterSavingSeconds = state.fasterSavingSeconds
        destinationName = state.destinationLabel
        destinationAddress = state.destinationAddress
        tripDistance = state.tripDistanceMeters
        tripSeconds = state.tripElapsedSeconds
        cameraDetached = state.cameraDetached
        northUp = state.northUp
        latitude = state.latitude?.doubleValue
        longitude = state.longitude?.doubleValue
        bearing = state.bearingDeg?.doubleValue
        activities.publish(state)
        syncActivityDebug()
        location?.setNavigating(state.navigating)
        UIApplication.shared.isIdleTimerDisabled = state.navigating

        if active && !wasActive {
            #if DEBUG
            log.debug("nav replay: start")
            #endif
            map?.beginNavigation()
        }
        if active && revisionChanged {
            showRoute(revision: state.routeRevision)
        }
        map?.setNavigationFollowing(!state.cameraDetached)
        if active {
            updateCamera(force: shownFixSequence != state.fixSequence)
            shownFixSequence = state.fixSequence
        } else if wasActive {
            #if DEBUG
            log.debug("nav replay: end")
            #endif
            map?.endNavigation()
            map?.clearRoutes()
            shownRouteRevision = -1
            shownFixSequence = -1
        }
    }

    private func syncActivityDebug() {
        activityActive = activities.hasActivity
        activityEnabled = activities.activitiesEnabled
        activityRequests = activities.requestCount
        activityUpdates = activities.updateCount
        activityEnds = activities.endCount
        activityError = activities.requestFailed
    }

    private func showRoute(revision: Int64) {
        guard let store = session?.nav else { return }
        let coordinates = Self.coordinates(store.line())
        guard !coordinates.isEmpty else { return }
        shownRouteRevision = revision
        map?.showRoutes([RouteLine(index: 0, coordinates: coordinates, traffic: [])],
                        selected: 0, fit: false, insets: .zero)
    }

    private func updateCamera(force: Bool = false) {
        guard active, let latitude, let longitude else { return }
        if !force && shownFixSequence >= 0 && deviceHeading == nil { return }
        let course: CLLocationDirection
        if northUp {
            course = 0
        } else {
            let movingBearing = (speedMps ?? 0) >= 0.5 ? bearing : deviceHeading
            course = movingBearing ?? deviceHeading ?? bearing ?? 0
        }
        map?.updateNavigation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            speedMps: speedMps ?? 0,
            heading: course)
    }

    private static func coordinates(_ flat: KotlinDoubleArray) -> [CLLocationCoordinate2D] {
        let count = Int(flat.size) / 2
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(count)
        for index in 0..<count {
            out.append(CLLocationCoordinate2D(
                latitude: flat.get(index: Int32(index * 2)),
                longitude: flat.get(index: Int32(index * 2 + 1))))
        }
        return out
    }
}
