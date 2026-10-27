package app.vela.ios.route

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.data.RoutingPrefs
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TravelMode
import app.vela.core.model.distanceTo
import app.vela.core.platform.Cancellable
import app.vela.core.platform.KeyValueStore
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
    /** Whether the directions template carries Google's avoid block (`DirectionsPb.avoidSupported`). */
    val avoidSupported: Boolean = false,
    /** The routes as the source returned them, never copied (PRESENTATION-MAP.md 5, trap 2). */
    val routes: List<Route> = emptyList(),
    /** One of [routes], by identity. */
    val active: Route? = null,
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
    fun rows(): List<RouteRow> = routes.map { r ->
        RouteRow(
            seconds = r.durationInTrafficSeconds ?: r.durationSeconds,
            meters = r.distanceMeters,
            via = r.summary?.takeIf { it.isNotBlank() },
            delaySeconds = RouteStore.trafficDelaySeconds(r),
            hasTraffic = r.hasLiveTraffic,
            typicalLowSeconds = r.typicalRangeSeconds?.first,
            typicalHighSeconds = r.typicalRangeSeconds?.second,
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
)

/** One step: the maneuver's `ManeuverType` name, the router's text, the meters to the next step. */
data class StepRow(
    val kind: String, val instruction: String, val meters: Double, val road: String?, val ref: String?,
    val laneHint: String?, val lanes: List<LaneRow>, val exit: Int,
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
) {
    private val _state = MutableStateFlow(RouteState())
    val state: StateFlow<RouteState> = _state.asStateFlow()

    private var started = false
    private var myLocation: LatLng? = null
    private var mapCenter: LatLng? = null
    private var routeJob: Job? = null
    private var etaJob: Job? = null
    private var namingJob: Job? = null
    private var generation = 0
    private var etaKey: String? = null
    private val etaCache = mutableMapOf<String, MutableMap<TravelMode, Double>>()

    fun start() {
        if (started) return
        started = true
        val p = runCatching { settings() }.getOrNull()
        val mode = p?.let { runCatching { it.getString(KEY_MODE, null)?.let(TravelMode::valueOf) }.getOrNull() }
        _state.update {
            it.copy(
                mode = mode ?: TravelMode.DRIVE,
                avoidTolls = p.bool(KEY_TOLLS),
                avoidHighways = p.bool(KEY_HIGHWAYS),
                avoidFerries = p.bool(KEY_FERRIES),
            )
        }
        syncRoutingAvoid()
    }

    // port of MapViewModel.directionsTo and routeToSelected (Google only, no stops or links)
    /** Opens the chooser to [p] from the user's location, on the sticky mode and avoids. */
    fun directionsTo(p: Place) {
        if (!started) return
        _state.update {
            it.copy(
                open = true, destination = p, origin = null, reversed = false, waypoints = emptyList(),
                timeMode = 0, timeEpochSec = null,
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
        if (!started) return
        _state.update {
            it.copy(
                open = true, destination = to, origin = origin, reversed = false,
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
        directionsFromNamed(origin, destination, modeName)
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
        etaKey = null
        generation++
        _state.update {
            it.copy(
                open = false, destination = null, origin = null, fromMapCenter = false, reversed = false,
                waypoints = emptyList(), timeMode = 0, timeEpochSec = null,
                routes = emptyList(), active = null, loading = false, error = null, modeSeconds = emptyMap(),
                showSteps = false, transit = emptyList(), activeTransit = -1,
            )
        }
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
        routeJob?.cancel()
        namingJob?.cancel()
        val gen = ++generation
        val fix = s.origin?.location ?: SearchStore.plausibleBias(myLocation)
        // The map's center only when it is not the place itself (a picked result is centered).
        val from = fix ?: SearchStore.plausibleBias(mapCenter)?.takeIf { it.distanceTo(place) > CENTER_MIN_M }
        if (from == null) {
            _state.update { it.copy(loading = false, routes = emptyList(), active = null, error = RouteError.NoOrigin) }
            return
        }
        val origin = if (s.reversed) place else from
        val dest = if (s.reversed) from else place
        val stops = s.waypoints.map { it.location }
        val key = etaKeyOf(origin, dest, stops, s)
        beginModeEtas(key)
        val mode = s.mode
        _state.update { it.copy(fromMapCenter = fix == null, routes = emptyList(), active = null, showSteps = false, transit = emptyList(), activeTransit = -1) }
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
                val routes = source().directions(origin, dest, mode, stops, s.avoidTolls, s.avoidHighways, s.avoidFerries)
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
                prefetchModeEtas(key, origin, dest, stops, s, except = mode)
                // The fastest can be a provisional alternate: named now, so the preview is the drive.
                if (routes.firstOrNull()?.provisional == true) select(0)
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
        _state.update { it.copy(loading = false, routes = emptyList(), active = null, error = error) }
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

        private fun KeyValueStore?.bool(key: String): Boolean =
            this?.let { runCatching { it.getBoolean(key, false) }.getOrNull() } ?: false
    }
}
