import AVFoundation
import AudioToolbox
import CoreLocation
import Foundation
import OSLog
import UIKit
import VelaCore

/// One banner lane, copied out of the shared route so the view never touches Kotlin collections.
struct NavBannerLane: Equatable {
    let arrows: [String]
    let valid: Bool
}

/// The destination's closing warning as the banner shows it, copied out of the Kotlin warning so
/// the view formats plain integers.
struct NavClosingHint: Equatable {
    let name: String
    let closesAtMinuteOfDay: Int
    let arrivesAtMinuteOfDay: Int
    let beforeArrival: Bool

    var text: String {
        TravelHintText.closing(
            name: name,
            closesAtMinuteOfDay: closesAtMinuteOfDay,
            arrivesAtMinuteOfDay: arrivesAtMinuteOfDay,
            beforeArrival: beforeArrival)
    }
}

/// SwiftUI's mirror of the process-owned `NavStore`. A nil session is a deliberate no-op fallback
/// for the route sheet before navigation is wired into a host.
final class NavModel: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var navigating = false
    /// Free driving has no destination and no session; the drive chrome and the road lookup run.
    @Published private(set) var freeDriving = false
    /// The free-drive switch that strips the map to what a driver needs. Memory only per drive.
    @Published private(set) var simpleMap = false
    @Published private(set) var stopsRecalculating = false
    @Published private(set) var stopAdds = 0
    @Published private(set) var starting = false
    @Published private(set) var startFailed = false
    @Published private(set) var arrived = false
    @Published private(set) var paused = false
    @Published private(set) var offRoute = false
    @Published private(set) var starved = false
    @Published private(set) var deadReckoning = false
    @Published private(set) var inBackground = false
    @Published private(set) var interruptions = 0
    @Published private(set) var routeChanges = 0
    @Published private(set) var maneuverKind = "STRAIGHT"
    @Published private(set) var nextManeuverKind = "STRAIGHT"
    @Published private(set) var maneuverText = ""
    @Published private(set) var nextManeuverText = ""
    @Published private(set) var streetName = ""
    @Published private(set) var maneuverRef = ""
    @Published private(set) var nextManeuverRef = ""
    @Published private(set) var maneuverLanes: [NavBannerLane] = []
    @Published private(set) var currentRoadLabel = ""
    @Published private(set) var currentRoadRef = ""
    @Published private(set) var previewing = false
    @Published private(set) var previewDistance = 0.0
    @Published private(set) var previewKind = "STRAIGHT"
    @Published private(set) var previewText = ""
    @Published private(set) var previewRef = ""
    @Published private(set) var previewLanes: [NavBannerLane] = []
    @Published private(set) var previewIndex: Int?
    #if DEBUG
    /// Set only by NavBannerUITests through the debug fixture.
    @Published private(set) var bannerFixture = false
    #endif
    @Published private(set) var distanceToNext = 0.0
    @Published private(set) var remainingDistance = 0.0
    @Published private(set) var remainingSeconds = 0.0
    @Published private(set) var speedMps: Double?
    @Published private(set) var accuracyM: Double?
    @Published private(set) var speedLimitKmh: Double?
    @Published private(set) var speeding = false
    @Published private(set) var roadAlertKind: String?
    @Published private(set) var roadAlertCount = 0
    @Published private(set) var roadAlertAtMs: Int64 = 0
    @Published private(set) var loadedCameraGroups = 0
    @Published private(set) var trafficDelaySeconds = 0.0
    @Published private(set) var fasterRouteOffered = false
    @Published private(set) var fasterSavingSeconds = 0.0
    @Published private(set) var imperial = false
    @Published private(set) var destinationName = ""
    @Published private(set) var destinationAddress = ""
    /// The destination closes within an hour of the arrival, or before it; nil hides the line.
    @Published private(set) var closingHint: NavClosingHint?
    @Published private(set) var tripDistance = 0.0
    @Published private(set) var tripSeconds = 0.0
    @Published private(set) var travelMode = "DRIVE"
    @Published private(set) var nextStopLabel = ""
    @Published private(set) var nextStopDistance = 0.0
    @Published private(set) var nextStopSeconds = 0.0
    @Published private(set) var stopsAhead = 0
    @Published private(set) var reachedStopLabel: String?
    @Published private(set) var reachedStopSerial: Int64 = 0
    @Published private(set) var parkingOffer = false
    @Published private(set) var parkingSaved = false
    @Published private(set) var cameraDetached = false
    /// The whole remaining route is fitted instead of the drive camera (NAV-CAMERA).
    @Published private(set) var overview = false
    @Published private(set) var northUp = false
    @Published private(set) var spokenCount = 0
    @Published private(set) var lastSpoken = ""
    @Published private(set) var voiceMuted = false
    @Published private(set) var voiceAlertsOnly = false
    @Published private(set) var bridgeAlerts = true
    @Published private(set) var stepIndex = 0
    @Published private(set) var navSegments = 0
    @Published private(set) var navCongestion = false
    @Published private(set) var navRoadAhead = 0
    @Published private(set) var navLaneGlyphs = 0
    @Published private(set) var sessionStarts = 0
    @Published private(set) var resuming = false
    @Published private(set) var resumeFailed = false
    @Published private(set) var resumedFromRecord = false
    @Published private(set) var loadedBridges = 0
    @Published private(set) var activityActive = false
    @Published private(set) var activityEnabled = false
    @Published private(set) var activityRequests = 0
    @Published private(set) var activityUpdates = 0
    @Published private(set) var activityEnds = 0
    @Published private(set) var activityError = false

    private let session: MapSession?
    private let log = Logger(subsystem: OSLogLog.subsystem, category: "Navigation")
    private let location: CoreLocationPipeline?
    private let voice: VelaNavVoice?
    private let activities: NavActivityController
    private let notifications: NavNotificationController
    private var observing: Task<Void, Never>?
    private var systemObservers: [NSObjectProtocol] = []
    private weak var map: MapController?
    private var shownRouteRevision: Int64 = -1
    private var shownFixSequence: Int64 = -1
    private var shownPreviewIndex: Int?
    private var navRenderKey = ""
    private var latitude: Double?
    private var longitude: Double?
    private var bearing: Double?
    private var deviceHeading: CLLocationDirection?
    /// The next maneuver's point, passed to the drive camera for the turn framing.
    private var maneuverLatitude: Double?
    private var maneuverLongitude: Double?
    /// The step the overview must watch: the next maneuver returns to the drive camera.
    private var overviewStepIndex = -1

    init(
        session: MapSession?,
        location: CoreLocationPipeline? = nil,
        voice: VelaNavVoice? = nil,
        activities: NavActivityController? = nil,
        notifications: NavNotificationController? = nil
    ) {
        self.session = session
        self.location = location
        self.voice = voice
        self.activities = activities ?? NavActivityController()
        self.notifications = notifications ?? NavNotificationController.shared
    }

    deinit {
        for observer in systemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard observing == nil else { return }
        // The Kotlin session is built before this view model, so the stores, the voice keys and a
        // persisted drive are attached here, before the first fix can reach guidance.
        session?.nav.attachPreferences(stores: UserDefaultsKeyValueStores(prefix: "app.vela.ios."))
        // Free driving reads the road around the fix from OSM Overpass. The same HTTP seam as
        // the rest of the app, so the Debug fixture can answer it deterministically.
        session?.nav.attachFreeDriveHttp(http: URLSessionVelaHttp())
        activities.start()
        syncActivityDebug()
        notifications.start()
        notifications.onOpen = { [weak self] in self?.notificationOpened() }
        imperial = session?.settings?.imperial ?? (Locale.current.measurementSystem == .us)
        session?.nav.setImperial(on: imperial)
        // The shared label builder owns "Road numbers first". iOS has no settings row for it yet,
        // so an existing preference is honored and the default stays off.
        if UserDefaults.standard.object(forKey: "road_numbers") != nil {
            session?.nav.setRoadNumbersFirst(on: UserDefaults.standard.bool(forKey: "road_numbers"))
        }
        session?.nav.alertText = { kind, count, atMs in
            let key: String
            switch kind {
            case "SPEED_CAMERA":
                key = "nav_speed_camera_ahead"
            case "ALPR_CAMERA":
                key = count.intValue > 1 ? "nav_flock_cameras_ahead" : "nav_flock_camera_ahead"
            case "BRIDGE_OPEN":
                return VelaL10n.text("nav_bridge_open_ahead")
            case "BRIDGE_PLANNED":
                return VelaL10n.text("nav_bridge_opening_ahead", Self.clockText(Int64(atMs)))
            default:
                key = "nav_speeding_alert"
            }
            return VelaL10n.text(key)
        }
        session?.nav.warningCue = { AppGraph.navHaptics.cameraWarning() }
        session?.nav.alertChime = { AudioServicesPlaySystemSound(1057) }
        observeSystemEvents()
        location?.onFix = { [weak self] fix, stamp in
            guard let self else { return }
            let accuracy = fix.horizontalAccuracy >= 0 ? fix.horizontalAccuracy : nil
            let speed = fix.speed >= 0 ? fix.speed : nil
            let course = fix.course >= 0 ? fix.course : nil
            // Core Location names no provider, so every update is a positioning fix. The Kotlin
            // pipeline applies Android's 50 m guidance gate: a coarse fix can move the dot but
            // never steers the session or clears the no-GPS state.
            self.session?.nav.onFix(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                accuracyM: accuracy ?? .nan,
                speedMps: speed ?? .nan,
                bearingDeg: course ?? .nan,
                elapsedNanos: stamp,
                gnss: true)
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
        // A pan pauses the follow for five seconds only. The model refuses the takeover while
        // the drive is paused or a step is previewed, and Re-center always wins.
        map.onNavigationPanResume = { [weak self] in
            guard let self, self.active || self.freeDriving,
                  !self.previewing, !self.paused else { return }
            self.session?.nav.recenter()
            self.map?.setNavigationFollowing(true)
            self.updateCamera(force: true)
        }
        map.onNavigationOverviewChanged = { [weak self] on in
            self?.overview = on
            self?.overviewStepIndex = on ? (self?.stepIndex ?? -1) : -1
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

    /// Free driving: the drive chrome without a destination. No session, no Live Activity and
    /// no resume record, as Android's driving mode.
    func startFreeDrive() {
        simpleMap = false
        session?.nav.startFreeDrive()
    }

    func stopFreeDrive() {
        simpleMap = false
        session?.nav.stopFreeDrive()
    }

    /// The map's drive switch: POIs, transit and the browse overlays leave, the cameras stay.
    func toggleSimpleMap() {
        guard freeDriving else { return }
        simpleMap.toggle()
    }

    /// Adds a stop at the end of the live drive's plan; the shared session replans and the ETA
    /// refreshes from the new route.
    func addStop(name: String, latitude: Double, longitude: Double) {
        session?.nav.addStop(name: name, latitude: latitude, longitude: longitude)
    }

    /// DRIVE-SEARCH: the live polyline as flat lat,lng pairs, so the drive's short result list
    /// can rank by detour without touching the shared route store.
    var routeFlat: [Double] {
        guard let line = session?.nav.line() else { return [] }
        var values: [Double] = []
        values.reserveCapacity(Int(line.size))
        for index in 0..<Int(line.size) {
            values.append(line.get(index: Int32(index)))
        }
        return values
    }

    /// How far the car has already travelled on the live line, zero outside a drive.
    var traveledMeters: Double {
        session?.nav.traveledMeters() ?? 0
    }

    /// The car's last fix, for the distance line of a drive search result.
    var currentCoordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    func togglePause() {
        session?.nav.setPaused(on: !paused)
    }

    /// Debug-only hooks for NavRobustnessUITests: the simulator keeps delivering fixes while the
    /// app ignores them, which is what a tunnel or a dead receiver looks like to guidance.
    func simulateGpsLoss() {
        location?.setFixDeliveryEnabled(false)
    }

    func restoreGps() {
        location?.setFixDeliveryEnabled(true)
    }

    func recenter() {
        map?.endNavigationOverview()
        session?.nav.recenter()
        map?.setNavigationFollowing(true)
        updateCamera(force: true)
    }

    /// One button shows the whole remaining route and returns on the next tap, the next maneuver,
    /// or a map tap (handled by the controller).
    func toggleOverview() {
        map?.toggleNavigationOverview()
    }

    func toggleNorthUp() {
        session?.nav.toggleNorthUp()
    }

    /// The speaker button cycles On, Alerts only, Off, as Android's three-way choice does. The
    /// shared store persists `spoken_directions` and `spoken_alerts_only`; this view only mirrors.
    func toggleVoice() {
        session?.nav.cycleVoiceMode()
    }

    /// A notification tap. The app is already in the foreground when this runs; the drive stays
    /// the same and the camera goes back to following the car.
    func notificationOpened() {
        guard active else { return }
        map?.setNavigationFollowing(true)
        session?.nav.recenter()
        updateCamera(force: true)
    }

    #if DEBUG
    /// NavAlertsUITests exercises the bridge without touching the system notification banner.
    func simulateNotificationTap() {
        notifications.simulateTap()
    }
    #endif

    func setImperial(_ on: Bool) {
        imperial = on
        session?.nav.setImperial(on: on)
    }

    /// The banner's left swipe: the next step, grayed, with the camera moved there. It does not
    /// touch guidance, voice or the route; tapping the card restores the live one.
    func previewNext() {
        guard previewing || navigating else { return }
        session?.nav.preview(stepOffset: 1)
        AppGraph.navHaptics.bannerPreview()
    }

    func previewPrevious() {
        guard previewing || navigating else { return }
        session?.nav.preview(stepOffset: -1)
        AppGraph.navHaptics.bannerPreview()
    }

    func exitPreview() {
        guard previewing else { return }
        session?.nav.exitPreview()
        AppGraph.navHaptics.bannerRestore()
        map?.setNavigationFollowing(!cameraDetached && !paused)
        updateCamera(force: true)
    }

    func acceptFasterRoute() {
        session?.nav.acceptFasterRoute()
    }

    func dismissFasterRoute() {
        session?.nav.dismissFasterRoute()
    }

    /// Saves the spot the car arrived at as the parked car, the arrival card's one tap. The map's
    /// own parking button writes the same `ParkingStore`; no second store and no invented position.
    @discardableResult
    func saveParkingHere() -> Bool {
        guard parkingOffer, let latitude, let longitude else { return false }
        session?.saved.saveParking(at: LatLng(lat: latitude, lng: longitude))
        parkingSaved = true
        return true
    }

    var debugLine: String {
        "nav=\(navigating ? 1 : 0) active=\(active ? 1 : 0) starting=\(starting ? 1 : 0)"
            + " free=\(freeDriving ? 1 : 0) simple=\(simpleMap ? 1 : 0) recalc=\(stopsRecalculating ? 1 : 0)"
            + " stopadds=\(stopAdds) arrived=\(arrived ? 1 : 0)"
            + " left=\(Int(remainingDistance)) eta=\(Int(remainingSeconds)) follow=\(map?.isFollowingUser == true ? 1 : 0)"
            + " camera=\(map?.navigationUpdateCount ?? 0) voice=\(spokenCount) idle=\(UIApplication.shared.isIdleTimerDisabled ? 1 : 0)"
            + " background=\(location?.backgroundUpdatesEnabled == true ? 1 : 0) offroute=\(offRoute ? 1 : 0)"
            + " activity=\(activityActive ? 1 : 0) actenabled=\(activityEnabled ? 1 : 0)"
            + " actrequests=\(activityRequests) actupdates=\(activityUpdates) actended=\(activityEnds)"
            + " acterror=\(activityError ? 1 : 0) limit=\(Int(speedLimitKmh ?? 0))"
            + " speeding=\(speeding ? 1 : 0) alertgroups=\(loadedCameraGroups)"
            + " offer=\(fasterRouteOffered ? 1 : 0) delay=\(Int(trafficDelaySeconds))"
            + " paused=\(paused ? 1 : 0) starved=\(starved ? 1 : 0) reckoning=\(deadReckoning ? 1 : 0)"
            + " bg=\(inBackground ? 1 : 0) interruptions=\(interruptions) routechanges=\(routeChanges)"
            + " accuracy=\(Int(accuracyM ?? -1)) suppressed=\(location?.suppressedFixes ?? 0)"
            + " stops=\(stopsAhead) nextstop=\(nextStopLabel.isEmpty ? 0 : 1) reached=\(Int(reachedStopSerial))"
            + " closing=\(closingHint == nil ? 0 : 1)"
            + " parked=\(parkingSaved ? 1 : 0) lanes=\(maneuverLanes.count) ref=\(maneuverRef.isEmpty ? "-" : maneuverRef)"
            + " currentref=\(currentRoadRef.isEmpty ? "-" : currentRoadRef) preview=\(previewIndex ?? -1)"
            + " voicemode=\(voiceMuted ? (voiceAlertsOnly ? "alerts" : "off") : "on")"
            + " step=\(stepIndex) sessions=\(sessionStarts) bridges=\(loadedBridges)"
            + " navsegments=\(navSegments) navcongestion=\(navCongestion ? 1 : 0)"
            + " navahead=\(navRoadAhead) navlanes=\(navLaneGlyphs)"
            + " instr=\(maneuverText.isEmpty ? 0 : 1)"
            + " resuming=\(resuming ? 1 : 0) resumefailed=\(resumeFailed ? 1 : 0) resumed=\(resumedFromRecord ? 1 : 0)"
            + " notifreq=\(notifications.requested) notifpost=\(notifications.posted)"
            + " notifopen=\(notifications.opens) notifauth=\(notifications.authorization)"
            + " notiferr=\(notifications.failed ? 1 : 0)"
            + " \(map?.cameraDebug ?? "carpad=0 camzoom=0 camtilt=0 camoverview=0 camfollow=0 camauto=0")"
            + " camdetached=\(cameraDetached ? 1 : 0)"
    }

    var voiceDebugLine: String {
        let spoken = lastSpoken.isEmpty ? "spoken=0" : "spoken=\(spokenCount) text=\(lastSpoken)"
        return "\(spoken) \(voice?.engineDebug ?? "engine=none")"
    }

    var roadAlertText: String {
        switch roadAlertKind {
        case "SPEED_CAMERA":
            return VelaL10n.text("nav_speed_camera_ahead")
        case "ALPR_CAMERA":
            return VelaL10n.text(roadAlertCount > 1 ? "nav_flock_cameras_ahead" : "nav_flock_camera_ahead")
        case "BRIDGE_OPEN":
            return VelaL10n.text("nav_bridge_open_ahead")
        case "BRIDGE_PLANNED":
            return VelaL10n.text("nav_bridge_opening_ahead", Self.clockText(roadAlertAtMs))
        default:
            return VelaL10n.text("nav_speeding_alert")
        }
    }

    /// The permission question belongs to a drive, not the map at launch. The deterministic UI
    /// harness never sees a system alert unless the notification scenario opts in.
    private func requestNotificationPermissionIfNeeded() {
        #if DEBUG
        if LaunchOptions.current.deterministic && !NavTestSupport.notifications { return }
        #endif
        notifications.requestIfNeeded()
    }

    private func apply(_ state: NavUiState) {
        let wasActive = active
        let wasPaused = paused
        let wasFreeDriving = freeDriving
        let previousStep = stepIndex
        let revisionChanged = shownRouteRevision != state.routeRevision
        active = state.active
        navigating = state.navigating
        freeDriving = state.freeDriving
        stopsRecalculating = state.stopsRecalculating
        stopAdds = Int(state.stopAdds)
        starting = state.starting
        startFailed = state.startFailed
        arrived = state.arrived
        paused = state.paused
        offRoute = state.offRoute
        starved = state.starved
        deadReckoning = state.deadReckoning
        maneuverKind = state.maneuver?.type ?? "STRAIGHT"
        nextManeuverKind = state.nextManeuver?.type ?? "STRAIGHT"
        maneuverText = state.maneuver?.instruction ?? ""
        nextManeuverText = state.nextManeuver?.instruction ?? ""
        streetName = state.maneuver?.streetName ?? ""
        maneuverRef = state.maneuver?.ref ?? ""
        nextManeuverRef = state.nextManeuver?.ref ?? ""
        maneuverLanes = Self.lanes(state.maneuver?.lanes ?? [])
        currentRoadLabel = state.currentRoadLabel
        currentRoadRef = state.currentRoadRef
        previewIndex = state.previewIndex?.intValue
        previewing = previewIndex != nil
        previewDistance = state.previewManeuver?.distanceMeters ?? 0
        previewKind = state.previewManeuver?.type ?? "STRAIGHT"
        previewText = state.previewManeuver?.instruction ?? ""
        previewRef = state.previewManeuver?.ref ?? ""
        previewLanes = Self.lanes(state.previewManeuver?.lanes ?? [])
        distanceToNext = state.maneuver?.distanceMeters ?? 0
        remainingDistance = state.remainingDistanceMeters
        remainingSeconds = state.remainingDurationSeconds
        speedMps = state.speedMps?.doubleValue
        accuracyM = state.accuracyM?.doubleValue
        speedLimitKmh = state.speedLimitKmh?.doubleValue
        speeding = state.speeding
        roadAlertKind = state.roadAlertKind
        roadAlertCount = Int(state.roadAlertCount)
        roadAlertAtMs = state.roadAlertAtMs
        loadedCameraGroups = Int(state.loadedCameraGroups)
        trafficDelaySeconds = state.trafficDelaySeconds
        fasterRouteOffered = state.fasterRouteOffered
        fasterSavingSeconds = state.fasterSavingSeconds
        destinationName = state.destinationLabel
        destinationAddress = state.destinationAddress
        if let warning = state.closingWarning {
            closingHint = NavClosingHint(
                name: warning.name,
                closesAtMinuteOfDay: Int(warning.closesAtMinuteOfDay),
                arrivesAtMinuteOfDay: Int(warning.arrivesAtMinuteOfDay),
                beforeArrival: warning.beforeArrival)
        } else {
            closingHint = nil
        }
        tripDistance = state.tripDistanceMeters
        tripSeconds = state.tripElapsedSeconds
        travelMode = state.travelMode
        nextStopLabel = state.nextStopLabel
        nextStopDistance = state.nextStopDistanceMeters
        nextStopSeconds = state.nextStopSeconds
        stopsAhead = Int(state.stopsAhead)
        reachedStopLabel = state.reachedStopLabel
        reachedStopSerial = state.reachedStopSerial
        parkingOffer = state.parkingOffer
        cameraDetached = state.cameraDetached
        northUp = state.northUp
        voiceMuted = state.voiceMuted
        voiceAlertsOnly = state.voiceAlertsOnly
        bridgeAlerts = state.bridgeAlerts
        stepIndex = Int(state.stepIndex)
        maneuverLatitude = state.maneuver?.latitude
        maneuverLongitude = state.maneuver?.longitude
        // The overview ends when the car reaches the next maneuver, so the driver never reads the
        // fitted route while the banner counts a new turn.
        if overview && previousStep != stepIndex {
            map?.endNavigationOverview()
        }
        sessionStarts = Int(state.sessionStarts)
        resuming = state.resuming
        resumeFailed = state.resumeFailed
        resumedFromRecord = state.resumedFromRecord
        loadedBridges = Int(state.loadedBridges)
        if voice?.isMuted != state.voiceMuted {
            voice?.setMuted(state.voiceMuted)
        }
        latitude = state.latitude?.doubleValue
        longitude = state.longitude?.doubleValue
        bearing = state.bearingDeg?.doubleValue
        // Swiping the banner moves the map to the previewed step and stops the chase camera;
        // restoring the live card re-attaches it. Same route, same session.
        if let preview = state.previewManeuver, let index = previewIndex {
            if shownPreviewIndex != index {
                shownPreviewIndex = index
                map?.setNavigationFollowing(false)
                map?.focus(latitude: preview.latitude, longitude: preview.longitude)
            }
        } else if shownPreviewIndex != nil {
            shownPreviewIndex = nil
            map?.setNavigationFollowing(!state.cameraDetached && !state.paused)
            updateCamera(force: true)
        }
        #if DEBUG
        NavBannerTestSupport.applyIfNeeded(to: self)
        #endif
        activities.publish(state)
        syncActivityDebug()
        location?.setNavigating(state.navigating)
        UIApplication.shared.isIdleTimerDisabled = (state.navigating && !state.paused) || state.freeDriving

        if active && !wasActive {
            #if DEBUG
            log.debug("nav replay: start")
            #endif
            parkingSaved = false
            map?.beginNavigation()
            requestNotificationPermissionIfNeeded()
        }
        // Free driving shares the drive camera and the same replay line, so the simulator's
        // fixture drive starts moving for the free-drive scenarios too. It never posts the
        // background notification: there is no destination or ETA to name.
        if state.freeDriving && !wasFreeDriving {
            #if DEBUG
            log.debug("nav replay: start")
            #endif
            map?.clearNavigationRoute()
            navRenderKey = ""
            map?.beginNavigation()
        }
        if active && revisionChanged {
            shownRouteRevision = state.routeRevision
        }
        if active {
            updateNavigationRoute(force: revisionChanged)
        } else if wasActive {
            map?.clearNavigationRoute()
            navRenderKey = ""
            navSegments = 0
            navCongestion = false
            navRoadAhead = 0
            navLaneGlyphs = 0
        }
        // Pause holds the camera where it is; Resume re-attaches it unless the driver had panned.
        // A previewed step keeps the camera on that step until the card is tapped. Free driving
        // has no pause, so only a pan detaches its camera.
        map?.setNavigationFollowing(
            !previewing && !state.cameraDetached && (!state.paused || state.freeDriving))
        if active || state.freeDriving {
            if (!previewing && (!state.paused || state.freeDriving)) {
                updateCamera(force: (wasPaused && !state.paused) || shownFixSequence != state.fixSequence)
                shownFixSequence = state.fixSequence
            }
        } else if wasActive {
            #if DEBUG
            log.debug("nav replay: end")
            #endif
            notifications.cancel()
            map?.endNavigation()
            map?.clearRoutes()
            shownRouteRevision = -1
            shownFixSequence = -1
        }
        if !state.freeDriving && wasFreeDriving {
            #if DEBUG
            log.debug("nav replay: end")
            #endif
            notifications.cancel()
            map?.endNavigation()
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

    /// Background, foreground, calls and Bluetooth never end guidance. They may cut the prompt in
    /// flight or re-arm the audio session, and coming back re-attaches a following camera. The
    /// route, the session and the single Live Activity stay untouched.
    private func observeSystemEvents() {
        guard systemObservers.isEmpty else { return }
        let center = NotificationCenter.default
        systemObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.inBackground = true
            if self.navigating && !self.arrived {
                self.notifications.notifyGuidance(
                    destination: self.destinationName,
                    remainingSeconds: self.remainingSeconds,
                    step: self.maneuverText,
                    paused: self.paused)
            }
            self.applyLifecycle(.background)
        })
        systemObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.inBackground = false
            self.notifications.cancel()
            UIApplication.shared.isIdleTimerDisabled = self.navigating && !self.paused
            self.applyLifecycle(.foreground)
            // Free driving survives a background trip the same way: the camera re-attaches and
            // no persisted guided drive is started underneath it.
            if self.freeDriving {
                self.map?.setNavigationFollowing(true)
                self.updateCamera(force: true)
            }
            // A resume that could not plan at launch (no fix yet) gets the next foreground.
            if !self.active && !self.freeDriving {
                self.session?.nav.resumeNavigation()
            }
        })
        systemObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            let raw = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) ?? 0
            guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began:
                self.interruptions += 1
                self.applyLifecycle(.audioInterruptionBegan)
            case .ended:
                self.applyLifecycle(.audioInterruptionEnded)
            @unknown default:
                break
            }
        })
        systemObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if self.navigating { self.routeChanges += 1 }
            let raw = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            if let reason = AVAudioSession.RouteChangeReason(rawValue: raw), reason == .oldDeviceUnavailable {
                self.applyLifecycle(.audioRouteChanged)
            }
        })
    }

    private func applyLifecycle(_ event: NavLifecyclePolicy.Event) {
        let action = NavLifecyclePolicy.action(
            event, navigating: navigating, paused: paused, cameraDetached: cameraDetached)
        switch action {
        case .none:
            break
        case .cutSpeech:
            voice?.stop()
        case .rearmAudio:
            voice?.rearm()
        case .followCamera:
            map?.setNavigationFollowing(true)
            updateCamera(force: true)
        }
    }

    private func updateNavigationRoute(force: Bool) {
        guard active, let store = session?.nav, let frame = store.renderFrame() else { return }
        var draw = Self.draw(from: frame)
        #if DEBUG
        if NavRenderTestSupport.enabled {
            draw = NavRenderTestSupport.apply(
                to: draw, traveledM: frame.traveledM, kind: maneuverKind,
                nextKind: nextManeuverKind, lanes: maneuverLanes)
        }
        #endif
        // The gray cut moves every fix; the geometry is only re-uploaded when it moved enough to
        // show, so a drive does not re-tessellate the route several times a second.
        let key = "\(shownRouteRevision)|\(Int(frame.traveledM / 8))|\(stepIndex)"
            + "|\(previewIndex ?? -1)|\(Int(distanceToNext / 50))"
            + "|\(draw.pieces.count)|\(draw.arrows.count)|\(draw.lanes.count)"
        guard force || key != navRenderKey else { return }
        navRenderKey = key
        navSegments = draw.pieces.count
        navCongestion = draw.pieces.contains { $0.level >= 1 }
        navRoadAhead = draw.arrows.count
        navLaneGlyphs = draw.lanes.count
        map?.showNavigationRoute(draw)
    }

    private static func draw(from frame: NavRenderFrame) -> NavRouteDraw {
        var draw = NavRouteDraw.empty
        draw.pieces = frame.pieces.map { piece in
            let flat = piece.points
            let count = Int(flat.size) / 2
            var coordinates: [CLLocationCoordinate2D] = []
            coordinates.reserveCapacity(count)
            for index in 0..<count {
                coordinates.append(CLLocationCoordinate2D(
                    latitude: flat.get(index: Int32(index * 2)),
                    longitude: flat.get(index: Int32(index * 2 + 1))))
            }
            return NavRoutePiece(level: Int(piece.level), coordinates: coordinates)
        }
        draw.arrows = frame.arrows.map { arrow in
            NavRouteArrow(
                role: arrow.role, kind: arrow.kind,
                coordinate: CLLocationCoordinate2D(
                    latitude: arrow.latitude, longitude: arrow.longitude),
                rotation: arrow.rotation)
        }
        draw.lanes = frame.lanes.map { lane in
            NavRouteLane(
                indications: lane.indications, valid: lane.valid,
                coordinate: CLLocationCoordinate2D(
                    latitude: lane.latitude, longitude: lane.longitude),
                rotation: lane.rotation)
        }
        return draw
    }

    private func updateCamera(force: Bool = false) {
        guard active || freeDriving, let latitude, let longitude else { return }
        if !force && shownFixSequence >= 0 && deviceHeading == nil { return }
        let course: CLLocationDirection
        if northUp {
            course = 0
        } else {
            let movingBearing = (speedMps ?? 0) >= 0.5 ? bearing : deviceHeading
            course = movingBearing ?? deviceHeading ?? bearing ?? 0
        }
        let maneuver = maneuverLatitude.flatMap { lat in
            maneuverLongitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) }
        }
        map?.updateNavigation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            speedMps: speedMps ?? 0,
            heading: course,
            distanceToNext: distanceToNext,
            maneuver: maneuver)
    }

    private static func lanes(_ rows: [NavLane]) -> [NavBannerLane] {
        rows.map { NavBannerLane(arrows: $0.indications, valid: $0.valid) }
    }

    /// A bridge's planned opening, at the app's 12 or 24 hour choice.
    private static func clockText(_ epochMs: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = AppGraph.uses24HourClock() ? "HH:mm" : "h:mm a"
        return formatter.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1000.0))
    }

    #if DEBUG
    /// Debug-only banner data for NavBannerUITests: live routes do not guarantee lanes or a
    /// shield on the fixture drive, and the test must render both. Never reachable in release.
    func applyBannerFixture(
        ref: String,
        nextRef: String,
        currentLabel: String,
        currentRef: String,
        lanes: [NavBannerLane]
    ) {
        maneuverRef = ref
        nextManeuverRef = nextRef
        currentRoadLabel = currentLabel
        currentRoadRef = currentRef
        maneuverLanes = lanes
        bannerFixture = true
    }
    #endif
}
