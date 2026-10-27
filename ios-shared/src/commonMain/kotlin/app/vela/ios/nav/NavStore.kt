package app.vela.ios.nav

import app.vela.core.diag.DiagSink
import app.vela.core.model.LatLng
import app.vela.core.model.Route
import app.vela.core.model.bearingTo
import app.vela.core.model.distanceTo
import app.vela.core.nav.NavSession
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice
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

/** The maneuver the driver must make next, plus the one after it for the compact "Then" row. */
data class NavManeuver(
    val index: Int,
    val type: String,
    val instruction: String,
    val distanceMeters: Double,
    val streetName: String?,
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
    private val sessionFactory: () -> NavSession,
) {
    private val _state = MutableStateFlow(NavUiState())
    val state: StateFlow<NavUiState> = _state.asStateFlow()
    private var useImperial = false

    /** Swift localizes alert speech through the String Catalog. The fallback keeps JVM tests simple. */
    var alertText: (String, Int) -> String = { kind, count ->
        when (kind) {
            NavRoadAlertKind.SPEED_CAMERA.name -> "Speed camera ahead"
            NavRoadAlertKind.ALPR_CAMERA.name -> if (count > 1) "License plate cameras ahead" else "License plate camera ahead"
            else -> "You're over the speed limit"
        }
    }

    /** A camera or speeding warning also has a haptic cue, including while the voice is muted. */
    var warningCue: () -> Unit = {}

    private val alerts = NavAlerts(
        provider = alertProvider,
        scope = scope,
        clock = clock,
        imperial = { useImperial },
        audibleAlert = { alert ->
            voiceProvider().speak(alertText(alert.kind.name, alert.count))
            warningCue()
        },
        onChange = { road ->
            _state.update {
                it.copy(
                    speedLimitKmh = road.speedLimitKmh,
                    speeding = road.speeding,
                    roadAlertKind = road.alert?.kind?.name,
                    roadAlertCount = road.alert?.count ?: 0,
                    loadedCameraGroups = road.loadedCameraGroups,
                )
            }
        },
    )

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
    private var lastFeedMs = 0L
    /** The visible stops still ahead at the previous publication, to notice a waypoint passed. */
    private var lastStopLabels: List<String> = emptyList()

    // Tunnel dead reckoning (port of NavController.tunnelDeadReckonLoop). Progress is meters along
    // the route; NaN means the loop is not reckoning.
    private var drProgressM = Double.NaN
    private var drCapM = 0.0
    private var drTotalM = 0.0
    private var drSpeed = 0.0
    private var drLastMs = 0L
    private var deadReckoning = false

    /** Arms the location timers and the tunnel estimator. The session and its Apple seams are
     * built on the first drive, after Swift has supplied them through
     * `MapSession.configureNavigation`. */
    fun start() {
        if (started) return
        started = true
        location.start()
        scope.launch { deadReckoningLoop() }
    }

    fun setImperial(on: Boolean) {
        useImperial = on
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
        if (!started || startJob?.isActive == true || _state.value.active) return
        val rs = routeStore.state.value
        val picked = rs.active ?: return
        val end = picked.polyline.lastOrNull() ?: return
        ensureObserver()
        val gen = ++generation
        _state.update { it.copy(starting = true, startFailed = false, travelMode = rs.mode.name) }
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
                _state.update { it.copy(starting = false) }
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

    fun stop() {
        generation++
        startJob?.cancel()
        startJob = null
        if (sessionCreated) session.stop()
        alerts.reset()
        location.navigationEnded()
        routeStore.close()
        trips?.finishTrip()
        lastRoute = null
        lastRecordedRoute = null
        lastFeedMs = 0L
        lastStopLabels = emptyList()
        resetDeadReckoning()
        _state.value = NavUiState(
            latitude = location.state.value.latitude,
            longitude = location.state.value.longitude,
            speedMps = location.state.value.speedMps,
            bearingDeg = location.state.value.bearingDeg,
            fixSequence = location.state.value.fixSequence,
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
        if (_state.value.navigating) _state.update { it.copy(cameraDetached = true) }
    }

    fun recenter() {
        _state.update { it.copy(cameraDetached = false) }
    }

    fun toggleNorthUp() {
        _state.update { it.copy(northUp = !it.northUp, cameraDetached = false) }
    }

    /** The active route's line as latitude, longitude pairs, empty outside a drive. */
    fun line(): DoubleArray = if (sessionCreated) RouteStore.lineOf(session.state.value.route) else DoubleArray(0)

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
                _state.update { old ->
                    old.copy(
                        navigating = ns.navigating,
                        paused = ns.paused,
                        arrived = ns.arrived,
                        maneuver = maneuver(ns, step),
                        nextManeuver = maneuver(ns, step + 1),
                        routeDistanceMeters = ns.route?.distanceMeters ?: 0.0,
                        remainingDistanceMeters = ns.remainingDistance,
                        remainingDurationSeconds = ns.remainingDuration,
                        offRoute = ns.navigating && ns.nav.offRoute,
                        trafficDelaySeconds = trafficDelay(ns),
                        fasterRouteOffered = ns.fasterRoute != null,
                        fasterSavingSeconds = ns.fasterSavingSeconds,
                        destinationLabel = ns.destinationLabel,
                        destinationAddress = ns.destinationAddress,
                        tripDistanceMeters = ns.tripDistanceMeters,
                        tripElapsedSeconds = ns.tripElapsedSeconds,
                        nextStopLabel = toStop?.label.orEmpty(),
                        nextStopDistanceMeters = toStop?.distanceM ?: 0.0,
                        nextStopSeconds = toStop?.seconds ?: 0.0,
                        stopsAhead = remainingStops.size,
                        reachedStopLabel = reachedLabel ?: old.reachedStopLabel,
                        reachedStopSerial = old.reachedStopSerial + if (reachedLabel != null) 1 else 0,
                        routeRevision = old.routeRevision + if (routeChanged) 1 else 0,
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
                }
                alerts.update(ns, _state.value.speedMps)
            }
        }
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
        )
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
    }

    companion object {
        private const val DR_START_MS = 3_500L
        private const val DR_DECAY_S = 60.0
        private const val DR_MIN_SPEED = 1.5
        private const val DR_MAX_M = 3_000.0
        private const val DR_TURN_HOLD_M = 15.0

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
