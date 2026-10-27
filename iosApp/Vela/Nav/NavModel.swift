import AVFoundation
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
    @Published private(set) var deadReckoning = false
    @Published private(set) var inBackground = false
    @Published private(set) var interruptions = 0
    @Published private(set) var routeChanges = 0
    @Published private(set) var maneuverKind = "STRAIGHT"
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
    @Published private(set) var loadedCameraGroups = 0
    @Published private(set) var trafficDelaySeconds = 0.0
    @Published private(set) var fasterRouteOffered = false
    @Published private(set) var fasterSavingSeconds = 0.0
    @Published private(set) var imperial = false
    @Published private(set) var destinationName = ""
    @Published private(set) var destinationAddress = ""
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
    private let voice: VelaNavVoice?
    private let activities: NavActivityController
    private var observing: Task<Void, Never>?
    private var systemObservers: [NSObjectProtocol] = []
    private weak var map: MapController?
    private var shownRouteRevision: Int64 = -1
    private var shownFixSequence: Int64 = -1
    private var shownPreviewIndex: Int?
    private var latitude: Double?
    private var longitude: Double?
    private var bearing: Double?
    private var deviceHeading: CLLocationDirection?

    init(
        session: MapSession?,
        location: CoreLocationPipeline? = nil,
        voice: VelaNavVoice? = nil,
        activities: NavActivityController? = nil
    ) {
        self.session = session
        self.location = location
        self.voice = voice
        self.activities = activities ?? NavActivityController()
    }

    deinit {
        for observer in systemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start() {
        guard observing == nil else { return }
        activities.start()
        syncActivityDebug()
        imperial = session?.settings?.imperial ?? (Locale.current.measurementSystem == .us)
        session?.nav.setImperial(on: imperial)
        // The shared label builder owns "Road numbers first". iOS has no settings row for it yet,
        // so an existing preference is honored and the default stays off.
        if UserDefaults.standard.object(forKey: "road_numbers") != nil {
            session?.nav.setRoadNumbersFirst(on: UserDefaults.standard.bool(forKey: "road_numbers"))
        }
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
        if active { map.beginNavigation() }
    }

    /// Hook used by the route sheet's Start button. It intentionally does nothing without a store.
    func startIfAvailable() {
        session?.nav.startNavigation()
    }

    func stop() {
        session?.nav.stop()
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

    /// The banner's left swipe: the next step, greyed, with the camera moved there. It does not
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
            + " arrived=\(arrived ? 1 : 0)"
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
            + " parked=\(parkingSaved ? 1 : 0) lanes=\(maneuverLanes.count) ref=\(maneuverRef.isEmpty ? "-" : maneuverRef)"
            + " currentref=\(currentRoadRef.isEmpty ? "-" : currentRoadRef) preview=\(previewIndex ?? -1)"
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
        default:
            return VelaL10n.text("nav_speeding_alert")
        }
    }

    private func apply(_ state: NavUiState) {
        let wasActive = active
        let wasPaused = paused
        let revisionChanged = shownRouteRevision != state.routeRevision
        active = state.active
        navigating = state.navigating
        starting = state.starting
        startFailed = state.startFailed
        arrived = state.arrived
        paused = state.paused
        offRoute = state.offRoute
        starved = state.starved
        deadReckoning = state.deadReckoning
        maneuverKind = state.maneuver?.type ?? "STRAIGHT"
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
        loadedCameraGroups = Int(state.loadedCameraGroups)
        trafficDelaySeconds = state.trafficDelaySeconds
        fasterRouteOffered = state.fasterRouteOffered
        fasterSavingSeconds = state.fasterSavingSeconds
        destinationName = state.destinationLabel
        destinationAddress = state.destinationAddress
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
        UIApplication.shared.isIdleTimerDisabled = state.navigating && !state.paused

        if active && !wasActive {
            #if DEBUG
            log.debug("nav replay: start")
            #endif
            parkingSaved = false
            map?.beginNavigation()
        }
        if active && revisionChanged {
            showRoute(revision: state.routeRevision)
        }
        // Pause holds the camera where it is; Resume re-attaches it unless the driver had panned.
        // A previewed step keeps the camera on that step until the card is tapped.
        map?.setNavigationFollowing(!previewing && !state.cameraDetached && !state.paused)
        if active {
            if !state.paused && !previewing {
                updateCamera(force: (wasPaused && !state.paused) || shownFixSequence != state.fixSequence)
                shownFixSequence = state.fixSequence
            }
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
            self.applyLifecycle(.background)
        })
        systemObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.inBackground = false
            UIApplication.shared.isIdleTimerDisabled = self.navigating && !self.paused
            self.applyLifecycle(.foreground)
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

    private static func lanes(_ rows: [NavLane]) -> [NavBannerLane] {
        rows.map { NavBannerLane(arrows: $0.indications, valid: $0.valid) }
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
