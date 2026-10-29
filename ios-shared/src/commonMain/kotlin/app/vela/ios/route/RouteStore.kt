package app.vela.ios.route

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.AlprCamera
import app.vela.core.data.ClosingTime
import app.vela.core.data.FuelGb
import app.vela.core.data.FuelGbStations
import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.RoutingPrefs
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TravelMode
import app.vela.core.model.distanceTo
import app.vela.core.nav.CameraDetour
import app.vela.core.nav.RouteProjection
import app.vela.core.platform.Cancellable
import app.vela.core.platform.KeyValueStore
import app.vela.ios.place.PlaceFuel
import app.vela.ios.place.PlaceTravelHints
import app.vela.ios.search.SearchStore
import app.vela.ios.transit.TransitPlanQuery
import kotlin.math.roundToLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.datetime.TimeZone

data class RouteState(
    val open: Boolean = false,
    val destination: Place? = null,
    /** A start chosen by hand; null starts from the user's location, else the map's center. */
    val origin: Place? = null,
    /** The trip starts from the map's center: there was no location fix and no start chosen. */
    val fromMapCenter: Boolean = false,
    /** From the place back to the start (`directionsReversed`). */
    val reversed: Boolean = false,
    /** Intermediate stops in displayed and travel order. [RouteStore.swap] reverses them too. */
    val waypoints: List<Place> = emptyList(),
    val mode: TravelMode = TravelMode.DRIVE,
    /** 0 leave now, 1 depart at, 2 arrive by. Only transit adds this to its request. */
    val timeMode: Int = 0,
    val timeEpochSec: Long? = null,
    /** The planner's vehicle numbers (0 bus, 1 subway, 2 train, 3 tram); empty means every mode. */
    val transitPrefer: Set<Int> = emptySet(),
    /** 0 best, 2 fewer transfers, 3 less walking; Transitous reorders its answers. */
    val transitRoutePref: Int = 0,
    val avoidTolls: Boolean = false,
    val avoidHighways: Boolean = false,
    val avoidFerries: Boolean = false,
    /** Bike mode prefers lanes and quiet streets (`RoutingPrefs.bikeSafe`), on by default. */
    val bikeSafe: Boolean = true,
    /** "Use Vela without Google" was on when this route set was asked for. */
    val googleOff: Boolean = false,
    /** Live traffic waits for the picker's "Show traffic" (Android's `route_traffic_on_tap`). */
    val trafficOnTap: Boolean = false,
    /** "Show traffic" was tapped for this trip: Google may answer from now on. */
    val trafficRequested: Boolean = false,
    /** "Avoid surveillance cameras" (Android's `flock_route_alert_on`), off by default. */
    val avoidCameras: Boolean = false,
    /** "Try side streets around cameras" (Android's `flock_detour`), nested under the camera choice. */
    val cameraSideStreets: Boolean = false,
    /** The camera choice can work here: a camera source is wired and the router is reachable. */
    val canAvoidCameras: Boolean = false,
    /** Cameras each route passes, aligned with [routes]; empty until the pass has counted them. */
    val cameraCounts: List<Int> = emptyList(),
    /** Cameras the shown route avoids against the route that led before the pass; 0 means none. */
    val camerasAvoided: Int = 0,
    /** Seconds the shown route adds over the fastest, when it avoids cameras; 0 otherwise. */
    val cameraDetourSeconds: Double = 0.0,
    /** Meters the shown route adds over the fastest, when it avoids cameras; 0 otherwise. */
    val cameraDetourMeters: Double = 0.0,
    /** The route that led before the pass was also the fastest one, so `fastest` is exact wording. */
    val cameraBaselineIsFastest: Boolean = false,
    /** Whether the directions template carries Google's avoid block (`DirectionsPb.avoidSupported`). */
    val avoidSupported: Boolean = false,
    /** The routes as the source returned them, never copied (PRESENTATION-MAP.md 5, trap 2). */
    val routes: List<Route> = emptyList(),
    /** One of [routes], by identity. */
    val active: Route? = null,
    /** The destination's arrival warning from its own Google status, recomputed with the route;
     *  null hides the picker's row. */
    val closingHint: ClosingTime.ArrivalWarning? = null,
    /** The cheapest fresh Fuel Finder forecourt within 500 m of [active]'s line; null hides the
     *  picker's row. */
    val fuelHint: PlaceTravelHints.FuelDetour? = null,
    val loading: Boolean = false,
    val error: RouteError? = null,
    /** The shown time of each mode for this trip: the current one's and the prefetched others'. */
    val modeSeconds: Map<TravelMode, Double> = emptyMap(),
    val showSteps: Boolean = false,
    /** Transit's answer (Transitous' planner), in its order; [routes] stays empty for transit. */
    val transit: List<TransitItinerary> = emptyList(),
    val activeTransit: Int = -1,
) {
    /** The index of [active] in [routes] (of [activeTransit] for transit), -1 when none. Swift
     *  holds this, never a route. */
    val activeIndex: Int get() = if (mode == TravelMode.TRANSIT) activeTransit else routes.indexOfFirst { it === active }

    /** [mode]'s enum name, for Swift (`DRIVE`, `WALK`, `BICYCLE`, `TRANSIT`). */
    val modeName: String get() = mode.name

    /** A drive on demand, before the tap: the picker offers "Show traffic" and no live time yet. */
    val canShowTraffic: Boolean
        get() = open && mode == TravelMode.DRIVE && trafficOnTap && !trafficRequested && !googleOff

    /** Swift reads a plain integer; 0 means leave now and no chosen time. */
    val timeEpoch: Long get() = timeEpochSec ?: 0L
    val canAddWaypoint: Boolean get() = waypoints.size < RouteStore.MAX_WAYPOINTS

    val prefersBus: Boolean get() = 0 in transitPrefer
    val prefersSubway: Boolean get() = 1 in transitPrefer
    val prefersTrain: Boolean get() = 2 in transitPrefer
    val prefersTram: Boolean get() = 3 in transitPrefer

    /** The time known for the mode called [modeName] on this trip, -1 when none. */
    fun secondsOf(modeName: String): Double =
        modeSeconds.entries.firstOrNull { it.key.name == modeName }?.value ?: -1.0

    /** The chooser's rows, in [routes] order. */
    fun rows(): List<RouteRow> = routes.mapIndexed { i, r ->
        RouteRow(
            seconds = r.durationInTrafficSeconds ?: r.durationSeconds,
            meters = r.distanceMeters,
            via = r.summary?.takeIf { it.isNotBlank() },
            delaySeconds = RouteStore.trafficDelaySeconds(r),
            hasTraffic = r.hasLiveTraffic,
            typicalLowSeconds = r.typicalRangeSeconds?.first,
            typicalHighSeconds = r.typicalRangeSeconds?.second,
            cameras = cameraCounts.getOrNull(i),
        )
    }

    /** The steps of [active]. */
    fun steps(): List<StepRow> = active?.maneuvers.orEmpty().map { m ->
        StepRow(
            kind = m.type.name,
            instruction = m.instruction,
            meters = m.distanceMeters,
            road = m.road,
            ref = m.ref,
            laneHint = m.laneHint,
            lanes = m.lanes.map { LaneRow(it.indications.joinToString(","), it.valid) },
            exit = m.roundaboutExit ?: -1,
            lat = m.location.lat,
            lng = m.location.lng,
        )
    }

    /** The transit itineraries as the chooser lists them. */
    fun transitRows(): List<TransitRow> = transit.map { t ->
        TransitRow(
            departText = t.departureText,
            arriveText = t.arrivalText,
            durationText = t.durationText,
            seconds = RouteStore.transitSeconds(t) ?: -1.0,
            legs = t.steps.map { st ->
                TransitLegRow(
                    kind = st.mode.name,
                    line = st.line?.name,
                    color = st.line?.colorHex,
                    textColor = st.line?.textColorHex,
                    durationText = st.durationText,
                    departText = st.departText,
                    arriveText = st.arriveText,
                    from = st.boardStop?.name,
                    to = st.alightStop?.name,
                    headsign = st.headsign,
                    stops = st.numStops ?: -1,
                    delayText = st.delayText,
                )
            },
        )
    }
}

/** One lane of a maneuver: its arrows (`left,straight`) and whether it is a lane to use. */
data class LaneRow(val indications: String, val valid: Boolean)

/** One transit itinerary in the chooser: its times as the planner wrote them, its length in
 *  seconds (-1 unknown) and its legs. */
data class TransitRow(val departText: String?, val arriveText: String?, val durationText: String?, val seconds: Double, val legs: List<TransitLegRow>)

/** One walk or ride: [kind] is the `TransitMode` name; [stops] is -1 when unknown. */
data class TransitLegRow(
    val kind: String, val line: String?, val color: String?, val textColor: String?, val durationText: String?,
    val departText: String?, val arriveText: String?, val from: String?, val to: String?, val headsign: String?,
    val stops: Int, val delayText: String?,
)

/** One route in the chooser: its shown time (live when known), length, Google's "via", how much
 *  traffic adds and its typical range for a future departure estimate. Numbers only; Swift formats them. */
data class RouteRow(
    val seconds: Double,
    val meters: Double,
    val via: String?,
    val delaySeconds: Double,
    val hasTraffic: Boolean,
    val typicalLowSeconds: Double? = null,
    val typicalHighSeconds: Double? = null,
    /** Cameras this route passes, null until the camera pass counted them. */
    val cameras: Int? = null,
)

/** One step: the maneuver's `ManeuverType` name, the router's text, the meters to the next step,
 *  and the maneuver's own point so the map can focus it from the list. */
data class StepRow(
    val kind: String, val instruction: String, val meters: Double, val road: String?, val ref: String?,
    val laneHint: String?, val lanes: List<LaneRow>, val exit: Int, val lat: Double, val lng: Double,
)

sealed interface RouteError {
    /** No start: no location fix, no map center, no start chosen. */
    data object NoOrigin : RouteError

    /** `mapvm_no_mode_route_found`. */
    data class NoRoute(val mode: TravelMode) : RouteError

    /** Transit without a planner. */
    data class ModeUnavailable(val mode: TravelMode) : RouteError

    /** `mapvm_directions_need_recalibration`. */
    data class NeedsRecalibration(val where: String?) : RouteError

    /** `mapvm_routing_failed_reason`. */
    data class Failed(val reason: String?) : RouteError
}

/** One intermediate stop of an incoming directions link: the name to show, already resolved to a
 *  point by the caller. */
data class LinkStop(val name: String, val lat: Double, val lng: Double)

/** One stretch of live traffic along a drawn line: Google's level (1 moderate, 2 heavy, 3+
 *  severe) and its points as `lat, lng` pairs. */
class TrafficLine(val level: Int, val points: DoubleArray)

/**
 * The directions facet of the map (docs/ios/PRESENTATION-MAP.md 3.3): the chooser of Android's
 * `MapViewModel` on Google's routes alone (SPEC 2.5, C-2). From the place sheet's Directions to a
 * route set per mode, the alternates, the selection by identity, the avoid toggles, the reverse
 * and a chosen start; the other modes' times are fetched after the current one, as the mode
 * chips show them.
 *
 * The constructor does nothing; [start] reads the sticky preferences. Every intent is meant for
 * the [scope]'s thread (the main thread on iOS).
 */
class RouteStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
    /** `vela_settings`, the same keys as Android; null keeps nothing across launches. */
    private val settings: () -> KeyValueStore? = { null },
    private val avoidSupported: () -> Boolean = { false },
    private val now: () -> Long = { 0L },
    /** Transitous' planner with leave/depart/arrive options; null leaves transit unavailable. */
    private val transitPlanner: (suspend (LatLng, LatLng, Int, Long?) -> List<TransitItinerary>)? = null,
    /** Transitous with the chooser's time, vehicle and preference options; preferred when set. */
    private val transitOptionsPlanner: (suspend (LatLng, LatLng, TransitPlanQuery) -> List<TransitItinerary>)? = null,
    /** On by default: iOS has no Settings row for "Live traffic only when I tap" yet, and L117
     *  asks the picker itself for the gate. A stored `route_traffic_on_tap` still wins. */
    private val trafficOnTapDefault: Boolean = true,
    /** ALPR cameras near a route's line (Overpass on iOS); null leaves the camera choice hidden. */
    private val camerasAlong: (suspend (List<LatLng>) -> List<AlprCamera>)? = null,
    /** Whether the router and the camera source are reachable: offline hides the camera choice
     *  instead of offering a detour iOS cannot plan. */
    private val online: () -> Boolean = { true },
    /** Fuel Finder forecourts for the picker's detour hint; null falls back to the process graph
     *  ([PlaceFuel.source]). Tests hand the parsed file directly, so no file is downloaded. */
    private val fuel: (suspend () -> FuelGbStations?)? = null,
) {
    private val _state = MutableStateFlow(RouteState())
    val state: StateFlow<RouteState> = _state.asStateFlow()

    private var started = false
    private var myLocation: LatLng? = null
    private var mapCenter: LatLng? = null
    private var routeJob: Job? = null
    private var etaJob: Job? = null
    private var namingJob: Job? = null
    private var cameraJob: Job? = null
    private var hintJob: Job? = null
    private var generation = 0

    /** One Fuel Finder store per process, so the parsed file stays in memory; the picker never
     *  downloads it outside the UK. */
    private val fuelLoader: (suspend () -> FuelGbStations?)? by lazy {
        fuel ?: PlaceFuel.source(now)?.let { src ->
            val load: suspend () -> FuelGbStations? = { src.load() }
            load
        }
    }
    private var etaKey: String? = null
    private val etaCache = mutableMapOf<String, MutableMap<TravelMode, Double>>()

    fun start() {
        if (started) return
        started = true
        val p = runCatching { settings() }.getOrNull()
        val mode = p?.let { runCatching { it.getString(KEY_MODE, null)?.let(TravelMode::valueOf) }.getOrNull() }
        val onTap = p?.let {
            runCatching { it.getBoolean(KEY_TRAFFIC_ON_TAP, trafficOnTapDefault) }.getOrNull()
        } ?: trafficOnTapDefault
        val avoidCameras = p.bool(KEY_AVOID_CAMERAS)
        val cameraSideStreets = p.bool(KEY_CAMERA_SIDE_STREETS)
        _state.update {
            it.copy(
                mode = mode ?: TravelMode.DRIVE,
                avoidTolls = p.bool(KEY_TOLLS),
                avoidHighways = p.bool(KEY_HIGHWAYS),
                avoidFerries = p.bool(KEY_FERRIES),
                bikeSafe = p.bool(KEY_BIKE_SAFE, default = true),
                googleOff = NoGoogle.enabled,
                trafficOnTap = onTap,
                avoidCameras = avoidCameras,
                cameraSideStreets = cameraSideStreets,
                canAvoidCameras = camerasAvailable(),
            )
        }
        syncRoutingAvoid()
        RoutingPrefs.bikeSafe = _state.value.bikeSafe
    }

    // port of MapViewModel.directionsTo and routeToSelected (Google only, no stops or links)
    /** Opens the chooser to [p] from the user's location, on the sticky mode and avoids. */
    fun directionsTo(p: Place) {
        if (!started) return
        _state.update {
            it.copy(
                open = true, destination = p, origin = null, reversed = false, waypoints = emptyList(),
                timeMode = 0, timeEpochSec = null, trafficRequested = false,
                routes = emptyList(), active = null, error = null, showSteps = false, modeSeconds = emptyMap(),
                avoidSupported = runCatching { avoidSupported() }.getOrDefault(false),
            )
        }
        route()
    }

    /** Opens the chooser for an incoming directions link: [to] is the destination, [origin] a start
     *  the link named (null starts from here), and [mode] the link's travel mode. Unlike
     *  [setModeNamed] the mode is not persisted, so the link's choice does not become the user's. */
    fun directionsFrom(origin: Place?, to: Place, mode: TravelMode?) {
        directionsWithStops(origin, to, mode, emptyList())
    }

    /** [directionsFrom] with the link's intermediate stops already resolved, in travel order. The
     *  stops replace any previous trip's, and only the first [MAX_WAYPOINTS] are kept. */
    fun directionsWithStops(origin: Place?, to: Place, mode: TravelMode?, stops: List<Place>) {
        if (!started) return
        _state.update {
            it.copy(
                open = true, destination = to, origin = origin, reversed = false,
                waypoints = stops.take(MAX_WAYPOINTS), trafficRequested = false,
                routes = emptyList(), active = null, error = null, showSteps = false, modeSeconds = emptyMap(),
                mode = mode ?: it.mode,
                avoidSupported = runCatching { avoidSupported() }.getOrDefault(false),
            )
        }
        route()
    }

    /** [directionsFrom] by the mode's enum name, for Swift; an unknown or nil name keeps the mode. */
    fun directionsFromNamed(origin: Place?, to: Place, modeName: String?) {
        directionsFrom(origin, to, modeName?.let { n -> TravelMode.entries.firstOrNull { it.name == n } })
    }

    /** An incoming directions link by its raw values, so Swift constructs no KMP model. A false
     *  [hasOrigin] starts from the user's location, as a link with no start does. */
    fun directionsFromPoint(
        name: String, lat: Double, lng: Double,
        originName: String, originLat: Double, originLng: Double, hasOrigin: Boolean,
        modeName: String?,
    ) {
        openIncomingPoint(name, lat, lng, originName, originLat, originLng, hasOrigin, modeName, emptyList())
    }

    /** [directionsFromPoint] with the link's stops, already resolved and in travel order. A stop
     *  with a blank name or an unusable coordinate opens nothing, so a link can never become a
     *  trip with a stop silently dropped. */
    fun directionsFromPointWithStops(
        name: String, lat: Double, lng: Double,
        originName: String, originLat: Double, originLng: Double, hasOrigin: Boolean,
        modeName: String?,
        stops: List<LinkStop>,
    ) {
        if (stops.any { it.name.isBlank() || it.lat !in -90.0..90.0 || it.lng !in -180.0..180.0 }) {
            return
        }
        val places = stops.map {
            Place(
                id = "link-stop:${it.lat},${it.lng}",
                name = it.name,
                location = LatLng(it.lat, it.lng))
        }
        openIncomingPoint(name, lat, lng, originName, originLat, originLng, hasOrigin, modeName, places)
    }

    private fun openIncomingPoint(
        name: String, lat: Double, lng: Double,
        originName: String, originLat: Double, originLng: Double, hasOrigin: Boolean,
        modeName: String?, stops: List<Place>,
    ) {
        if (name.isBlank() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        val destination = Place(id = "link:$lat,$lng", name = name, location = LatLng(lat, lng))
        val origin = if (hasOrigin && originLat in -90.0..90.0 && originLng in -180.0..180.0) {
            Place(
                id = "link:$originLat,$originLng",
                name = originName.ifBlank { name },
                location = LatLng(originLat, originLng))
        } else {
            null
        }
        directionsWithStops(origin, destination, modeName?.let { n -> TravelMode.entries.firstOrNull { it.name == n } }, stops)
    }

    // port of MapViewModel.setTravelMode
    fun setMode(mode: TravelMode) {
        if (_state.value.mode == mode) return
        settings()?.edit()?.putString(KEY_MODE, mode.name)?.apply()
        _state.update { it.copy(mode = mode, showSteps = false) }
        route()
    }

    /** [setMode] by the enum name, for Swift; an unknown name does nothing. */
    fun setModeNamed(name: String) {
        TravelMode.entries.firstOrNull { it.name == name }?.let(::setMode)
    }

    // port of MapViewModel.setAvoidTolls, setAvoidHighways, setAvoidFerries
    fun setAvoidTolls(on: Boolean) = setAvoid(KEY_TOLLS, on) { it.copy(avoidTolls = on) }
    fun setAvoidHighways(on: Boolean) = setAvoid(KEY_HIGHWAYS, on) { it.copy(avoidHighways = on) }
    fun setAvoidFerries(on: Boolean) = setAvoid(KEY_FERRIES, on) { it.copy(avoidFerries = on) }

    // port of the Android BikeSafe setting: saved in vela_settings under the same key
    /** On: bike routes are safety-weighted (Valhalla `use_roads` 0.1); off: the fastest bike route.
     *  The flag lives in `RoutingPrefs` for every fetch, the way Android's `BikeSafe` mirrors it. */
    fun setBikeSafe(on: Boolean) {
        val before = _state.value
        if (before.bikeSafe == on) return
        settings()?.edit()?.putBoolean(KEY_BIKE_SAFE, on)?.apply()
        _state.update { it.copy(bikeSafe = on) }
        RoutingPrefs.bikeSafe = on
        if (before.open && before.mode == TravelMode.BICYCLE) route()
    }

    /** The bike profile as the store holds it, for a Settings row outside the chooser. */
    fun bikeSafeEnabled(): Boolean = _state.value.bikeSafe

    /** "Show traffic" tapped: this trip may now ask Google for its live ETA and spans. Google off
     *  stays off: the tap never flips a privacy choice, it only opens the traffic gate. */
    fun requestTraffic() {
        val s = _state.value
        if (!s.open || s.mode != TravelMode.DRIVE || !s.trafficOnTap || s.trafficRequested) return
        if (NoGoogle.enabled) return
        _state.update { it.copy(trafficRequested = true, googleOff = NoGoogle.enabled) }
        syncRouteTraffic()
        etaCache.clear()
        route()
    }

    /** A future Settings row: live traffic at once, or only after the picker's tap. Persisted
     *  under Android's key so both apps read one preference. */
    fun setTrafficOnTap(on: Boolean) {
        val before = _state.value
        if (before.trafficOnTap == on) return
        settings()?.edit()?.putBoolean(KEY_TRAFFIC_ON_TAP, on)?.apply()
        _state.update { it.copy(trafficOnTap = on) }
        syncRouteTraffic()
        if (before.open && before.mode == TravelMode.DRIVE) route()
    }

    /** The picker's "Avoid cameras" chip (L109). Updating the routes re-counts and re-ranks them;
     *  the preference is stored under Android's `flock_route_alert_on`. */
    fun setAvoidCameras(on: Boolean) {
        val before = _state.value
        if (before.avoidCameras == on) return
        settings()?.edit()?.putBoolean(KEY_AVOID_CAMERAS, on)?.apply()
        _state.update {
            it.copy(
                avoidCameras = on,
                cameraCounts = if (on) it.cameraCounts else emptyList(),
                camerasAvoided = 0,
                cameraDetourSeconds = 0.0,
                cameraDetourMeters = 0.0,
                cameraBaselineIsFastest = false,
            )
        }
        if (!on) cameraJob?.cancel()
        if (before.open && before.mode != TravelMode.TRANSIT) route()
    }

    /** The "Try side streets around cameras" switch (L203), nested under [setAvoidCameras]. It
     *  costs extra route requests, so it stays off until asked, as Android's `flock_detour`. */
    fun setCameraSideStreets(on: Boolean) {
        val before = _state.value
        if (before.cameraSideStreets == on) return
        settings()?.edit()?.putBoolean(KEY_CAMERA_SIDE_STREETS, on)?.apply()
        _state.update { it.copy(cameraSideStreets = on) }
        if (before.open && before.mode == TravelMode.DRIVE && before.avoidCameras) route()
    }

    /** Traffic follows the trip's choice: a drive on demand asks Google only after the tap; every
     *  other mode keeps the sources it had. Navigation reopens the gate at Start. */
    private fun syncRouteTraffic() {
        val s = _state.value
        RoutingPrefs.googleTraffic = s.mode != TravelMode.DRIVE || !s.trafficOnTap || s.trafficRequested
    }

    /** Navigation keeps its own live re-checks: a drive started from an on-demand trip turns
     *  Google traffic back on for the session (L297's separate switch owns that policy). */
    fun prepareNavigation() {
        RoutingPrefs.googleTraffic = true
    }

    // port of MapViewModel.setDirectionsTime (only transit sends the chosen time to its planner)
    /** 0 leave now, 1 depart at [epochSec], 2 arrive by [epochSec]. A future drive has no keyless
     *  request field, so only transit re-plans. */
    fun setTime(mode: Int, epochSec: Long) {
        if (mode !in 0..2) return
        val before = _state.value
        val epoch = if (mode == 0) null else epochSec.takeIf { it > 0 }
        val nextMode = if (epoch == null) 0 else mode
        if (before.timeMode == nextMode && before.timeEpochSec == epoch) return
        _state.update { it.copy(timeMode = nextMode, timeEpochSec = epoch) }
        if (before.open && before.mode == TravelMode.TRANSIT) route()
    }

    // port of MapViewModel.setTransitPrefer (the planner's own transitModes filter)
    /** Bus (0), subway (1), train (2) and tram (3) as Transitous names them. FERRY has no planner
     *  mode and is never sent; an empty selection asks for every mode. */
    fun setTransitPreferFlags(bus: Boolean, subway: Boolean, train: Boolean, tram: Boolean) {
        val modes = TransitPlanQuery.flags(bus, subway, train, tram)
        val before = _state.value
        if (before.transitPrefer == modes) return
        _state.update { it.copy(transitPrefer = modes) }
        if (before.open && before.mode == TravelMode.TRANSIT) route()
    }

    // port of MapViewModel.setTransitRoutePref (Transitous answers are reordered, not filtered)
    /** 0 best, 2 fewer transfers, 3 less walking. The endpoint has no such parameter. */
    fun setTransitRoutePreference(pref: Int) {
        if (!TransitPlanQuery.acceptsRoutePreference(pref)) return
        val before = _state.value
        if (before.transitRoutePref == pref) return
        _state.update { it.copy(transitRoutePref = pref) }
        if (before.open && before.mode == TravelMode.TRANSIT) route()
    }

    // port of MapViewModel.swapDirections
    /** Reverses both ends and the stops, so display order remains travel order. */
    fun swap() {
        if (!_state.value.open) return
        _state.update { it.copy(reversed = !it.reversed, waypoints = it.waypoints.reversed()) }
        route()
    }

    // port of MapViewModel.setDirectionsOrigin
    /** Sets the model's base start; null goes back to the user's location. */
    fun setOrigin(p: Place?) {
        if (!_state.value.open) return
        _state.update { it.copy(origin = p) }
        route()
    }

    /** Sets the start as displayed, including after a swap. A reversed trip is first represented
     *  forward with the same two ends, so editing its start cannot accidentally edit its destination. */
    fun setStart(p: Place?) {
        val s = _state.value
        if (!s.open) return
        if (!s.reversed) {
            setOrigin(p)
            return
        }
        val oldDestination = s.origin ?: currentPlace() ?: return
        _state.update {
            it.copy(destination = oldDestination, origin = it.destination, reversed = false)
        }
        setOrigin(p)
    }

    /** Swift's saved-place and pin rows need no Kotlin `Place` constructor. */
    fun setStartPlace(id: String, name: String, address: String?, lat: Double, lng: Double) {
        setStart(Place(id = id, name = name, address = address, location = LatLng(lat, lng)))
    }

    fun setStartToMapCenter() {
        val at = mapCenter ?: return
        setStart(Place(id = "pin:${at.lat},${at.lng}", name = "Dropped pin", location = at))
    }

    // port of MapViewModel.addStop and applyStops (planning only)
    fun addWaypoint(p: Place) {
        val s = _state.value
        if (!s.open || s.waypoints.size >= MAX_WAYPOINTS) return
        _state.update { it.copy(waypoints = it.waypoints + p) }
        route()
    }

    fun addWaypointPlace(id: String, name: String, address: String?, lat: Double, lng: Double) {
        addWaypoint(Place(id = id, name = name, address = address, location = LatLng(lat, lng)))
    }

    fun addWaypointAtMapCenter() {
        val at = mapCenter ?: return
        addWaypoint(Place(id = "pin:${at.lat},${at.lng}", name = "Dropped pin", location = at))
    }

    /** Moves the stop at [from] to final index [to] and replans once. */
    fun moveWaypoint(from: Int, to: Int) {
        val s = _state.value
        if (!s.open || from !in s.waypoints.indices || to !in s.waypoints.indices || from == to) return
        val stops = s.waypoints.toMutableList()
        stops.add(to, stops.removeAt(from))
        _state.update { it.copy(waypoints = stops) }
        route()
    }

    fun removeWaypoint(index: Int) {
        val s = _state.value
        if (!s.open || index !in s.waypoints.indices) return
        _state.update { it.copy(waypoints = it.waypoints.filterIndexed { i, _ -> i != index }) }
        route()
    }


    /** A place search private to the endpoint and stop picker; it does not replace map search state. */
    suspend fun findPlaces(query: String): List<Place> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        val near = SearchStore.plausibleBias(mapCenter) ?: SearchStore.plausibleBias(myLocation)
        return source().search(q, near = near, rankFrom = myLocation).places
    }

    private fun currentPlace(): Place? {
        val at = myLocation ?: mapCenter ?: return null
        val name = if (myLocation != null) "Your location" else "Dropped pin"
        return Place(id = "current:${at.lat},${at.lng}", name = name, location = at)
    }

    // port of MapViewModel.selectRoute (Google's routes are never provisional here)
    fun select(index: Int) {
        if (_state.value.mode == TravelMode.TRANSIT) {
            if (index in _state.value.transit.indices) _state.update { it.copy(activeTransit = index) }
            return
        }
        val picked = _state.value.routes.getOrNull(index) ?: return
        _state.update { it.copy(active = picked) }
        // The alternate's own time decides whether the destination closes before the arrival, and
        // its own line whether a forecourt sits on it.
        publishHints(generation, picked)
        if (!picked.provisional) return
        // A provisional Google alternate (line and time only) is named the moment it is picked,
        // so its steps are there by Start; replaced by identity, never by index.
        namingJob?.cancel()
        val s = _state.value
        namingJob = scope.launch {
            val named = nameIfNeeded(picked, s)
            _state.update { st ->
                val at = st.routes.indexOfFirst { it === picked }
                if (at < 0) return@update st
                val routes = st.routes.toMutableList().also { it[at] = named }
                st.copy(routes = routes, active = if (st.active === picked) named else st.active)
            }
        }
    }

    // port of MapViewModel.nameIfNeeded
    private suspend fun nameIfNeeded(route: Route, s: RouteState): Route {
        if (!route.provisional) return route
        val o = route.polyline.firstOrNull() ?: return route.copy(provisional = false)
        val d = route.polyline.lastOrNull() ?: return route.copy(provisional = false)
        return try {
            source().nameRoute(route, o, d, s.mode, s.avoidTolls, s.avoidHighways, s.avoidFerries)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            route.copy(provisional = false)
        }
    }

    fun showSteps(on: Boolean) {
        _state.update { it.copy(showSteps = on && (it.active != null || it.activeTransit >= 0)) }
    }

    fun retry() {
        if (_state.value.open) route()
    }

    // port of MapViewModel.clearRoute
    fun close() {
        routeJob?.cancel()
        namingJob?.cancel()
        etaJob?.cancel()
        cameraJob?.cancel()
        hintJob?.cancel()
        etaKey = null
        generation++
        _state.update {
            it.copy(
                open = false, destination = null, origin = null, fromMapCenter = false, reversed = false,
                waypoints = emptyList(), timeMode = 0, timeEpochSec = null, trafficRequested = false,
                routes = emptyList(), active = null, closingHint = null, fuelHint = null,
                loading = false, error = null, modeSeconds = emptyMap(),
                showSteps = false, transit = emptyList(), activeTransit = -1,
                cameraCounts = emptyList(), camerasAvoided = 0, cameraDetourSeconds = 0.0,
                cameraDetourMeters = 0.0, cameraBaselineIsFastest = false,
            )
        }
        // The gate belongs to the chooser, not to the drive that may start next: navigation keeps
        // its own re-checks.
        RoutingPrefs.googleTraffic = true
    }

    fun onLocation(lat: Double, lng: Double) {
        myLocation = LatLng(lat, lng)
    }

    fun onMapCenter(lat: Double, lng: Double) {
        mapCenter = LatLng(lat, lng)
    }

    /** Intermediate stops in travel order as `lat, lng` pairs for the map. */
    fun waypointPoints(): DoubleArray {
        val pts = _state.value.waypoints.map { it.location }
        val out = DoubleArray(pts.size * 2)
        pts.forEachIndexed { i, p -> out[2 * i] = p.lat; out[2 * i + 1] = p.lng }
        return out
    }

    /** The drawn line of route [index] as `lat, lng` pairs, empty for no such route. */
    fun line(index: Int): DoubleArray {
        val s = _state.value
        return if (s.mode == TravelMode.TRANSIT) transitLineOf(s.transit.getOrNull(index)) else lineOf(s.routes.getOrNull(index))
    }

    /** Route [index]'s traffic spans placed on its drawn line. */
    fun trafficLines(index: Int): List<TrafficLine> {
        if (_state.value.mode == TravelMode.TRANSIT) return emptyList()
        val r = _state.value.routes.getOrNull(index) ?: return emptyList()
        return trafficOn(r)
    }

    /** See [SearchStore.watch]. */
    fun watch(onChange: (RouteState) -> Unit): Cancellable {
        val job = scope.launch { state.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    private fun setAvoid(key: String, on: Boolean, apply: (RouteState) -> RouteState) {
        val before = _state.value
        val after = apply(before)
        if (after == before) return
        settings()?.edit()?.putBoolean(key, on)?.apply()
        _state.value = after
        syncRoutingAvoid()
        if (after.open && after.mode == TravelMode.DRIVE) route()
    }

    // port of MapViewModel.syncRoutingAvoid
    private fun syncRoutingAvoid() {
        val s = _state.value
        RoutingPrefs.avoidTolls = s.avoidTolls
        RoutingPrefs.avoidHighways = s.avoidHighways
        RoutingPrefs.avoidFerries = s.avoidFerries
    }

    // port of MapViewModel.route (transit through Transitous alone: Google's page is a WebView)
    private fun route() {
        val s = _state.value
        if (!s.open) return
        val place = s.destination?.location ?: return
        syncRouteTraffic()
        routeJob?.cancel()
        namingJob?.cancel()
        cameraJob?.cancel()
        hintJob?.cancel()
        val gen = ++generation
        val fix = s.origin?.location ?: SearchStore.plausibleBias(myLocation)
        // The map's center only when it is not the place itself (a picked result is centered).
        val from = fix ?: SearchStore.plausibleBias(mapCenter)?.takeIf { it.distanceTo(place) > CENTER_MIN_M }
        if (from == null) {
            _state.update {
                it.copy(
                    loading = false, routes = emptyList(), active = null, error = RouteError.NoOrigin,
                    closingHint = null, fuelHint = null,
                )
            }
            return
        }
        val origin = if (s.reversed) place else from
        val dest = if (s.reversed) from else place
        val stops = s.waypoints.map { it.location }
        val key = etaKeyOf(origin, dest, stops, s)
        beginModeEtas(key)
        val mode = s.mode
        _state.update { it.copy(googleOff = NoGoogle.enabled, fromMapCenter = fix == null, routes = emptyList(), active = null, closingHint = null, fuelHint = null, showSteps = false, transit = emptyList(), activeTransit = -1, cameraCounts = emptyList(), camerasAvoided = 0, cameraDetourSeconds = 0.0, cameraDetourMeters = 0.0, cameraBaselineIsFastest = false) }
        val planner = transitOptionsPlanner ?: transitPlanner
        if (mode == TravelMode.TRANSIT && planner == null) {
            _state.update { it.copy(loading = false, error = RouteError.ModeUnavailable(mode)) }
            prefetchModeEtas(key, origin, dest, stops, s, except = mode)
            return
        }
        _state.update { it.copy(loading = true, error = null) }
        fun stillWanted() = gen == generation && _state.value.open && _state.value.mode == mode
        routeJob = scope.launch {
            try {
                if (mode == TravelMode.TRANSIT && planner != null) {
                    // port of MapViewModel.routeTransit
                    // Transitous has no intermediate-stop parameter; stops remain stored for the other modes.
                    val trips = planTransit(origin, dest, s)
                    if (!stillWanted()) return@launch
                    _state.update {
                        it.copy(
                            loading = false, transit = trips, activeTransit = if (trips.isEmpty()) -1 else 0,
                            error = if (trips.isEmpty()) RouteError.NoRoute(mode) else null,
                        )
                    }
                    trips.firstOrNull()?.let(::transitSeconds)?.let { publishModeEta(key, mode, it) }
                    prefetchModeEtas(key, origin, dest, stops, s, except = mode)
                    return@launch
                }
                val routes = if (mode == TravelMode.BICYCLE && BikeProfileFixture.enabled) {
                    BikeProfileFixture.routes(origin, dest, s.bikeSafe)
                } else {
                    source().directions(origin, dest, mode, stops, s.avoidTolls, s.avoidHighways, s.avoidFerries)
                }
                if (!stillWanted()) return@launch
                _state.update {
                    it.copy(
                        loading = false,
                        routes = routes,
                        active = routes.firstOrNull(),
                        error = if (routes.isEmpty()) RouteError.NoRoute(mode) else null,
                    )
                }
                shownDuration(routes)?.let { publishModeEta(key, mode, it) }
                publishHints(gen, routes.firstOrNull())
                prefetchModeEtas(key, origin, dest, stops, s, except = mode)
                // The fastest can be a provisional alternate: named now, so the preview is the drive.
                if (routes.firstOrNull()?.provisional == true) select(0)
                cameraPass(gen, origin, dest, stops, s, routes)
            } catch (e: CancellationException) {
                throw e
            } catch (e: CalibrationNeededException) {
                if (stillWanted()) fail(RouteError.NeedsRecalibration(e.message))
            } catch (e: Exception) {
                if (stillWanted()) fail(RouteError.Failed(e.message))
            }
        }
    }

    private fun fail(error: RouteError) {
        _state.update {
            it.copy(
                loading = false, routes = emptyList(), active = null, error = error,
                closingHint = null, fuelHint = null,
            )
        }
    }

    /**
     * The picker's two travel hints for [route]: the destination's arrival warning, and the
     * cheapest forecourt within 500 m of the line. Both come from real data only: a place with no
     * parsable closing status, a drive whose arrival is more than an hour before it, a file past
     * its freshness window, and a route outside the Fuel Finder area all leave their row hidden.
     * A newer request or a picked alternate cancels the previous pass, so a hint never outlives
     * the route it was computed for.
     */
    private fun publishHints(gen: Int, route: Route?) {
        val s = _state.value
        val destination = if (s.reversed) s.origin else s.destination
        val seconds = route?.let { it.durationInTrafficSeconds ?: it.durationSeconds } ?: 0.0
        val nowSec = now() / 1000L
        val warning = if (route == null || destination == null) {
            null
        } else {
            PlaceTravelHints.closingWarning(
                name = destination.name,
                statusText = destination.statusText,
                openNow = when (destination.openNow) {
                    true -> 1
                    false -> 0
                    null -> -1
                },
                arrivalEpochSec = nowSec + seconds.toLong(),
                nowEpochSec = nowSec,
                zoneId = TimeZone.currentSystemDefault().id,
            )
        }
        _state.update { if (gen == generation) it.copy(closingHint = warning) else it }
        hintJob?.cancel()
        val polyline = route?.polyline ?: return
        // The Fuel Finder file covers Great Britain. Outside it the hint stays hidden and no file
        // is downloaded at all.
        if (s.mode != TravelMode.DRIVE || !inFuelArea(polyline)) return
        val loader = fuelLoader ?: return
        hintJob = scope.launch {
            val data = try {
                loader()
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            } ?: return@launch
            if (gen != generation) return@launch
            val hint = PlaceTravelHints.fuelDetour(polyline, data, now() / 1000L)
            if (gen != generation) return@launch
            _state.update { if (gen == generation) it.copy(fuelHint = hint) else it }
        }
    }

    private fun inFuelArea(polyline: List<LatLng>): Boolean =
        polyline.firstOrNull()?.let { FuelGb.inUk(it) } == true ||
            polyline.lastOrNull()?.let { FuelGb.inUk(it) } == true

    /** The camera choice is offered only when a camera source is wired and the router can be
     *  reached: an offline iOS build has no local router, so it hides the option rather than
     *  promising a detour it cannot plan. Google's state is irrelevant: the cameras come from
     *  OpenStreetMap's Overpass, which works with "Use Vela without Google". */
    private fun camerasAvailable(): Boolean =
        camerasAlong != null && runCatching { online() }.getOrDefault(false)

    /** Counts the cameras on each route, re-ranks to a lighter route inside [CameraDetour.cap] and,
     *  when asked, tries the side streets. Runs after the routes are shown, off the first paint. */
    private fun cameraPass(
        gen: Int, origin: LatLng, dest: LatLng, stops: List<LatLng>, state: RouteState, routes: List<Route>,
    ) {
        cameraJob?.cancel()
        val available = camerasAvailable()
        _state.update { it.copy(canAvoidCameras = available) }
        if (!available || !state.avoidCameras || state.mode == TravelMode.TRANSIT || routes.isEmpty()) {
            _state.update {
                it.copy(cameraCounts = emptyList(), camerasAvoided = 0, cameraDetourSeconds = 0.0,
                    cameraDetourMeters = 0.0, cameraBaselineIsFastest = false)
            }
            return
        }
        cameraJob = scope.launch {
            try {
                planCameraRoutes(gen, origin, dest, stops, state, routes)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // A camera source failure leaves the routes as they are and claims nothing.
            }
        }
    }

    private suspend fun planCameraRoutes(
        gen: Int, origin: LatLng, dest: LatLng, stops: List<LatLng>, state: RouteState,
        routes: List<Route>,
    ) {
        val provider = camerasAlong ?: return
        fun eta(r: Route): Double = r.durationInTrafficSeconds ?: r.durationSeconds
        val counts = routes.map { CameraDetour.count(it.polyline, provider(it.polyline)) }
        if (!stillWanted(gen, routes)) return
        val fastestIndex = routes.indices.minByOrNull { eta(routes[it]) } ?: 0
        val eta0 = eta(routes[fastestIndex])
        val cap = CameraDetour.cap(eta0)
        // The route the user would have led with without the preference: the baseline the avoided
        // count and the added time are measured against.
        val baseRoute = routes[0]
        val baseCount = counts[0]
        var list = routes
        var aligned = counts
        val best = CameraDetour.choose(
            counts.mapIndexed { i, c -> CameraDetour.Option(c, eta(routes[i])) }, eta0, cap)
        if (best != null) {
            list = CameraDetour.lead(routes, best)
            aligned = CameraDetour.lead(counts, best)
        }
        if (state.cameraSideStreets && state.mode == TravelMode.DRIVE && aligned.any { it > 0 }) {
            val budget = intArrayOf(CameraDetour.MAX_REQUESTS)
            val tried = ArrayList<LatLng>()
            val found = ArrayList<Pair<Route, Int>>()
            for (i in list.indices) {
                if (budget[0] <= 0) break
                if (aligned[i] <= 0) continue
                val r = tryCameraDetour(
                    list[i], aligned[i], eta0, cap, gen, origin, dest, stops, state, budget, tried,
                ) ?: continue
                if (!stillWanted(gen, routes)) return
                found += r
            }
            if (found.isNotEmpty()) {
                val options = listOf(CameraDetour.Option(aligned[0], eta(list[0]))) +
                    found.map { (r, n) -> CameraDetour.Option(n, eta(r)) }
                val pick = CameraDetour.choose(options, eta0, cap)
                if (pick != null) {
                    val (kept, n) = found[pick - 1]
                    // A router that answered with the road it was already on made no detour.
                    if (!CameraDetour.sameRoute(baseRoute.polyline, kept.polyline)) {
                        list = listOf(kept) + list
                        aligned = listOf(n) + aligned
                    }
                }
            }
        }
        if (!stillWanted(gen, routes)) return
        val avoidedCount = if (aligned[0] < baseCount &&
            !CameraDetour.sameRoute(baseRoute.polyline, list[0].polyline)
        ) baseCount - aligned[0] else 0
        val extraSeconds = if (avoidedCount > 0) (eta(list[0]) - eta0).coerceAtLeast(0.0) else 0.0
        val extraMeters = if (avoidedCount > 0) {
            (list[0].distanceMeters - routes[fastestIndex].distanceMeters).coerceAtLeast(0.0)
        } else 0.0
        val reordered = list
        val finalCounts = aligned
        _state.update { st ->
            // A user pick, a rename or a newer request owns the list now.
            if (!sameRouteSet(st.routes, routes) || st.active !== routes.first()) return@update st
            st.copy(
                routes = reordered,
                active = reordered.first(),
                cameraCounts = finalCounts,
                camerasAvoided = avoidedCount,
                cameraDetourSeconds = extraSeconds,
                cameraDetourMeters = extraMeters,
                cameraBaselineIsFastest = fastestIndex == 0,
            )
        }
        // A re-ranked list can lead with another route: its time and line own the hints now.
        if (reordered.first() !== routes.first()) publishHints(gen, reordered.first())
        if (avoidedCount > 0 && reordered.first().provisional) select(0)
    }

    /** One greedy pass over [route]'s camera clusters: the left then right point beside each is
     *  routed through like a stop, and a candidate that passes fewer cameras inside [cap] is kept
     *  and built on. Requests come from the trip's [budget] and at most
     *  [CameraDetour.MAX_REQUESTS_PER_ROUTE] are spent here; a same-road answer is never kept. */
    private suspend fun tryCameraDetour(
        route: Route, routeCount: Int, eta0: Double, cap: Double, gen: Int,
        origin: LatLng, dest: LatLng, stops: List<LatLng>, state: RouteState,
        budget: IntArray, tried: MutableList<LatLng>,
    ): Pair<Route, Int>? {
        val provider = camerasAlong ?: return null
        val poly = route.polyline
        val cum = RouteProjection.cumulative(poly)
        val onRoute = CameraDetour.onRoute(poly, provider(poly))
        val candidates = CameraDetour.untried(
            CameraDetour.candidates(poly, onRoute.map { it.atM }), tried)
        if (candidates.isEmpty()) return null
        val stopAt = stops.map { RouteProjection.alongMeters(poly, cum, it, 250.0) to it }
        var vias = emptyList<Pair<Double, LatLng>>()
        var best: Route? = null
        var bestCount = routeCount
        var requests = 0
        outer@ for (cluster in candidates) {
            tried += cluster.at
            for (via in listOf(cluster.left, cluster.right)) {
                if (requests >= CameraDetour.MAX_REQUESTS_PER_ROUTE || budget[0] <= 0) break@outer
                val trial = vias + (cluster.atM to via)
                val plan = CameraDetour.mergePlan(stopAt, trial)
                requests++
                budget[0]--
                val answer = try {
                    source().directions(
                        origin, dest, state.mode, plan, state.avoidTolls, state.avoidHighways,
                        state.avoidFerries,
                    )
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    continue
                }
                val r = answer.firstOrNull() ?: continue
                if (gen != generation) return null
                if (CameraDetour.sameRoute(poly, r.polyline)) continue
                val n = CameraDetour.count(r.polyline, provider(r.polyline))
                val extra = (r.durationInTrafficSeconds ?: r.durationSeconds) - eta0
                if (n < bestCount && extra <= cap) {
                    vias = trial
                    best = r.copy(detourPlan = plan)
                    bestCount = n
                    break
                }
            }
        }
        return best?.let { it to bestCount }
    }

    private fun stillWanted(gen: Int, routes: List<Route>): Boolean {
        val st = _state.value
        return gen == generation && st.open && sameRouteSet(st.routes, routes)
    }

    /** [current] holds the same route objects, in the same order, as [expected]. */
    private fun sameRouteSet(current: List<Route>, expected: List<Route>): Boolean {
        if (current.size != expected.size) return false
        return current.indices.all { current[it] === expected[it] }
    }

    /** Transitous with the chooser's time, vehicles and preference; the legacy two-point planner
     *  stays for tests and callers that predate the options. */
    private suspend fun planTransit(origin: LatLng, dest: LatLng, s: RouteState): List<TransitItinerary> {
        val options = transitOptionsPlanner
        if (options != null) {
            val query = TransitPlanQuery(s.timeMode, s.timeEpochSec, s.transitPrefer, s.transitRoutePref).normalized()
            return options(origin, dest, query)
        }
        return transitPlanner?.invoke(origin, dest, s.timeMode, s.timeEpochSec).orEmpty()
    }

    // port of MapViewModel.modeEtaKeyOf (the clock is a parameter)
    private fun etaKeyOf(origin: LatLng, dest: LatLng, stops: List<LatLng>, s: RouteState): String {
        val pts = (listOf(origin) + stops + dest).joinToString(";") { "${(it.lat * 1e5).roundToLong()},${(it.lng * 1e5).roundToLong()}" }
        return "$pts|${s.avoidTolls}|${s.avoidHighways}|${s.avoidFerries}|${s.timeMode}|${s.timeEpochSec}|${now() / 300_000L}"
    }

    // port of MapViewModel.beginModeEtas
    private fun beginModeEtas(key: String) {
        if (etaCache.size > 16) etaCache.clear()
        etaKey = key
        _state.update { it.copy(modeSeconds = etaCache[key].orEmpty().toMap()) }
    }

    // port of MapViewModel.publishModeEta (seconds; Swift formats them)
    private fun publishModeEta(key: String, mode: TravelMode, seconds: Double) {
        etaCache.getOrPut(key) { mutableMapOf() }[mode] = seconds
        if (etaKey == key) _state.update { it.copy(modeSeconds = etaCache[key].orEmpty().toMap()) }
    }

    // port of MapViewModel.prefetchModeEtas (transit last, from the planner)
    private fun prefetchModeEtas(key: String, origin: LatLng, dest: LatLng, stops: List<LatLng>, s: RouteState, except: TravelMode) {
        etaJob?.cancel()
        val known = etaCache[key].orEmpty()
        val planner = transitOptionsPlanner ?: transitPlanner
        val missing = listOf(TravelMode.DRIVE, TravelMode.WALK, TravelMode.BICYCLE, TravelMode.TRANSIT)
            .filter { it != except && it !in known && (it != TravelMode.TRANSIT || planner != null) }
        if (missing.isEmpty()) return
        etaJob = scope.launch {
            for (m in missing) {
                if (!_state.value.open || etaKey != key) return@launch
                if (_state.value.mode == m) continue
                val seconds = try {
                    if (m == TravelMode.TRANSIT) planTransit(origin, dest, s).firstOrNull()?.let(::transitSeconds)
                    else shownDuration(source().directions(origin, dest, m, stops, s.avoidTolls, s.avoidHighways, s.avoidFerries))
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    null
                } ?: continue
                publishModeEta(key, m, seconds)
            }
        }
    }

    companion object {
        const val KEY_MODE = "travel_mode"
        const val KEY_TOLLS = "avoid_tolls"
        const val KEY_HIGHWAYS = "avoid_highways"
        const val KEY_FERRIES = "avoid_ferries"
        /** Android's BikeSafe key, so the two apps read one preference when it is present. */
        const val KEY_BIKE_SAFE = "bike_safe"
        /** Android's "Live traffic only when I tap" key; the picker's gate reads it too. */
        const val KEY_TRAFFIC_ON_TAP = "route_traffic_on_tap"
        /** Android's "Avoid surveillance cameras" key (L109), off by default there and here. */
        const val KEY_AVOID_CAMERAS = "flock_route_alert_on"
        /** Android's "Try side streets around cameras" key (L203), nested under the camera choice. */
        const val KEY_CAMERA_SIDE_STREETS = "flock_detour"
        const val MAX_WAYPOINTS = 10
        private const val CENTER_MIN_M = 50.0

        // port of MapViewModel.shownDuration
        /** The chooser's time for a route set: the fastest live time, free-flow without traffic. */
        fun shownDuration(routes: List<Route>): Double? =
            routes.minOfOrNull { it.durationInTrafficSeconds ?: it.durationSeconds }

        /** How much longer than its free-flow time [r] takes now, in seconds; 0 without traffic. */
        fun trafficDelaySeconds(r: Route): Double =
            ((r.durationInTrafficSeconds ?: return 0.0) - r.durationSeconds).coerceAtLeast(0.0)

        /** An itinerary's length from its epoch times, null without them. */
        fun transitSeconds(t: TransitItinerary): Double? {
            val a = t.departureEpochSec ?: return null
            val b = t.arrivalEpochSec ?: return null
            return (b - a).toDouble().takeIf { it > 0 }
        }

        /** An itinerary's legs joined into one line: each leg's own path, else its stops or its
         *  walk's ends joined straight. */
        fun transitLineOf(t: TransitItinerary?): DoubleArray {
            val pts = ArrayList<LatLng>()
            for (st in t?.steps.orEmpty()) {
                val leg = st.path ?: listOfNotNull(
                    st.walkFrom ?: st.boardStop?.location,
                    st.walkTo ?: st.alightStop?.location,
                )
                pts += leg
            }
            val out = DoubleArray(pts.size * 2)
            pts.forEachIndexed { i, p -> out[2 * i] = p.lat; out[2 * i + 1] = p.lng }
            return out
        }

        fun lineOf(r: Route?): DoubleArray {
            val pts = r?.let { it.drawPolyline ?: it.polyline } ?: return DoubleArray(0)
            val out = DoubleArray(pts.size * 2)
            pts.forEachIndexed { i, p -> out[2 * i] = p.lat; out[2 * i + 1] = p.lng }
            return out
        }

        /** [r]'s traffic spans cut out of its drawn line, the span meters scaled to the line's
         *  own length (the drawn line and the router's distance differ by a few meters). */
        fun trafficOn(r: Route): List<TrafficLine> {
            val pts = r.drawPolyline ?: r.polyline
            if (pts.size < 2 || r.trafficSpans.isEmpty()) return emptyList()
            val along = DoubleArray(pts.size)
            for (i in 1 until pts.size) along[i] = along[i - 1] + pts[i - 1].distanceTo(pts[i])
            val total = along.last()
            if (total <= 0.0) return emptyList()
            val scale = if (r.distanceMeters > 0) total / r.distanceMeters else 1.0
            return r.trafficSpans.mapNotNull { span ->
                val a = (span.startMeters * scale).coerceIn(0.0, total)
                val b = ((span.startMeters + span.lengthMeters) * scale).coerceIn(0.0, total)
                if (b - a < 1.0) return@mapNotNull null
                TrafficLine(span.level, cut(pts, along, a, b))
            }
        }

        private fun cut(pts: List<LatLng>, along: DoubleArray, a: Double, b: Double): DoubleArray {
            val out = ArrayList<Double>()
            fun at(m: Double): LatLng {
                var i = 1
                while (i < along.size - 1 && along[i] < m) i++
                val seg = along[i] - along[i - 1]
                val t = if (seg > 0) (m - along[i - 1]) / seg else 0.0
                val p = pts[i - 1]; val q = pts[i]
                return LatLng(p.lat + (q.lat - p.lat) * t, p.lng + (q.lng - p.lng) * t)
            }
            val start = at(a)
            out += start.lat; out += start.lng
            for (i in pts.indices) {
                if (along[i] > a && along[i] < b) { out += pts[i].lat; out += pts[i].lng }
            }
            val end = at(b)
            out += end.lat; out += end.lng
            return out.toDoubleArray()
        }

        private fun KeyValueStore?.bool(key: String, default: Boolean = false): Boolean =
            this?.let { runCatching { it.getBoolean(key, default) }.getOrNull() } ?: default
    }
}
