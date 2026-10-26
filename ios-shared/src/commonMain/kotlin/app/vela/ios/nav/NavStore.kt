package app.vela.ios.nav

import app.vela.core.diag.DiagSink
import app.vela.core.model.Route
import app.vela.core.nav.NavSession
import app.vela.core.platform.Cancellable
import app.vela.core.platform.Clock
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice
import app.vela.ios.route.RouteStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
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
    val speedMps: Double? = null,
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
) {
    /** Arrival keeps the route and camera until Done; End clears both. */
    val active: Boolean get() = navigating || arrived
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
    voiceProvider: () -> NavVoice = { InertNavVoice },
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
                session.onLocation(
                    fix.position,
                    imperial = useImperial,
                    speedMps = fix.speedMps,
                    accuracyM = fix.accuracyM,
                    bearingDeg = fix.bearingDeg,
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

    /** Arms only the location timers. The session and its Apple seams are built on the first
     * drive, after Swift has supplied them through `MapSession.configureNavigation`. */
    fun start() {
        if (started) return
        started = true
        location.start()
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
                    return@launch
                }
                val destinationPlace = if (rs.reversed) rs.origin else rs.destination
                val display = NavSession.destinationDisplay(destinationPlace?.name, destinationPlace?.address, end)
                session.start(
                    route = route,
                    destination = end,
                    destinationLabel = display.first,
                    destinationAddress = display.second.orEmpty(),
                    mode = rs.mode,
                )
                location.navigationStarted()
                routeStore.close()
                _state.update { it.copy(starting = false) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
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
        lastRoute = null
        _state.value = NavUiState(
            latitude = location.state.value.latitude,
            longitude = location.state.value.longitude,
            speedMps = location.state.value.speedMps,
            bearingDeg = location.state.value.bearingDeg,
            fixSequence = location.state.value.fixSequence,
        )
    }

    fun setPaused(on: Boolean) {
        if (sessionCreated) session.setPaused(on)
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
        observeJob = scope.launch {
            session.state.collect { ns ->
                val routeChanged = ns.route !== lastRoute
                lastRoute = ns.route
                if (routeChanged) alerts.onRoute(ns.route)
                val step = ns.nav.stepIndex
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
                        routeRevision = old.routeRevision + if (routeChanged) 1 else 0,
                    )
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

    private fun applyLocation(location: LocationState) {
        _state.update {
            it.copy(
                latitude = location.latitude,
                longitude = location.longitude,
                speedMps = location.speedMps,
                bearingDeg = location.bearingDeg,
                fixSequence = location.fixSequence,
                starved = it.navigating && location.starved,
            )
        }
    }

    companion object {
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
