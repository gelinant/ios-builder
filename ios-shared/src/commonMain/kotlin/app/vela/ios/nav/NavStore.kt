package app.vela.ios.nav

import app.vela.core.data.ClosingTime
import app.vela.core.diag.DiagSink
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.TravelMode
import app.vela.core.model.bearingTo
import app.vela.core.model.distanceTo
import app.vela.core.nav.NavSession
import app.vela.core.nav.RoadNumbers
import app.vela.core.nav.roadLabel
import app.vela.core.nav.signedHeading
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice
import app.vela.core.platform.VelaHttp
import app.vela.ios.place.PlaceTravelHints
import app.vela.ios.replay.TripsStore
import app.vela.ios.replay.VelaDiag
import app.vela.ios.route.RouteStore
import kotlin.math.exp
import kotlin.math.min
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.datetime.TimeZone

/** One approach lane: the arrows it permits and whether it serves the next maneuver. */
data class NavLane(val indications: List<String>, val valid: Boolean)

/** What a road alert does in the current voice mode, as Android's three-way speaker choice. */
enum class NavAlertCue { SPEAK, CHIME, SILENT }

/** Alerts only mutes guidance and keeps a chime for the alerts; complete mute keeps silence. */
fun navAlertCue(muted: Boolean, alertsOnly: Boolean): NavAlertCue = when {
    muted && alertsOnly -> NavAlertCue.CHIME
    muted -> NavAlertCue.SILENT
    else -> NavAlertCue.SPEAK
}

/** The maneuver the driver must make next, plus the one after it for the compact "Then" row. */
data class NavManeuver(
    val index: Int,
    val type: String,
    val instruction: String,
    val distanceMeters: Double,
    val streetName: String?,
    /** The road entered, kept separately from its route number for the banner's shield. */
    val road: String? = null,
    val ref: String? = null,
    val laneHint: String? = null,
    val lanes: List<NavLane> = emptyList(),
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
)

/** The navigation facet's Swift-facing state. Durations are seconds and distances are meters. */
data class NavUiState(
    val navigating: Boolean = false,
    val starting: Boolean = false,
    val startFailed: Boolean = false,
    val paused: Boolean = false,
    val arrived: Boolean = false,
    /** The selected TravelMode name, kept after RouteStore closes on Start. */
    val travelMode: String = "DRIVE",
    val maneuver: NavManeuver? = null,
    val nextManeuver: NavManeuver? = null,
    val routeDistanceMeters: Double = 0.0,
    val remainingDistanceMeters: Double = 0.0,
    val remainingDurationSeconds: Double = 0.0,
    val offRoute: Boolean = false,
    val starved: Boolean = false,
    /** The published position is synthesized along the route because guidance fixes stopped. */
    val deadReckoning: Boolean = false,
    val speedMps: Double? = null,
    val accuracyM: Double? = null,
    val speedLimitKmh: Double? = null,
    val speeding: Boolean = false,
    val roadAlertKind: String? = null,
    val roadAlertCount: Int = 0,
    /** A bridge's planned opening (epoch ms) for the card's line, 0 for other alerts. */
    val roadAlertAtMs: Long = 0,
    val loadedCameraGroups: Int = 0,
    val trafficDelaySeconds: Double = 0.0,
    val fasterRouteOffered: Boolean = false,
    val fasterSavingSeconds: Double = 0.0,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val bearingDeg: Double? = null,
    val fixSequence: Long = 0,
    val cameraDetached: Boolean = false,
    val northUp: Boolean = false,
    val routeRevision: Long = 0,
    val destinationLabel: String = "",
    val destinationAddress: String = "",
    /** The destination closes within an hour of the live arrival, or before it; null when its
     *  status names no parsable closing time or the new route no longer matches. */
    val closingWarning: ClosingTime.ArrivalWarning? = null,
    val tripDistanceMeters: Double = 0.0,
    val tripElapsedSeconds: Double = 0.0,
    /** The next visible stop's name and figures, empty for a direct trip. */
    val nextStopLabel: String = "",
    val nextStopDistanceMeters: Double = 0.0,
    val nextStopSeconds: Double = 0.0,
    val stopsAhead: Int = 0,
    /** The waypoint just passed, with a serial that changes once per stop. The card is the UI's. */
    val reachedStopLabel: String? = null,
    val reachedStopSerial: Long = 0,
    /** The road under the car, as the banner's current-road line names it. */
    val currentRoadLabel: String = "",
    /** The same road's route number, for the persistent shield, empty when it has none. */
    val currentRoadRef: String = "",
    /** A step the driver swiped to in the banner, null while live guidance shows. */
    val previewIndex: Int? = null,
    val previewManeuver: NavManeuver? = null,
    /** Android's `spoken_directions` and `spoken_alerts_only`: On, Alerts only, or Off. */
    val voiceMuted: Boolean = false,
    val voiceAlertsOnly: Boolean = false,
    /** Settings > Navigation > Bridge openings, on by default as on Android. */
    val bridgeAlerts: Boolean = true,
    /** The live step index, for the lifecycle scenario's "same current step" check. */
    val stepIndex: Int = 0,
    /** How many times a common session was started in this process, never more than one per drive. */
    val sessionStarts: Int = 0,
    /** A persisted drive is being replanned after a relaunch. */
    val resuming: Boolean = false,
    val resumeFailed: Boolean = false,
    /** The live drive was rebuilt from the persisted destination, not picked in the route sheet. */
    val resumedFromRecord: Boolean = false,
    val resumeLabel: String = "",
    /** Movable bridges with an NDW opening found on the current route. */
    val loadedBridges: Int = 0,
    /** Driving with no destination: the drive chrome shows the speed, the posted limit and the
     *  road under the car, but no session, no route and no ETA. */
    val freeDriving: Boolean = false,
    /** A stop was added during the drive and its route is still being planned. */
    val stopsRecalculating: Boolean = false,
    /** How many stops this process added mid-drive, for the debug line and the UI scenarios. */
    val stopAdds: Int = 0,
) {
    /** Arrival keeps the route and camera until Done; End clears both. */
    val active: Boolean get() = navigating || arrived

    /**
     * Whether the arrival card offers to save the car's spot here: a drive that has arrived, with
     * the position it arrived at. Walking and cycling get no offer, and no coordinates means no
     * honest parking spot.
     */
    val parkingOffer: Boolean
        get() = arrived && travelMode == "DRIVE" && latitude != null && longitude != null
}

/**
 * Guided navigation over the common [NavSession]. The selected `RouteStore` route is handed to
 * the session as the very same object. Swift holds no route and only reads rows, numbers and the
 * drawn line. The class lives for the process, independently of any SwiftUI view.
 */
class NavStore(
    private val routeStore: RouteStore,
    private val source: () -> app.vela.core.data.MapDataSource,
    private val scope: CoroutineScope,
    private val clock: Clock,
    alertProvider: NavAlertProvider = NavAlertProvider.EMPTY,
    private val voiceProvider: () -> NavVoice = { InertNavVoice },
    /** The opt-in trip recorder, null in tests that do not exercise saving. */
    private val trips: TripsStore? = null,
    /** Platform preferences. Android keeps the same keys in `vela_settings` and
     *  `vela_nav_resume`; Swift attaches the stores through `attachPreferences`. */
    private val keyValues: () -> KeyValueStores? = { NavPrefsStore.stores },
    private val sessionFactory: () -> NavSession,
) {
    private val _state = MutableStateFlow(NavUiState())
    val state: StateFlow<NavUiState> = _state.asStateFlow()
    private var useImperial = false
    private var voiceMuted = false
    private var voiceAlertsOnly = false
    private var bridgeAlerts = true
    private var sessionStarts = 0
    private var stopAddsCounter = 0
    /** Swift attaches the platform stores after the graph was built but before the first drive. */
    private var attachedStores: KeyValueStores? = null

    /** Swift localizes alert speech through the String Catalog. The fallback keeps JVM tests simple.
     *  [atMs] is the planned opening of a bridge, 0 for the other alerts. Double avoids a boxed
     *  nullable number at the Swift boundary. */
    var alertText: (String, Int, Double) -> String = { kind, count, _ ->
        when (kind) {
            NavRoadAlertKind.SPEED_CAMERA.name -> "Speed camera ahead"
            NavRoadAlertKind.ALPR_CAMERA.name -> if (count > 1) "License plate cameras ahead" else "License plate camera ahead"
            NavRoadAlertKind.BRIDGE_OPEN.name -> "Bridge ahead is open"
            NavRoadAlertKind.BRIDGE_PLANNED.name -> "Bridge ahead: opening planned"
            else -> "You're over the speed limit"
        }
    }

    /** A camera, speeding or bridge warning also has a haptic cue, including while the voice is muted. */
    var warningCue: () -> Unit = {}

    /** The short chime Android plays for an alert in Alerts only, where nothing is spoken. */
    var alertChime: () -> Unit = {}

    private val alerts = NavAlerts(
        provider = alertProvider,
        scope = scope,
        clock = clock,
        imperial = { useImperial },
        audibleAlert = { alert ->
            when (navAlertCue(voiceMuted, voiceAlertsOnly)) {
                // Alerts only: guidance is muted and the alert is a chime, as on Android.
                NavAlertCue.CHIME -> {
                    alertChime()
                    warningCue()
                }
                NavAlertCue.SILENT -> Unit
                NavAlertCue.SPEAK -> {
                    voiceProvider().speak(alertText(alert.kind.name, alert.count, alert.atMs.toDouble()))
                    warningCue()
                }
            }
        },
        onChange = { road ->
            _state.update {
                it.copy(
                    speedLimitKmh = road.speedLimitKmh,
                    speeding = road.speeding,
                    roadAlertKind = road.alert?.kind?.name,
                    roadAlertCount = road.alert?.count ?: 0,
                    roadAlertAtMs = road.alert?.atMs ?: 0L,
                    loadedCameraGroups = road.loadedCameraGroups,
                    loadedBridges = road.loadedBridges,
                )
            }
        },
    )

    init {
        alerts.bridgesEnabled = { bridgeAlerts }
    }

    val location = LocationPipeline(
        scope = scope,
        clock = clock,
        onState = { applyLocation(it) },
        onGuidance = { fix ->
            if (sessionCreated) {
                lastFeedMs = clock.elapsedRealtimeMillis()
                val wasReckoning = deadReckoning
                if (wasReckoning) {
                    // The first real fix after a gap re-anchors the published position before the
                    // session projects it, so the camera never keeps the estimate after recovery.
                    deadReckoning = false
                    _state.update {
                        it.copy(
                            latitude = fix.position.lat,
                            longitude = fix.position.lng,
                            speedMps = fix.speedMps,
                            bearingDeg = fix.bearingDeg ?: it.bearingDeg,
                            fixSequence = it.fixSequence + 1,
                            deadReckoning = false,
                        )
                    }
                }
                session.onLocation(
                    fix.position,
                    imperial = useImperial,
                    speedMps = fix.speedMps,
                    accuracyM = fix.accuracyM,
                    bearingDeg = fix.bearingDeg,
                )
                val nav = _state.value
                trips?.recordFix(
                    latitude = fix.position.lat,
                    longitude = fix.position.lng,
                    t = clock.nowMillis(),
                    bearingDeg = fix.bearingDeg ?: 0.0,
                    speedMps = fix.speedMps ?: 0.0,
                    offRoute = nav.offRoute,
                    accuracyM = fix.accuracyM ?: Double.NaN,
                    provider = "ios",
                    offRouteHits = 0,
                )
            }
        },
    )

    private var started = false
    private var sessionCreated = false
    private val session: NavSession by lazy {
        sessionFactory().also { sessionCreated = true }
    }
    private var observeJob: Job? = null
    private var startJob: Job? = null
    private var generation = 0
    private var lastRoute: Route? = null
    private var lastRecordedRoute: Route? = null
    /** The place the drive is headed to, kept only for its closing status on the banner. */
    private var destinationPlace: Place? = null
    private var lastFeedMs = 0L
    /** The visible stops still ahead at the previous publication, to notice a waypoint passed. */
    private var lastStopLabels: List<String> = emptyList()

    // The drive that a process kill interrupted. Android keeps the same values in the
    // `vela_nav_resume` SharedPreferences file and replans from the first fresh fix after Resume.
    private var resumeDestination: LatLng? = null
    private var resumeLabel = ""
    private var resumeMode = TravelMode.DRIVE
    private var lastResumeHeartbeatMs = 0L
    private var resumeJob: Job? = null

    // Tunnel dead reckoning (port of NavController.tunnelDeadReckonLoop). Progress is meters along
    // the route; NaN means the loop is not reckoning.
    private var drProgressM = Double.NaN
    private var drCapM = 0.0
    private var drTotalM = 0.0
    private var drSpeed = 0.0
    private var drLastMs = 0L
    private var deadReckoning = false

    // Free driving's road lookup. Swift attaches the HTTP seam once, before the first drive.
    // Lookups are single-flight and paced by distance, since the road under the car changes at
    // the speed of the car, not at the speed of the fix stream.
    private var freeRoadLookup: FreeDriveRoadLookup? = null
    private var freeLookupJob: Job? = null
    private var freeLookupLat = Double.NaN
    private var freeLookupLng = Double.NaN
    private var freeLookupAtMs = 0L
    private var lastFreeLimitAt: LatLng? = null
    private var stopsRecalcAtMs = 0L

    /** Arms the location timers and the tunnel estimator. The session and its Apple seams are
     * built on the first drive, after Swift has supplied them through
     * `MapSession.configureNavigation`. */
    fun start() {
        if (started) return
        started = true
        location.start()
        scope.launch { deadReckoningLoop() }
        if (stores() != null) {
            readPreferences()
            maybeResumeOnLaunch()
        }
    }

    /** Hands the platform stores to the navigation facet. The session is built before Swift's
     *  view model exists, so this is the first moment the resume record and the voice keys can be
     *  read. Calling it again with the same stores is inert. */
    fun attachPreferences(stores: KeyValueStores) {
        if (attachedStores === stores) return
        attachedStores = stores
        if (started) {
            readPreferences()
            maybeResumeOnLaunch()
        }
    }

    /** The HTTP seam for free driving's road lookup. Called once by the navigation view model;
     *  a JVM test can inject its own fake through the same method. */
    fun attachFreeDriveHttp(http: VelaHttp) {
        if (freeRoadLookup == null) {
            freeRoadLookup = FreeDriveRoadLookup(http, nowMillis = { clock.nowMillis() })
        }
    }

    /**
     * Enters free driving: no destination, no session and no route. The location pipeline already
     * publishes the fix, speed and bearing; this only turns on the drive chrome and the road
     * lookup. A persisted drive is not consumed and no resume record is written, because free
     * driving has no destination to restore.
     */
    fun startFreeDrive() {
        if (!started || _state.value.active || _state.value.freeDriving) return
        resumeJob?.cancel()
        resumeJob = null
        freeLookupJob?.cancel()
        freeLookupJob = null
        freeLookupLat = Double.NaN
        freeLookupLng = Double.NaN
        freeLookupAtMs = 0L
        lastFreeLimitAt = null
        alerts.reset()
        _state.value = NavUiState(
            latitude = location.state.value.latitude,
            longitude = location.state.value.longitude,
            speedMps = location.state.value.speedMps,
            bearingDeg = location.state.value.bearingDeg,
            accuracyM = location.state.value.accuracyM,
            fixSequence = location.state.value.fixSequence,
            voiceMuted = voiceMuted,
            voiceAlertsOnly = voiceAlertsOnly,
            bridgeAlerts = bridgeAlerts,
            sessionStarts = sessionStarts,
            freeDriving = true,
        )
        // The car may already be tracked: ask for the road now rather than at the next fix.
        maybeLookupFreeRoad(location.state.value)
        VelaDiag.navStarted()
    }

    /** Leaves free driving. The resume record is untouched: this mode never owned one. */
    fun stopFreeDrive() {
        if (!_state.value.freeDriving) return
        freeLookupJob?.cancel()
        freeLookupJob = null
        freeLookupLat = Double.NaN
        freeLookupLng = Double.NaN
        freeLookupAtMs = 0L
        lastFreeLimitAt = null
        _state.value = NavUiState(
            latitude = location.state.value.latitude,
            longitude = location.state.value.longitude,
            speedMps = location.state.value.speedMps,
            bearingDeg = location.state.value.bearingDeg,
            accuracyM = location.state.value.accuracyM,
            fixSequence = location.state.value.fixSequence,
            voiceMuted = voiceMuted,
            voiceAlertsOnly = voiceAlertsOnly,
            bridgeAlerts = bridgeAlerts,
            sessionStarts = sessionStarts,
        )
    }

    /**
     * Adds [name] at the given point as the LAST stop of a live guided drive and replans through
     * it from the current fix. The shared session owns the fetch and the ETA; this store only
     * publishes the recalculation state the chrome shows, and clears it when the new route lands.
     */
    fun addStop(name: String, latitude: Double, longitude: Double) {
        val state = _state.value
        if (!state.navigating || state.paused || !sessionCreated) return
        val hereLat = state.latitude ?: return
        val hereLng = state.longitude ?: return
        stopAddsCounter++
        stopsRecalcAtMs = clock.elapsedRealtimeMillis()
        _state.update {
            it.copy(
                stopsRecalculating = true,
                stopAdds = stopAddsCounter,
            )
        }
        session.addStop(
            NavSession.NavStop(LatLng(latitude, longitude), name),
            LatLng(hereLat, hereLng),
            atEnd = true,
        )
    }

    /** Voice mode and bridge alerts survive the process. Android stores them in `vela_settings`. */
    private fun readPreferences() {
        val store = settingsStore() ?: return
        val muted = !store.getBoolean(KEY_SPOKEN_DIRECTIONS, true)
        val alertsOnly = muted && store.getBoolean(KEY_SPOKEN_ALERTS_ONLY, false)
        bridgeAlerts = store.getBoolean(KEY_BRIDGE_OPENINGS, true)
        voiceMuted = muted
        voiceAlertsOnly = alertsOnly
        _state.update {
            it.copy(
                voiceMuted = muted,
                voiceAlertsOnly = alertsOnly,
                bridgeAlerts = bridgeAlerts,
            )
        }
        if (muted) voiceProvider().stop()
    }

    /** Settings > Voice, also behind the in-drive speaker button: On, Alerts only, Off. */
    fun setVoiceMode(muted: Boolean, alertsOnly: Boolean) {
        val alerts = muted && alertsOnly
        if (voiceMuted == muted && voiceAlertsOnly == alerts) return
        voiceMuted = muted
        voiceAlertsOnly = alerts
        _state.update { it.copy(voiceMuted = muted, voiceAlertsOnly = alerts) }
        val store = settingsStore()
        store?.edit()
            ?.putBoolean(KEY_SPOKEN_DIRECTIONS, !muted)
            ?.putBoolean(KEY_SPOKEN_ALERTS_ONLY, alerts)
            ?.apply()
        if (muted) voiceProvider().stop()
    }

    /** The banner's speaker button cycle, exactly Android's: On, then Alerts only, then Off. */
    fun cycleVoiceMode() {
        when {
            !voiceMuted -> setVoiceMode(muted = true, alertsOnly = true)
            voiceAlertsOnly -> setVoiceMode(muted = true, alertsOnly = false)
            else -> setVoiceMode(muted = false, alertsOnly = false)
        }
    }

    /** Settings > Navigation > Bridge openings. On by default, as on Android. */
    fun setBridgeAlerts(on: Boolean) {
        if (bridgeAlerts == on) return
        bridgeAlerts = on
        _state.update { it.copy(bridgeAlerts = on) }
        settingsStore()?.edit()?.putBoolean(KEY_BRIDGE_OPENINGS, on)?.apply()
    }

    private fun settingsStore(): KeyValueStore? = stores()?.open(SETTINGS_STORE)

    private fun resumeStore(): KeyValueStore? = stores()?.open(RESUME_STORE)

    private fun stores(): KeyValueStores? = attachedStores ?: keyValues()

    fun setImperial(on: Boolean) {
        useImperial = on
    }

    /** Settings > Navigation > Road numbers first. The preference lives in the shared label
     *  builder, so the current-road line follows it without rebuilding the route. */
    fun setRoadNumbersFirst(on: Boolean) {
        RoadNumbers.preferred = on
    }

    /** Swipes the banner [stepOffset] steps from the live maneuver, or from the step already
     *  previewed. Preview state lives here so Swift reads one published value per frame. */
    fun preview(stepOffset: Int) {
        if (!_state.value.navigating || !sessionCreated) return
        val ns = session.state.value
        val last = ns.route?.maneuvers?.lastIndex ?: return
        if (last < 0) return
        val base = _state.value.previewIndex ?: ns.nav.stepIndex
        val target = (base + stepOffset).coerceIn(0, last)
        _state.update { it.copy(previewIndex = target, previewManeuver = maneuver(ns, target)) }
    }

    /** Taps the previewed banner: live guidance takes the card back, the same session and route. */
    fun exitPreview() {
        if (_state.value.previewIndex == null) return
        _state.update { it.copy(previewIndex = null, previewManeuver = null) }
    }

    /** Swift's `CLLocationManager` callback, already stamped with the monotonic clock. A NaN
     * measurement means unknown, avoiding boxed nullable numbers at the Swift boundary. */
    fun onFix(
        latitude: Double,
        longitude: Double,
        accuracyM: Double,
        speedMps: Double,
        bearingDeg: Double,
        elapsedNanos: Long,
        gnss: Boolean,
    ) {
        location.onFix(LocationFix(
            latitude,
            longitude,
            accuracyM.takeIf { it.isFinite() },
            speedMps.takeIf { it.isFinite() },
            bearingDeg.takeIf { it.isFinite() },
            elapsedNanos,
            gnss,
        ))
    }

    /** Starts the selected route. Repeated taps share one start job. */
    fun startNavigation() {
        if (!started || startJob?.isActive == true || _state.value.active || _state.value.freeDriving) return
        val rs = routeStore.state.value
        val picked = rs.active ?: return
        val end = picked.polyline.lastOrNull() ?: return
        ensureObserver()
        val gen = ++generation
        _state.update {
            it.copy(starting = true, startFailed = false, closingWarning = null, travelMode = rs.mode.name)
        }
        startJob = scope.launch {
            try {
                val route = if (picked.provisional) {
                    routeStoreSourceName(picked)
                } else {
                    picked
                }
                if (gen != generation || !route.drivable) {
                    _state.update { it.copy(starting = false, startFailed = true) }
                    VelaDiag.warn("navigation: route not drivable")
                    return@launch
                }
                val destinationPlace = if (rs.reversed) rs.origin else rs.destination
                this@NavStore.destinationPlace = destinationPlace
                val display = NavSession.destinationDisplay(destinationPlace?.name, destinationPlace?.address, end)
                // The chooser's stops are in travel order (`RouteStore.swap` reverses them with the
                // ends), so the session can announce each one and keep the same drive afterwards.
                val stops = rs.waypoints.map { NavSession.NavStop(it.location, it.name) }
                session.start(
                    route = route,
                    destination = end,
                    destinationLabel = display.first,
                    destinationAddress = display.second.orEmpty(),
                    stops = stops,
                    mode = rs.mode,
                )
                VelaDiag.navStarted()
                if (trips?.recordingEnabled == true) {
                    if (trips.startTrip(display.first, end, clock.nowMillis()) != null) {
                        trips.saveRoute(route, "start")
                        lastRecordedRoute = route
                    } else {
                        VelaDiag.warn("trip: could not start recording")
                    }
                }
                location.navigationStarted()
                lastFeedMs = 0L
                resetDeadReckoning()
                routeStore.close()
                resumeDestination = end
                resumeLabel = display.first
                resumeMode = rs.mode
                lastResumeHeartbeatMs = clock.nowMillis()
                sessionStarts++
                _state.update {
                    it.copy(
                        starting = false,
                        sessionStarts = sessionStarts,
                        resumedFromRecord = false,
                        resumeFailed = false,
                    )
                }
                persistResume()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                VelaDiag.warn("navigation: start failed")
                if (gen == generation) _state.update { it.copy(starting = false, startFailed = true) }
            }
        }
    }

    /** Names a provisional alternate through the same source as the rest of the session. */
    private suspend fun routeStoreSourceName(route: Route): Route {
        val rs = routeStore.state.value
        return source().nameRoute(
            route,
            route.polyline.first(),
            route.polyline.last(),
            rs.mode,
            rs.avoidTolls,
            rs.avoidHighways,
            rs.avoidFerries,
        )
    }

    /** A drive interrupted by a process kill: the next launch offers the same destination again.
     *  Unlike Android there is no prompt screen of its own, so the drive returns on its own once a
     *  position is available; a failure leaves the record for the next foreground. */
    private fun maybeResumeOnLaunch() {
        val record = readResumeRecord() ?: return
        if (clock.nowMillis() - record.at > RESUME_MAX_AGE_MS) {
            clearResumeRecord()
            return
        }
        _state.update { it.copy(resuming = true, resumeFailed = false, resumeLabel = record.label) }
        resumeJob = scope.launch { runResume(record) }
    }

    /** Retries the persisted drive, for the host after a foreground or the lifecycle scenario.
     *  No-op while a drive is live or being started. */
    fun resumeNavigation() {
        if (!started || _state.value.active || _state.value.freeDriving ||
            startJob?.isActive == true || resumeJob?.isActive == true
        ) return
        val record = readResumeRecord() ?: return
        if (clock.nowMillis() - record.at > RESUME_MAX_AGE_MS) {
            clearResumeRecord()
            return
        }
        _state.update { it.copy(resuming = true, resumeFailed = false, resumeLabel = record.label) }
        resumeJob = scope.launch { runResume(record) }
    }

    /** Replans from the first fresh fix, exactly as Android's `resumeNav` does: the road driven
     *  while the process was gone is not redrawn, and the remaining ETA and step are the rerouted
     *  ones. The saved origin is the fallback when no fix arrives in the window. */
    private suspend fun runResume(record: ResumeRecord) {
        try {
            val fresh = withTimeoutOrNull(RESUME_FIX_WAIT_MS) {
                location.state.first { it.latitude != null && it.longitude != null }
            }
            val origin = fresh?.let { LatLng(it.latitude!!, it.longitude!!) } ?: record.origin
            if (origin == null) {
                failResume("navigation: resume has no position")
                return
            }
            val routes = try {
                source().directions(origin, record.destination, record.mode)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                emptyList()
            }
            var route = routes.firstOrNull()
            if (route != null && route.provisional) {
                route = try {
                    source().nameRoute(route, origin, record.destination, record.mode)
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    route
                }
            }
            if (route == null || !route.drivable) {
                failResume("navigation: resume route unavailable")
                return
            }
            ensureObserver()
            generation++
            session.start(
                route = route,
                destination = record.destination,
                destinationLabel = record.label,
                stops = emptyList(),
                mode = record.mode,
            )
            resumeDestination = record.destination
            resumeLabel = record.label
            resumeMode = record.mode
            lastResumeHeartbeatMs = clock.nowMillis()
            location.navigationStarted()
            lastFeedMs = 0L
            lastStopLabels = emptyList()
            resetDeadReckoning()
            routeStore.close()
            sessionStarts++
            _state.update {
                it.copy(
                    resuming = false,
                    resumeFailed = false,
                    resumedFromRecord = true,
                    resumeLabel = record.label,
                    sessionStarts = sessionStarts,
                )
            }
            persistResume()
            VelaDiag.navStarted()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            failResume("navigation: resume failed")
        }
    }

    private fun failResume(reason: String) {
        VelaDiag.warn(reason)
        _state.update { it.copy(resuming = false, resumeFailed = true) }
    }

    /** Called on start, on the 5 min heartbeat and after a resumed plan. Android clears the record
     *  on End and on arrival so a finished drive is never offered again. */
    private fun persistResume() {
        val store = resumeStore() ?: return
        val destination = resumeDestination ?: return
        val live = _state.value
        store.edit()
            .putLong(RESUME_AT, clock.nowMillis())
            .putString(RESUME_LAT, destination.lat.toString())
            .putString(RESUME_LNG, destination.lng.toString())
            .putString(RESUME_LABEL, resumeLabel)
            .putString(RESUME_MODE, resumeMode.name)
            .putString(RESUME_ORIGIN_LAT, (live.latitude ?: destination.lat).toString())
            .putString(RESUME_ORIGIN_LNG, (live.longitude ?: destination.lng).toString())
            // A process kill follows a relaunch test, so this write must be on disk before the
            // call returns; it happens on start and every five minutes, never per fix.
            .commit()
        lastResumeHeartbeatMs = clock.nowMillis()
    }

    private fun clearResumeRecord() {
        resumeDestination = null
        resumeLabel = ""
        lastResumeHeartbeatMs = 0L
        resumeStore()?.edit()?.clear()?.commit()
        _state.update {
            it.copy(resuming = false, resumeFailed = false, resumedFromRecord = false, resumeLabel = "")
        }
    }

    private fun readResumeRecord(): ResumeRecord? {
        val store = resumeStore() ?: return null
        val at = store.getLong(RESUME_AT, 0L)
        val lat = store.getString(RESUME_LAT, null)?.toDoubleOrNull()
        val lng = store.getString(RESUME_LNG, null)?.toDoubleOrNull()
        if (at <= 0L || lat == null || lng == null) return null
        val originLat = store.getString(RESUME_ORIGIN_LAT, null)?.toDoubleOrNull()
        val originLng = store.getString(RESUME_ORIGIN_LNG, null)?.toDoubleOrNull()
        val origin = if (originLat != null && originLng != null) LatLng(originLat, originLng) else null
        val mode = runCatching { TravelMode.valueOf(store.getString(RESUME_MODE, null).orEmpty()) }
            .getOrDefault(TravelMode.DRIVE)
        return ResumeRecord(
            destination = LatLng(lat, lng),
            label = store.getString(RESUME_LABEL, null).orEmpty(),
            mode = mode,
            at = at,
            origin = origin,
        )
    }

    private data class ResumeRecord(
        val destination: LatLng,
        val label: String,
        val mode: TravelMode,
        val at: Long,
        val origin: LatLng?,
    )

    fun stop() {
        generation++
        startJob?.cancel()
        startJob = null
        resumeJob?.cancel()
        resumeJob = null
        if (sessionCreated) session.stop()
        alerts.reset()
        location.navigationEnded()
        routeStore.close()
        trips?.finishTrip()
        lastRoute = null
        lastRecordedRoute = null
        destinationPlace = null
        lastFeedMs = 0L
        lastStopLabels = emptyList()
        clearResumeRecord()
        resetDeadReckoning()
        _state.value = NavUiState(
            latitude = location.state.value.latitude,
            longitude = location.state.value.longitude,
            speedMps = location.state.value.speedMps,
            bearingDeg = location.state.value.bearingDeg,
            fixSequence = location.state.value.fixSequence,
            voiceMuted = voiceMuted,
            voiceAlertsOnly = voiceAlertsOnly,
            bridgeAlerts = bridgeAlerts,
            sessionStarts = sessionStarts,
        )
    }

    /** Holds the drive without losing the route: the common session stops speaking, rerouting,
     *  arrival and stop cues while paused, and the camera stops following. Resume reuses the same
     *  session, so no route is planned again and no Live Activity is requested again. */
    fun setPaused(on: Boolean) {
        if (!_state.value.navigating || _state.value.paused == on) return
        if (sessionCreated) session.setPaused(on)
        val accepted = !sessionCreated || session.state.value.paused
        _state.update { it.copy(paused = accepted) }
        if (on && accepted) {
            resetDeadReckoning()
            voiceProvider().stop()
        }
    }

    fun acceptFasterRoute() {
        if (sessionCreated) session.acceptFasterRoute()
    }

    fun dismissFasterRoute() {
        if (sessionCreated) session.dismissFasterRoute()
    }

    fun panned() {
        if (_state.value.navigating || _state.value.freeDriving) {
            _state.update { it.copy(cameraDetached = true) }
        }
    }

    fun recenter() {
        _state.update { it.copy(cameraDetached = false) }
    }

    fun toggleNorthUp() {
        _state.update { it.copy(northUp = !it.northUp, cameraDetached = false) }
    }

    /** The active route's line as latitude, longitude pairs, empty outside a drive. */
    fun line(): DoubleArray = if (sessionCreated) RouteStore.lineOf(session.state.value.route) else DoubleArray(0)

    /**
     * The live route reduced to what the navigation map draws: the travelled and congestion
     * pieces, the two manoeuvre arrows and the lane row at the approach. Null outside a drive.
     * Every value comes from the shared route; this adds no invented traffic or glyph.
     */
    fun renderFrame(): NavRenderFrame? {
        if (!sessionCreated) return null
        val ns = session.state.value
        val route = ns.route ?: return null
        val st = _state.value
        return NavMapRender.build(
            route = route,
            traveledM = ns.nav.traveledM,
            stepIndex = ns.nav.stepIndex,
            distanceToNext = ns.nav.distanceToNextManeuver,
            speedMps = st.speedMps,
            previewIndex = st.previewIndex?.toInt(),
            previewManeuver = st.previewManeuver,
        )
    }

    fun watch(onChange: (NavUiState) -> Unit): Cancellable {
        val job = scope.launch { state.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    private fun ensureObserver() {
        if (observeJob != null) return
        session.onNote = { text ->
            trips?.note("K", text)
            if (text.contains("FAIL") || text.contains("abandon") || text.contains("wedged")) {
                VelaDiag.warn("nav: $text")
            }
        }
        observeJob = scope.launch {
            session.state.collect { ns ->
                val wasArrived = _state.value.arrived
                val routeChanged = ns.route !== lastRoute
                lastRoute = ns.route
                if (routeChanged) alerts.onRoute(ns.route)
                val step = ns.nav.stepIndex
                // A waypoint passed is a change of remaining stops, announced once. Only a drop of
                // the list's prefix counts: a stops edit that replaces the list must not fire the
                // card for stops the driver never reached.
                val remainingStops = if (ns.navigating) session.remainingStops() else emptyList()
                val remainingLabels = remainingStops.map { it.label }
                var reachedLabel: String? = null
                val dropped = lastStopLabels.size - remainingLabels.size
                if (ns.navigating && dropped > 0 && remainingLabels == lastStopLabels.drop(dropped)) {
                    reachedLabel = lastStopLabels[dropped - 1]
                }
                lastStopLabels = remainingLabels
                val toStop = ns.nextStop
                val (roadLabelNow, roadRefNow) = currentRoad(ns)
                _state.update { old ->
                    old.copy(
                        navigating = ns.navigating,
                        paused = ns.paused,
                        arrived = ns.arrived,
                        maneuver = maneuver(ns, step),
                        nextManeuver = maneuver(ns, step + 1),
                        stepIndex = step,
                        routeDistanceMeters = ns.route?.distanceMeters ?: 0.0,
                        remainingDistanceMeters = ns.remainingDistance,
                        remainingDurationSeconds = ns.remainingDuration,
                        offRoute = ns.navigating && ns.nav.offRoute,
                        trafficDelaySeconds = trafficDelay(ns),
                        fasterRouteOffered = ns.fasterRoute != null,
                        fasterSavingSeconds = ns.fasterSavingSeconds,
                        destinationLabel = ns.destinationLabel,
                        destinationAddress = ns.destinationAddress,
                        // A reroute or an accepted faster route moves the arrival, so the warning
                        // is recomputed from the new remaining time and disappears when the new
                        // route no longer matches the closing hour.
                        closingWarning = if (routeChanged) closingWarningFor(ns) else old.closingWarning,
                        tripDistanceMeters = ns.tripDistanceMeters,
                        tripElapsedSeconds = ns.tripElapsedSeconds,
                        nextStopLabel = toStop?.label.orEmpty(),
                        nextStopDistanceMeters = toStop?.distanceM ?: 0.0,
                        nextStopSeconds = toStop?.seconds ?: 0.0,
                        stopsAhead = remainingStops.size,
                        reachedStopLabel = reachedLabel ?: old.reachedStopLabel,
                        reachedStopSerial = old.reachedStopSerial + if (reachedLabel != null) 1 else 0,
                        routeRevision = old.routeRevision + if (routeChanged) 1 else 0,
                        currentRoadLabel = roadLabelNow,
                        currentRoadRef = roadRefNow,
                        // A new route makes a previewed old step meaningless. Otherwise the
                        // preview follows its step while the live card keeps advancing.
                        previewIndex = if (routeChanged) null else old.previewIndex,
                        previewManeuver = if (routeChanged) null
                            else old.previewIndex?.let { maneuver(ns, it) },
                        stopsRecalculating = old.stopsRecalculating && ns.navigating &&
                            !routeChanged && ns.nextStop == null &&
                            clock.elapsedRealtimeMillis() - stopsRecalcAtMs < STOP_RECALC_TIMEOUT_MS,
                        stopAdds = stopAddsCounter,
                    )
                }
                // A reroute or an accepted faster route is a new drive segment: record the route
                // the car is actually on, at the fix where the swap happened.
                val nsRoute = ns.route
                if (ns.navigating && nsRoute != null && nsRoute !== lastRecordedRoute) {
                    if (lastRecordedRoute != null) trips?.saveRoute(nsRoute, session.lastSwapReason)
                    lastRecordedRoute = nsRoute
                }
                if (ns.arrived && !wasArrived) {
                    trips?.finishTrip()
                    lastRecordedRoute = null
                    clearResumeRecord()
                }
                // Android refreshes the resume timestamp every five minutes while driving, so the
                // one hour window measures time since the interruption, not since the start.
                if (ns.navigating && resumeDestination != null &&
                    clock.nowMillis() - lastResumeHeartbeatMs >= RESUME_HEARTBEAT_MS
                ) {
                    persistResume()
                }
                alerts.update(ns, _state.value.speedMps)
            }
        }
    }

    /**
     * The banner's closing line, from the destination's own Google status and the drive's
     * remaining time. Android's same 60-minute window (`NavController.closingMessage`): a place
     * with no parsable status, an arrival more than an hour before the doors close, or a resumed
     * drive whose place was never known all leave the line absent.
     */
    private fun closingWarningFor(ns: NavSession.State): ClosingTime.ArrivalWarning? {
        val place = destinationPlace ?: return null
        if (!ns.navigating) return null
        val nowSec = clock.nowMillis() / 1000L
        return PlaceTravelHints.closingWarning(
            name = place.name,
            statusText = place.statusText,
            openNow = when (place.openNow) {
                true -> 1
                false -> 0
                null -> -1
            },
            arrivalEpochSec = nowSec + ns.remainingDuration.toLong(),
            nowEpochSec = nowSec,
            zoneId = TimeZone.currentSystemDefault().id,
        )
    }

    /** The part of the remaining live ETA attributable to congestion, never a fabricated delay. */
    private fun trafficDelay(ns: NavSession.State): Double {
        if (!ns.navigating) return 0.0
        val ratio = ns.route?.trafficRatio ?: return 0.0
        return if (ratio > 1.0) ns.remainingDuration * (1.0 - 1.0 / ratio) else 0.0
    }

    private fun maneuver(ns: NavSession.State, index: Int): NavManeuver? {
        val route = ns.route ?: return null
        val m = route.maneuvers.getOrNull(index) ?: return null
        val current = index == ns.nav.stepIndex
        return NavManeuver(
            index = index,
            type = m.type.name,
            instruction = if (current) ns.maneuverText else m.instruction,
            distanceMeters = if (current) ns.nav.distanceToNextManeuver else m.distanceMeters,
            streetName = m.road?.takeIf { it.isNotBlank() } ?: m.ref?.takeIf { it.isNotBlank() },
            road = m.road?.takeIf { it.isNotBlank() },
            ref = m.ref?.takeIf { it.isNotBlank() },
            laneHint = m.laneHint?.takeIf { it.isNotBlank() },
            lanes = m.lanes.map { NavLane(it.indications, it.valid) },
            latitude = m.location.lat,
            longitude = m.location.lng,
        )
    }

    /** The road under the car, following the leg's silent renames. Empty before the first
     *  maneuver, so no name is invented while the route is still starting. */
    private fun currentRoad(ns: NavSession.State): Pair<String, String> {
        val maneuvers = ns.route?.maneuvers ?: return "" to ""
        // Before the first turn the DEPART step names the road being driven.
        val index = (ns.nav.stepIndex - 1).coerceAtLeast(0)
        val m = maneuvers.getOrNull(index) ?: return "" to ""
        val traveled = (m.distanceMeters - ns.nav.distanceToNextManeuver).coerceAtLeast(0.0)
        val (name, ref) = m.roadAt(traveled)
        val cleanRef = ref?.takeIf { it.isNotBlank() }
        val label = roadLabel(
            name,
            cleanRef,
            cleanRef?.let { signedHeading(maneuvers, index, it) },
        ).orEmpty()
        return label to cleanRef.orEmpty()
    }

    /** Sleeps until a drive is on, then estimates at 1 Hz, the same window and limits as Android's
     *  `tunnelDeadReckonLoop`: start after 3.5 s without a guidance fix, decay the last speed with
     *  a 60 s tau, never start below 1.5 m/s, stop after 3 km and hold 15 m before the next turn. */
    private suspend fun deadReckoningLoop() {
        while (scope.isActive) {
            if (!_state.value.navigating) {
                resetDeadReckoning()
                _state.first { it.navigating }
            }
            delay(1_000)
            tickDeadReckoning()
        }
    }

    private fun tickDeadReckoning() {
        if (!sessionCreated) {
            resetDeadReckoning()
            return
        }
        val now = clock.elapsedRealtimeMillis()
        val ns = session.state.value
        val route = ns.route
        val state = _state.value
        val eligible = ns.navigating && !state.paused && !state.offRoute && route != null &&
            route.polyline.size >= 2 && lastFeedMs > 0L && now - lastFeedMs > DR_START_MS
        if (!eligible) {
            resetDeadReckoning()
            return
        }
        if (drProgressM.isNaN()) {
            // A standstill when the feed goes quiet never starts reckoning: there is no evidence
            // the car is still moving.
            drSpeed = state.speedMps ?: 0.0
            if (drSpeed < DR_MIN_SPEED) return
            drProgressM = ns.nav.traveledM
            drCapM = ns.nav.traveledM + ns.nav.distanceToNextManeuver - DR_TURN_HOLD_M
            drTotalM = 0.0
            drLastMs = now
            return
        }
        val dt = ((now - drLastMs) / 1000.0).coerceIn(0.5, 3.0)
        drLastMs = now
        drSpeed *= exp(-dt / DR_DECAY_S)
        if (drSpeed < DR_MIN_SPEED || drTotalM > DR_MAX_M) return
        if (drProgressM >= drCapM) return // at the turn: hold until a fix says where the car went
        val step = min(drSpeed * dt, (drCapM - drProgressM).coerceAtLeast(0.0))
        drProgressM += step
        drTotalM += step
        val sample = sampleAlong(route.polyline, drProgressM) ?: return
        deadReckoning = true
        _state.update {
            it.copy(
                latitude = sample.first.lat,
                longitude = sample.first.lng,
                speedMps = drSpeed,
                bearingDeg = sample.second ?: it.bearingDeg,
                fixSequence = it.fixSequence + 1,
                deadReckoning = true,
            )
        }
        session.onLocation(sample.first, imperial = useImperial, speedMps = drSpeed)
    }

    private fun resetDeadReckoning() {
        drProgressM = Double.NaN
        if (deadReckoning) {
            deadReckoning = false
            _state.update { it.copy(deadReckoning = false) }
        }
    }

    /** The point and local bearing [m] meters along [poly], clamped to the ends. */
    private fun sampleAlong(poly: List<LatLng>, m: Double): Pair<LatLng, Double?>? {
        if (poly.size < 2) return null
        if (m <= 0.0) return poly.first() to poly[0].bearingTo(poly[1])
        var acc = 0.0
        for (i in 1 until poly.size) {
            val from = poly[i - 1]
            val to = poly[i]
            val length = from.distanceTo(to)
            if (acc + length >= m) {
                val f = if (length > 0.0) (m - acc) / length else 0.0
                val point = LatLng(
                    from.lat + (to.lat - from.lat) * f,
                    from.lng + (to.lng - from.lng) * f,
                )
                return point to from.bearingTo(to)
            }
            acc += length
        }
        val last = poly.last()
        return last to poly[poly.size - 2].bearingTo(last)
    }

    private fun applyLocation(location: LocationState) {
        _state.update {
            // A poor-accuracy fix keeps moving the real dot until guidance-quality fixes stop. Once
            // the estimator is steering, only the estimate moves the published position, so the
            // two feeds cannot fight over the camera.
            if (deadReckoning) {
                it.copy(accuracyM = location.accuracyM, starved = it.navigating && location.starved)
            } else {
                it.copy(
                    latitude = location.latitude,
                    longitude = location.longitude,
                    accuracyM = location.accuracyM,
                    speedMps = location.speedMps,
                    bearingDeg = location.bearingDeg,
                    fixSequence = location.fixSequence,
                    starved = it.navigating && location.starved,
                )
            }
        }
        if (_state.value.freeDriving) maybeLookupFreeRoad(location)
    }

    /**
     * Refreshes the road under a free-driving car from OSM. One lookup is in flight at a time; a
     * new one starts only after [FREE_LOOKUP_M] of travel, or [FREE_LOOKUP_MS] and [FREE_LOOKUP_MIN_M].
     * A standing car never repeats a lookup, and a failed one is retried once the car moves.
     */
    private fun maybeLookupFreeRoad(location: LocationState) {
        val lookup = freeRoadLookup ?: return
        val lat = location.latitude ?: return
        val lng = location.longitude ?: return
        if (freeLookupJob?.isActive == true) return
        val now = clock.nowMillis()
        val moved = if (freeLookupLat.isNaN()) Double.MAX_VALUE
        else LatLng(freeLookupLat, freeLookupLng).distanceTo(LatLng(lat, lng))
        val due = moved >= FREE_LOOKUP_M || (moved >= FREE_LOOKUP_MIN_M && now - freeLookupAtMs >= FREE_LOOKUP_MS)
        if (!due) return
        freeLookupLat = lat
        freeLookupLng = lng
        freeLookupAtMs = now
        freeLookupJob = scope.launch {
            val road = runCatching { lookup.roadAt(lat, lng) }.getOrNull()
            if (!_state.value.freeDriving) return@launch
            val limit = road?.limitKmh
            if (limit != null) lastFreeLimitAt = LatLng(lat, lng)
            val keepLimit = limit ?: _state.value.speedLimitKmh.takeIf {
                lastFreeLimitAt?.let { at -> at.distanceTo(LatLng(lat, lng)) <= FREE_FORGET_M } == true
            }
            _state.update {
                if (!it.freeDriving) it else it.copy(
                    currentRoadLabel = road?.name ?: road?.ref.orEmpty(),
                    currentRoadRef = road?.ref.orEmpty(),
                    speedLimitKmh = keepLimit,
                )
            }
        }
    }

    companion object {
        private const val DR_START_MS = 3_500L
        private const val DR_DECAY_S = 60.0
        private const val DR_MIN_SPEED = 1.5
        private const val DR_MAX_M = 3_000.0
        private const val DR_TURN_HOLD_M = 15.0
        /** A free-drive road lookup is refreshed after this much travel, or the pair below. */
        private const val FREE_LOOKUP_M = 120.0
        private const val FREE_LOOKUP_MIN_M = 30.0
        private const val FREE_LOOKUP_MS = 12_000L
        /** A known limit is kept across a short untagged gap this close to where it was read. */
        private const val FREE_FORGET_M = 80.0
        /** The chrome stops showing "Rerouting" if the stops replan never lands. */
        private const val STOP_RECALC_TIMEOUT_MS = 20_000L
        private const val RESUME_MAX_AGE_MS = 60 * 60 * 1000L
        private const val RESUME_HEARTBEAT_MS = 5 * 60 * 1000L
        private const val RESUME_FIX_WAIT_MS = 8_000L

        /** The stores' names are Android's, so the settings keep the same key on both platforms. */
        const val SETTINGS_STORE = "vela_settings"
        const val RESUME_STORE = "vela_nav_resume"
        const val KEY_SPOKEN_DIRECTIONS = "spoken_directions"
        const val KEY_SPOKEN_ALERTS_ONLY = "spoken_alerts_only"
        const val KEY_BRIDGE_OPENINGS = "bridge_openings"
        const val RESUME_AT = "at"
        const val RESUME_LAT = "lat"
        const val RESUME_LNG = "lng"
        const val RESUME_LABEL = "label"
        const val RESUME_MODE = "mode"
        const val RESUME_ORIGIN_LAT = "origin_lat"
        const val RESUME_ORIGIN_LNG = "origin_lng"

        /** The production factory, kept here so MapSession has only graph wiring. */
        fun session(
            source: app.vela.core.data.MapDataSource,
            voice: NavVoice,
            haptics: NavHaptics,
            log: app.vela.core.platform.Log,
            clock: Clock,
        ): NavSession = NavSession(source, voice, haptics, DiagSink.NONE, log, clock)
    }
}

/**
 * An optional process-wide store holder. Swift normally calls `NavStore.attachPreferences` from
 * its navigation model; JVM tests inject a memory store through the constructor. A null provider
 * simply means nothing is persisted.
 */
object NavPrefsStore {
    var stores: KeyValueStores? = null
}
