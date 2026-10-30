@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package app.vela.core.data.google

import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.LowDataMode
import app.vela.core.data.RerouteFallback
import app.vela.core.data.RouteBudget
import app.vela.core.data.RouteEngine
import app.vela.core.data.RouteGeometry
import app.vela.core.data.RouteHttp
import app.vela.core.data.RoutingPrefs
import app.vela.core.data.ValhallaRouter
import app.vela.core.data.abandonableAsync
import app.vela.core.diag.DiagSink
import app.vela.core.model.LatLng
import app.vela.core.model.Route
import app.vela.core.model.RouteSource
import app.vela.core.model.TravelMode
import app.vela.core.model.distanceTo
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.LogLevel
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.d
import app.vela.core.platform.i
import app.vela.core.platform.w
import app.vela.core.util.Fmt
import app.vela.core.util.LockedList
import app.vela.core.util.LockedMap
import app.vela.core.util.fixedInDefaultLocale
import app.vela.core.util.ioDispatcher
import kotlin.concurrent.atomics.AtomicInt
import kotlin.concurrent.atomics.AtomicReference
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Android's data source: [GoogleMapsSource] (every Google request and its parse, in `:core-common`)
 * plus the hybrid router, which stays here with the open routers and the on-device engine it calls:
 * the open router's steps, Google's traffic and alternates, map matching, street names from the
 * map tiles, the on-device engine, and the parking-lot last turn.
 */
class GoogleMapsDataSource(
    private val graph: CoreGraph,
    largeReplyHttp: VelaHttp,
    /** OSRM's client (`RouteGeometry`), with its bounded per-attempt clients. */
    private val routeHttp: RouteHttp,
    /** Valhalla's client: the plain one, each call with its own deadline. */
    private val openHttp: VelaHttp,
    session: GoogleSession,
    calibration: CalibrationStore,
    jsTransforms: JsTransforms,
    diag: DiagSink,
    private val routeEngine: RouteEngine,
    /** The browser the requests claim to be: Android's is [ChromeIdentity], iOS passes Safari. */
    identity: GoogleIdentity = ChromeIdentity { calibration.current() },
) : GoogleMapsSource(
    graph = graph,
    largeReplyHttp = largeReplyHttp,
    session = session,
    calibration = calibration,
    jsTransforms = jsTransforms,
    diag = diag,
    identity = identity,
) {

    override suspend fun directions(
        origin: LatLng,
        destination: LatLng,
        mode: TravelMode,
        waypoints: List<LatLng>,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
        urgent: Boolean,
        departBearingDeg: Double?,
        budgetMs: Long?,
    ): List<Route> {
        if (mode != TravelMode.DRIVE) return directionsPlain(origin, destination, mode, waypoints, avoidTolls, avoidHighways, avoidFerries, urgent, departBearingDeg, budgetMs)
        // The map's roads round the destination are asked for while the routes are fetched, so
        // the word on the last turn (withLotTurn) is a read from memory by the time they are built.
        if (!app.vela.core.data.LowDataMode.enabled) kotlinx.coroutines.CoroutineScope(ioDispatcher).launch {
            runCatching { app.vela.core.data.naming.RoadNameTiles.roadsAlong(listOf(destination)) }
        }
        val routes = directionsPlain(origin, destination, mode, waypoints, avoidTolls, avoidHighways, avoidFerries, urgent, departBearingDeg, budgetMs)
        // Off the caller's thread (the view model calls from Main): the tiles' protobuf is
        // decoded here. Every route at once, so a tile host that does not answer costs one wait.
        return io { coroutineScope { routes.map { r -> async { withLotTurn(r, urgent) } }.awaitAll() } }
    }

    /**
     * [route] with its last turn worded "into the parking lot" when the map shows it entering the
     * destination's own lot (ParkingLotTurn.wordDestination). A route that cannot be driven as it
     * is, or whose steps are Google's short ones, is left alone; so is one the map does not answer
     * for inside the wait.
     */
    private suspend fun withLotTurn(route: Route, urgent: Boolean): Route {
        if (!route.drivable || !route.hasRealSteps) return route
        return kotlinx.coroutines.withTimeoutOrNull(if (urgent) LOT_WORD_WAIT_URGENT_MS else LOT_WORD_WAIT_MS) {
            runCatching {
                app.vela.core.nav.ParkingLotTurn.wordDestination(route) { left -> app.vela.core.i18n.NavStringsRegistry.current().intoLot(left) }
            }.getOrNull()
        } ?: route
    }

    private suspend fun directionsPlain(
        origin: LatLng,
        destination: LatLng,
        mode: TravelMode,
        waypoints: List<LatLng>,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
        urgent: Boolean,
        departBearingDeg: Double?,
        budgetMs: Long?,
    ): List<Route> = io {
        // Mid-drive reroutes are URGENT: one shot per source, no divergence snap, no alternates
        // polish. The retry ladders below (3x OSRM + 3x Google with backoff) are right for a
        // planning fetch but can hold a reroute past NavSession's hard deadline on a flaky cell
        // link, so the fetch gets canceled mid-flight and the driver waits on the next attempt
        // (issues #185/#236). The recheck loop upgrades the lean result minutes later anyway.
        val tries = if (urgent) 1 else 3
        // BOUNDED fetches (issue #557): a reroute carries its deadline in. A diagnostics export
        // showed FOSSGIS's car router hanging while its foot router answered: each urgent attempt
        // sat 20 s on the open router (the shared client's timeouts) and never consulted Google or
        // the downloaded region, and the escalated attempt could not even finish its three OSRM
        // tries inside its own deadline. Now the open router gets a short call timeout and only a
        // share of the budget, and the fallbacks get the rest. A planning fetch (no budget, not
        // urgent) takes none of these branches.
        val budget = RouteBudget.of(budgetMs ?: if (urgent) URGENT_DEFAULT_BUDGET_MS else null)
        val bounded = budget.bounded
        val osrmTryMs: Long? = when {
            urgent -> URGENT_OSRM_TIMEOUT_MS
            bounded -> LADDER_OSRM_TRY_MS
            else -> null
        }
        val osrmBudget = when {
            !bounded -> RouteBudget.NONE
            urgent -> budget.slice(URGENT_OSRM_TIMEOUT_MS)
            else -> budget.slice(((budget.remainingMs() ?: 0L) * LADDER_OSRM_SHARE).toLong())
        }
        val osrmWhy = AtomicReference("empty reply")
        val onOsrmFail: (String) -> Unit = { osrmWhy.store(it) }
        val stage = if (urgent) "urgent" else "ladder"
        // Bike mode routes for safety over speed (issue #401, default on): the offline engine's
        // bicycle profile where a region is downloaded, else the open Valhalla router told to stay
        // off busy roads. Null = neither answered, so the fastest-route chain below takes over.
        if (mode == TravelMode.BICYCLE && RoutingPrefs.bikeSafe) {
            bikeSafeRoutes(origin, destination, waypoints, avoidTolls, avoidHighways, avoidFerries, urgent)?.let { return@io it }
        }
        if (mode == TravelMode.WALK && waypoints.isEmpty()) {
            walkRoutes(origin, destination, tries, osrmTryMs, osrmBudget, onOsrmFail, urgent)?.let { return@io it }
        }
        // Multi-stop (rebuilt 2026-09-21, issue #600): Google is asked for the trip THROUGH the stops
        // (DirectionsPb.withWaypoints) and the open router is routed through them too. Same course =
        // the open route with Google's real through-the-stops time and spans; Google left the course
        // (traffic, an avoid) = the open router is snapped along Google's line leg by leg, with the
        // stops as vias between the samples, exactly as the single-destination path snaps below.
        // Before this Google was only ever asked for the DIRECT trip and its answer calibrated a
        // speed; every trip with stops was the open router's free-flow choice with a ratio on it.
        // A waypointed trip is a single path: neither router returns alternates for one.
        if (waypoints.isNotEmpty()) {
            return@io coroutineScope {
                val phoneFirst = urgent && routeEngine.isReady(mode) && routeEngine.covers(origin, destination, mode)
                val viaCall: suspend () -> List<Route> = {
                    RouteGeometry.routeVia(
                        routeHttp, listOf(origin) + waypoints + destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg,
                        tries = tries, callTimeoutMs = osrmTryMs, budget = osrmBudget, onFailure = onOsrmFail,
                    )
                }
                // Outside the scope when phone first can return ahead of it: a scope waits for its
                // children, and as one this blocking call would hold the phone's route for the
                // rest of URGENT_OSRM_TIMEOUT_MS.
                val viaD = if (phoneFirst) abandonableAsync { viaCall() } else async { viaCall() }
                // Same urgent grace as the single-destination path below (issue #397).
                val gD = if (bounded) kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                    googleDirectionsRetried(origin, destination, mode, tries, avoidTolls, avoidHighways, avoidFerries, waypoints)
                } else async { googleDirectionsRetried(origin, destination, mode, tries, avoidTolls, avoidHighways, avoidFerries, waypoints) }
                // PHONE FIRST for a trip with stops: the legs chained on the downloaded region.
                val phoneD = if (phoneFirst) {
                    kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                        runCatching { chainOnDevice(listOf(origin) + waypoints + destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg, maxMs = PHONE_FIRST_ONLINE_WAIT_MS + PHONE_FIRST_ONDEVICE_WAIT_MS) }.getOrNull()
                    }
                } else null
                val via = if (phoneD == null) viaD.await().firstOrNull() else {
                    val early = kotlinx.coroutines.withTimeoutOrNull(PHONE_FIRST_ONLINE_WAIT_MS) { viaD.await() }
                    if (!early.isNullOrEmpty()) early.first() else {
                        val wait = minOf(PHONE_FIRST_ONDEVICE_WAIT_MS, budget.remainingMs() ?: PHONE_FIRST_ONDEVICE_WAIT_MS).coerceAtLeast(0L)
                        val onDevice = kotlinx.coroutines.withTimeoutOrNull(wait) { phoneD.await() }
                        if (onDevice != null) {
                            diag.record(
                                "directions",
                                "urgent: phone first, on-device legs ×${waypoints.size} after ${budget.elapsedMs()} ms while the open router was " +
                                    (if (early == null) "still out" else "empty") + "; the recheck heals traffic",
                                "",
                            )
                            return@coroutineScope listOf(onDevice)
                        }
                        (early ?: viaD.await()).firstOrNull()
                    }
                }
                if (bounded && via == null) {
                    // Bounded + open router empty (issue #557): Google's direct route if it is back,
                    // else the on-device legs, else nothing; never past the budget.
                    val osrmMs = budget.elapsedMs()
                    val fb = RerouteFallback.pick(
                        gD,
                        onDevice = if (routeEngine.isReady(mode)) {
                            { listOfNotNull(chainOnDevice(listOf(origin) + waypoints + destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg, maxMs = budget.remainingMs())) }
                        } else null,
                        budgetMs = budget.remainingMs() ?: 0L,
                    )
                    diag.record(
                        "directions",
                        "$stage: $mode multi-stop ×${waypoints.size} open router gave nothing after $osrmMs ms (${osrmWhy.load()}); " +
                            "fallback ${fb.source.name.lowercase()} ${fb.routes.size} route(s) after ${fb.waitedMs} ms more (on-device tried=${fb.onDeviceTried})",
                        "",
                    )
                    return@coroutineScope when (fb.source) {
                        RerouteFallback.Source.GOOGLE_READY, RerouteFallback.Source.GOOGLE ->
                            fb.routes.take(1).map { it.copy(abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED) }
                        RerouteFallback.Source.ON_DEVICE -> fb.routes
                        RerouteFallback.Source.NONE -> emptyList()
                    }
                }
                suspend fun googleOrGrace(): List<Route> =
                    if (urgent && via != null) kotlinx.coroutines.withTimeoutOrNull(URGENT_GOOGLE_GRACE_MS) { gD.await() } ?: emptyList()
                    else if (bounded) kotlinx.coroutines.withTimeoutOrNull(budget.remainingMs() ?: 0L) { gD.await() } ?: emptyList()
                    else gD.await()
                // OSRM unreachable → route the legs on-device (origin→w1→…→dest chained), like the
                // single-destination path's offline fallback; only then fall to Google's DIRECT route
                // (which reaches the destination but loses the stops).
                val onDevice = if (via == null && routeEngine.isReady(mode))
                    chainOnDevice(listOf(origin) + waypoints + destination, mode, avoidTolls, avoidHighways, avoidFerries) else null
                // Google is awaited only on the branches that read it (the on-device fallback with no
                // open route never waited for it, and still does not).
                val g: Route? = if (via != null || onDevice == null) googleOrGrace().firstOrNull() else null
                // THE GUARD: Google's line has to pass every stop, or the reply is the direct trip
                // (a template without the waypoint groups, or a drift) and gets the old direct-trip
                // handling, never adopted as if it called at the stops.
                val gStops = g?.takeIf { it.polyline.size >= 5 && RouteGeometry.stopsOnLine(it.polyline, waypoints) }
                val avoidWantedHere = (avoidTolls || avoidHighways || avoidFerries) && mode == TravelMode.DRIVE
                var divergentStops = false
                var snapKeptStops = false
                var honoredByGoogle = false
                var result = when {
                    via != null && gStops != null -> {
                        divergentStops = RouteGeometry.divergent(via, gStops)
                        var snapped: Route? = null
                        if (divergentStops && (!urgent || avoidWantedHere)) {
                            val pts = RouteGeometry.sampleViasThrough(gStops.polyline, waypoints)
                            if (pts != null) {
                                val all = listOf(origin) + pts + destination
                                // The real stops' positions in the via list: exempt from the strict
                                // snap-distance refusal (a stop in a lot is a stop, not an appendix).
                                val loose = all.indices.filter { i -> i in 1 until all.lastIndex && waypoints.any { it == all[i] } }.toSet()
                                snapped = RouteGeometry.routeVia(
                                    routeHttp, all, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg,
                                    strictVias = true, looseVias = loose, tries = tries, callTimeoutMs = osrmTryMs, budget = budget,
                                ).firstOrNull()?.copy(source = RouteSource.OSRM_VIA_SNAP)?.takeIf { r ->
                                    r.polyline.lastOrNull()?.let { it.distanceTo(destination) <= SNAP_REACH_M } == true &&
                                        r.distanceMeters <= gStops.distanceMeters * SNAP_LENGTH_SLACK + SNAP_LENGTH_SLACK_M &&
                                        !spurWithTurn(r, gStops.polyline)
                                }
                            }
                        }
                        // One calibration from whichever open route follows Google's course, the
                        // single-destination rule: both now cover the same trip through the same stops.
                        val basis = if (!divergentStops) via else snapped
                        val cal = basis?.takeIf { it.durationSeconds > 0 && gStops.durationSeconds > 0 }?.let { b ->
                            val dScale = if (gStops.distanceMeters > 0) b.distanceMeters / gStops.distanceMeters else 1.0
                            ((gStops.durationSeconds * dScale) / b.durationSeconds).coerceIn(0.5, 3.0)
                        }
                        val gEta = gStops.durationInTrafficSeconds ?: gStops.durationSeconds
                        snapKeptStops = snapped != null &&
                            (avoidWantedHere || gEta <= via.durationSeconds * (cal ?: 1.0) * SNAP_ETA_MARGIN)
                        when {
                            !divergentStops -> { honoredByGoogle = true; listOf(applyTraffic(via, gStops, freeFlowCal = cal)) }
                            snapKeptStops -> { honoredByGoogle = true; listOf(applyTraffic(snapped!!, gStops, freeFlowCal = cal)) }
                            // Avoid on and the open router could not be led along Google's avoiding
                            // course: Google's own (abbreviated) route through the stops beats a
                            // plain one that ignores the avoid, the single-destination rule.
                            avoidWantedHere -> { honoredByGoogle = true; listOf(gStops.copy(abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED)) }
                            // Google's detour was not worth it: the open route, its speed rebased on
                            // Google's through-the-stops time, spans transferred where the roads overlap.
                            else -> listOf(applyTraffic(via, gStops, freeFlowCal = speedCal(via, gStops)))
                        }
                    }
                    // Google answered with the direct trip (or not at all): the old calibration, a
                    // speed ratio so the distance difference cancels, spans kept off other roads.
                    via != null -> listOf(applyTraffic(via, g, freeFlowCal = speedCal(via, g)))
                    onDevice != null -> listOf(onDevice)
                    else -> listOfNotNull(g).map { it.copy(abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED) }
                }
                // The open router cannot exclude; only a result that left Google's avoiding course
                // (or never had one) gets the note.
                if (avoidWantedHere && via != null && !honoredByGoogle) {
                    result = result.map { it.copy(avoidNotHonored = true) }
                }
                // The plain trip's farm-track check, for a trip through stops: when the line
                // offered is the open router's own and it cuts through a track, the other
                // service's car route through the same points takes its place.
                if (mode == TravelMode.DRIVE && via != null && result.firstOrNull()?.polyline === via.polyline) {
                    offTrackRoute(via, listOf(origin) + waypoints + destination, avoidTolls, avoidHighways, avoidFerries, urgent)?.let { other ->
                        val timed = applyTraffic(other, g, freeFlowCal = speedCal(other, g), withSpans = false)
                        result = listOf(if (avoidWantedHere && !honoredByGoogle) timed.copy(avoidNotHonored = true) else timed)
                    }
                }
                val line = "$mode multi-stop ×${waypoints.size} → via=${via != null} onDevice=${onDevice != null} " +
                    "googleStops=${when { g == null -> "none"; gStops != null -> "honored"; else -> "IGNORED" }} " +
                    "divergent=$divergentStops snapKept=$snapKeptStops " +
                    "googleDirect=${result.isNotEmpty() && via == null && onDevice == null}" +
                    if (via == null && onDevice == null && gStops == null) " (STOPS DROPPED if google won)" else ""
                diag.record("directions", line, "")
                // Mirrored to logcat (no coordinates in it): the diag ring needs an opt-in and an
                // export, and whether Google took the stops is the first thing to check in the field.
                runCatching { graph.log.d("VelaDirections", line) }
                result
            }
        }
        var avoidHonored = false
        var openEdgesD: kotlinx.coroutines.Deferred<List<app.vela.core.data.ValhallaRouter.Edge>?>? = null
        var openLine: List<LatLng>? = null
        val fetched = coroutineScope {
            val phoneFirst = urgent && routeEngine.isReady(mode) && routeEngine.covers(origin, destination, mode)
            // PRIMARY: the open router (OSRM) — complete, street-named turn-by-turn + real geometry.
            // Google's keyless directions endpoint hands back ABBREVIATED steps for longer routes
            // (a 6-mi route came back with 2 of ~10 turns), so Google is only the FALLBACK + the
            // live-traffic source. Fetch both in parallel so the traffic round-trip is free.
            val openCall: suspend () -> List<Route> = {
                RouteGeometry.route(
                    routeHttp, origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, tries, departBearingDeg,
                    callTimeoutMs = osrmTryMs, budget = osrmBudget, onFailure = onOsrmFail,
                )
            }
            // Outside the scope when phone first can return ahead of it: a scope waits for its
            // children, and as one this blocking call would hold the phone's route for the rest
            // of URGENT_OSRM_TIMEOUT_MS. The scope's end, or its cancellation, cancels it.
            val openD = if (phoneFirst) abandonableAsync { openCall() } else async { openCall() }
            // URGENT (a mid-drive reroute): Google runs on an unstructured scope so a dead or slow
            // Google endpoint cannot hold the reroute. A diagnostics export (issue #397, 2026-09-15)
            // showed reroutes taking 18 to 40 s while OSRM had answered in seconds, because the
            // fetch waited for Google's empty replies and their backoff. Once the open router has
            // a route, Google gets URGENT_GOOGLE_GRACE_MS more; past that the route goes out
            // trafficless and the recheck's trafficUpgrade heals it minutes later. (A structured
            // child would keep this scope open until the blocking HTTP call returned, which is the
            // wait this exists to remove; the orphan finishes into the void, like the avoid compute.)
            val googleD = if (bounded) kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                googleDirectionsRetried(origin, destination, mode, tries, avoidTolls, avoidHighways, avoidFerries)
            } else async { googleDirectionsRetried(origin, destination, mode, tries, avoidTolls, avoidHighways, avoidFerries) }
            // PHONE FIRST: an urgent reroute over a downloaded region computes the on-device route
            // in parallel and takes it when the open router is not back inside the short wait.
            val phoneD = if (phoneFirst) {
                kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                    runCatching {
                        routeEngine.route(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg, maxMs = PHONE_FIRST_ONLINE_WAIT_MS + PHONE_FIRST_ONDEVICE_WAIT_MS)
                            .map { it.copy(offline = true) }
                    }.getOrDefault(emptyList())
                }
            } else null
            val openRaw = if (phoneD == null) openD.await() else {
                val early = kotlinx.coroutines.withTimeoutOrNull(PHONE_FIRST_ONLINE_WAIT_MS) { openD.await() }
                if (!early.isNullOrEmpty()) early else {
                    val wait = minOf(PHONE_FIRST_ONDEVICE_WAIT_MS, budget.remainingMs() ?: PHONE_FIRST_ONDEVICE_WAIT_MS).coerceAtLeast(0L)
                    val onDevice = kotlinx.coroutines.withTimeoutOrNull(wait) { phoneD.await() }.orEmpty()
                    if (onDevice.isNotEmpty()) {
                        avoidHonored = true // the obf engine applies the avoid parameters itself
                        diag.record(
                            "directions",
                            "urgent: phone first, on-device route after ${budget.elapsedMs()} ms while the open router was " +
                                (if (early == null) "still out" else "empty") + "; the recheck heals traffic",
                            "",
                        )
                        return@coroutineScope onDevice
                    }
                    early ?: openD.await()
                }
            }
            // THE OPEN ROUTER'S TURN NAMES ARE CHECKED TOO (2026-10-02): the road pieces under its
            // own line are asked for here and read once the routes are built (after this block), so
            // the request runs beside Google's and the stretch matching instead of ahead of them.
            openLine = openRaw.firstOrNull()?.polyline
            openEdgesD = if (mode == TravelMode.DRIVE && openRaw.firstOrNull()?.source == RouteSource.OSRM)
                kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                    // A reply in a shape the parser does not know is no answer, not a failed route.
                    runCatching { app.vela.core.data.ValhallaRouter.edges(openHttp, openRaw.first().polyline, timeoutMs = if (urgent) 1_000 else 2_500) }.getOrNull()
                } else null
            val avoidWanted = (avoidTolls || avoidHighways || avoidFerries) && mode == TravelMode.DRIVE
            if (bounded && openRaw.isEmpty()) {
                // Bounded + open router empty or hung (issue #557): (a) Google's route from this
                // same fetch if it is already back, (b) the downloaded region, (c) nothing. Google
                // routes go out tagged abbreviated, so the recheck heal upgrades them to full
                // steps once the open router answers again. Every decision is logged so an
                // export shows which source answered and how long each stage took.
                val osrmMs = budget.elapsedMs()
                val fb = RerouteFallback.pick(
                    googleD,
                    onDevice = if (routeEngine.isReady(mode)) {
                        {
                            routeEngine.route(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg, maxMs = budget.remainingMs())
                                .map { it.copy(offline = true) }
                        }
                    } else null,
                    budgetMs = budget.remainingMs() ?: 0L,
                )
                diag.record(
                    "directions",
                    "$stage: $mode open router gave nothing after $osrmMs ms (${osrmWhy.load()}); " +
                        "fallback ${fb.source.name.lowercase()} ${fb.routes.size} route(s) after ${fb.waitedMs} ms more " +
                        "(on-device tried=${fb.onDeviceTried}, heading=${departBearingDeg?.toInt()})",
                    "",
                )
                return@coroutineScope when (fb.source) {
                    RerouteFallback.Source.GOOGLE_READY, RerouteFallback.Source.GOOGLE -> {
                        if (avoidWanted && DirectionsPb.avoidSupported(calibration.current().directionsPb)) avoidHonored = true
                        fb.routes.map { it.copy(abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED) }
                    }
                    RerouteFallback.Source.ON_DEVICE -> {
                        avoidHonored = true // the obf engine applies the avoid parameters itself
                        fb.routes
                    }
                    RerouteFallback.Source.NONE -> emptyList()
                }
            }
            val googleAll = when {
                urgent && openRaw.isNotEmpty() ->
                    kotlinx.coroutines.withTimeoutOrNull(URGENT_GOOGLE_GRACE_MS) { googleD.await() } ?: run {
                        diag.record("directions", "urgent: google not back ${URGENT_GOOGLE_GRACE_MS} ms after OSRM, rerouting trafficless")
                        emptyList()
                    }
                // The escalated reroute: the open router answered, Google gets what is left
                // minus room for the traffic snap, then the route goes out trafficless.
                bounded -> {
                    val wait = ((budget.remainingMs() ?: 0L) - LADDER_SNAP_RESERVE_MS).coerceAtLeast(0L)
                    kotlinx.coroutines.withTimeoutOrNull(wait) { googleD.await() } ?: run {
                        diag.record("directions", "ladder: google not back after ${budget.elapsedMs()} ms, rerouting trafficless")
                        emptyList()
                    }
                }
                else -> googleD.await()
            }
            // A REROUTE GOES THE WAY THE CAR IS GOING. Google's request has no heading, so from a
            // car that has just passed a turn its route often starts back the way the car came,
            // and since the driven line is Google's wherever it differs, the reroute said "turn
            // around", the driver carried on, and the next reroute said it again (a real drive,
            // three reroutes in thirty seconds). The open router was asked with the car's heading;
            // a Google route that starts against it is set aside when the open router answered,
            // unless going on costs minutes more than turning around (RouteGeometry.forwardChoice).
            val google = if (departBearingDeg != null && openRaw.isNotEmpty()) {
                val chosen = RouteGeometry.forwardChoice(googleAll, departBearingDeg, openRaw.firstOrNull()?.durationSeconds, openRaw.firstOrNull()?.distanceMeters)
                val against = googleAll.count { RouteGeometry.startsAgainst(it.polyline, departBearingDeg) }
                if (against > 0) diag.record(
                    "directions",
                    "reroute: $against of ${googleAll.size} google route(s) start against the car's heading, " +
                        when {
                            chosen.isEmpty() -> "set aside for the open router's"
                            RouteGeometry.startsAgainst(chosen.first().polyline, departBearingDeg) -> "kept: going on costs too much"
                            else -> "set aside"
                        },
                )
                chosen
            } else googleAll
            val gTop = google.firstOrNull()
            val open = openRaw
            // AVOID toggles: the public FOSSGIS OSRM rejects `exclude=` outright (probed
            // 2026-07-11 and again 2026-08-24: InvalidValue, its profiles were not built with
            // excludable classes). Google's keyless directions DO honor avoid (DirectionsPb.withAvoid, 2026-09-06), so
            // online the avoiding route IS gTop: the open router cannot exclude, so its plain route
            // diverges and the snap below follows Google's course with named turns, and Google's
            // own in-traffic time is the ETA. The on-device engine is the avoid router only when
            // Google is unreachable. (Until today avoid was on-device-or-nothing, with the plain
            // route and a note otherwise; #325's broken ETA came from that branch.)
            // Honored only when the request could actually carry the flags: a recalibrated pb
            // template without the feature block makes withAvoid a no-op (review 2026-09-06).
            if (avoidWanted && gTop != null && DirectionsPb.avoidSupported(calibration.current().directionsPb)) avoidHonored = true
            if (avoidWanted && gTop == null && routeEngine.isReady(mode)) {
                // BOUNDED: the obf engine can spend many seconds on a long route, and this branch
                // used to wait for it unconditionally - with an offline region installed an
                // avoid-toggled plan just sat there (the Reddit report). The compute runs on an
                // UNSTRUCTURED scope on purpose: a structured child would keep this coroutineScope
                // from returning until the non-cancellable native compute finished, which would
                // defeat the timeout entirely. Past the deadline the online chain answers (tagged
                // not-honored below) and the orphaned compute finishes and is discarded.
                val avoidWait = budget.remainingMs()?.let { minOf(it, AVOID_ONDEVICE_TIMEOUT_MS) } ?: AVOID_ONDEVICE_TIMEOUT_MS
                val avoidD = kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                    runCatching { routeEngine.route(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg, maxMs = avoidWait).map { it.copy(offline = true) } }.getOrDefault(emptyList())
                }
                val avoidRoutes = kotlinx.coroutines.withTimeoutOrNull(avoidWait) { avoidD.await() } ?: emptyList()
                if (avoidRoutes.isNotEmpty()) {
                    avoidHonored = true
                    // Offline (no Google answer): the engine's own time is all there is. Online,
                    // this branch never runs; Google's avoiding route carries the traffic ETA.
                    return@coroutineScope avoidRoutes
                }
            }
            // TRAFFIC-AWARE routing (option 3): if Google's live-traffic route took a DIFFERENT path
            // than OSRM's free-flow one — i.e. Google rerouted around a jam — re-run OSRM forced
            // through Google's path so we follow the traffic-smart route WITH full street-named steps.
            // (Only on real divergence, so the normal case stays the fast single OSRM call.)
            val topDivergent = open.isNotEmpty() && gTop != null && gTop.polyline.size >= 5 &&
                RouteGeometry.divergent(open.first(), gTop)
            // GOOGLE'S LINE, ALWAYS (2026-10-02, a real drive: Google routed around a closed road,
            // Vela drove into it twice). The open router knows nothing of closures, and the test
            // above samples five points and asks for 700 m, so a detour of a few blocks read as
            // "same course" and the open route was kept with Google's time painted on it. Now,
            // for DRIVE, wherever Google's line leaves the open route at all the result is
            // Google's line itself (HybridRoute): the open router's maneuvers where the two share
            // the road, turns named from the map tiles on the stretches where they do not. Nothing
            // is routed through sampled points, so it cannot loop. Only the tiles under the
            // differing stretches are read. When a stretch cannot be named (tiles unreachable,
            // too little of it on a named street) the older via-snap and plain paths stand.
            // CAPTURE for the replay tests: Google's own line for this trip, to logcat, only when a
            // developer asks (adb shell setprop log.tag.VelaCapture DEBUG). Lines from real trips are
            // what NamingStudyTest.replayCapturedLines builds the route from on a desk, where
            // Google's directions cannot be fetched.
            if (mode == TravelMode.DRIVE && gTop != null && graph.log.isLoggable("VelaCapture", LogLevel.DEBUG)) runCatching {
                val id = graph.clock.nowMillis().toString(36)
                val enc = PolylineCodec.encode(gTop.polyline)
                graph.log.d("VelaCapture", "BEGIN $id ${gTop.distanceMeters.toInt()} ${gTop.durationSeconds.toInt()} ${enc.length}")
                enc.chunked(3000).forEachIndexed { i, c -> graph.log.d("VelaCapture", "P $id $i $c") }
                graph.log.d("VelaCapture", "END $id")
            }
            val hybridStretches = if (mode == TravelMode.DRIVE && open.isNotEmpty() && gTop != null && gTop.polyline.size >= 5)
                app.vela.core.data.naming.HybridRoute.stretchesFor(gTop.polyline, open.first()) else emptyList()
            // Which stretch ends the trip is read off the line's own length: stretches are meters
            // along the line, and Google's stated distance is not.
            val gLineM = if (hybridStretches.isEmpty() || gTop == null) 0.0 else app.vela.core.data.naming.HybridRoute.lengthOf(gTop.polyline)
            val tHybrid = graph.clock.nowMillis()
            // Each stretch where Google leaves the open route gets its steps from the best source
            // that answers, in this order (how many took each is logged):
            //  1. a MAP MATCH of the stretch (ValhallaRouter.match): the road network's own steps
            //     for the roads the line is on, so a name is never a guess. Checked against the
            //     line before it is trusted.
            //  2. the map tiles, strictly (LineNamer): a name only where the map is sure. A study
            //     of 90 routes put this at 1.4% wrong names, which is why it is second.
            //  3. the line's bends alone: bare "Turn right".
            // It is always Google's line. A missing street name costs nothing; a wrong one, or the
            // open router's own route through whatever Google went around, sends the driver wrong
            // (the owner's rule, 2026-10-02).
            val untrusted = LockedList<app.vela.core.data.naming.HybridRoute.Stretch>() // where a kept match is off Google's line
            val stretchNames = IntArray(4) // on matched stretches: turn names kept, renamed, bare; stretches whose edges did not come back
            val stretchSource = IntArray(4) // matched, from tiles, bare, and of the matched: with the open router's lane detail
            // The matched road shape per stretch (OpenStreetMap geometry), for the line to DRAW.
            val matchedShapes = LockedMap<app.vela.core.data.naming.HybridRoute.Stretch, List<LatLng>>()
            // Each stretch's steps from the best source in hand when the route has to go out
            // (StretchNamer). The tiles are read beside the matcher, so a slow matcher costs no
            // names; and what a stretch has when the deadline passes is kept, so one slow stretch
            // does not strip the others, and a matched stretch keeps its road shape for the line.
            val matches = LockedMap<app.vela.core.data.naming.HybridRoute.Stretch, app.vela.core.data.ValhallaRouter.Match>()
            val nudgedM = AtomicInt(0) // meters of the drawn line moved onto the roads' middle
            fun pieceOf(st: app.vela.core.data.naming.HybridRoute.Stretch) = app.vela.core.data.naming.HybridRoute.slice(gTop!!.polyline, st.fromM, st.toM)
            val namer = app.vela.core.data.naming.StretchNamer(
                match = { st ->
                    val (startSlack, endSlack) = app.vela.core.data.naming.HybridRoute.tripEndSlack(st, gLineM, MATCH_TRIP_END_SLACK_M)
                    val m = if (st.toM - st.fromM <= MATCH_MAX_M && !app.vela.core.data.ValhallaRouter.matchOff)
                        app.vela.core.data.ValhallaRouter.matchWithEdges(
                            openHttp, pieceOf(st), timeoutMs = if (urgent) 1_200 else 2_500,
                            startSlackM = startSlack, endSlackM = endSlack,
                            // Only a stretch that starts the trip has its first step said.
                            departSaid = st.fromM <= 0.0,
                        ) else null
                    m?.let {
                        matches[st] = it
                        it.off.forEach { o -> untrusted += app.vela.core.data.naming.HybridRoute.Stretch(st.fromM + o.first, st.fromM + o.second) }
                        if (it.off.isEmpty()) matchedShapes[st] = it.route.polyline
                        app.vela.core.data.naming.StretchNamer.Named(
                            it.route.maneuvers, app.vela.core.data.naming.StretchNamer.Source.MATCHED,
                            names = it.names.copyOf(3), noEdges = it.edges == null,
                        )
                    }
                },
                // LANES: the matcher gives names, exit numbers and signs but no lane arrows; only
                // the open router has those. The matched path is on the road network exactly, so
                // the open router can be led along it with a point in the middle of each step
                // (never at a turn, which a via swallows), each with the path's heading. Its steps
                // are used only when its path is the matched path (8 m); else the matcher's stand.
                // Those steps carry the open router's names, so they pass the same check against
                // the matched edges; borrowed lanes sit on the matcher's steps, whose names are
                // already checked. Without edges the matcher's stand.
                lanes = { st, plain ->
                    val m = matches[st]
                    val edges = m?.edges
                    if (urgent || m == null || edges == null) null else {
                        val (startSlack, endSlack) = app.vela.core.data.naming.HybridRoute.tripEndSlack(st, gLineM, MATCH_TRIP_END_SLACK_M)
                        laneDetail(m.route, LANE_TRY_MS, trimStartM = startSlack, trimEndM = endSlack)?.let { (ms, replaced) ->
                            val dt = IntArray(4)
                            val steps = if (replaced) app.vela.core.data.ValhallaRouter.recheck(ms, edges, keepUnplaced = false, tally = dt) else ms
                            app.vela.core.data.naming.StretchNamer.Named(
                                steps, app.vela.core.data.naming.StretchNamer.Source.MATCHED, lanes = true,
                                names = if (replaced) intArrayOf(dt[0], dt[1], dt[2] + dt[3]) else plain.names,
                            )
                        }
                    }
                },
                tiles = { st, fetch ->
                    val piece = pieceOf(st)
                    val len = st.toM - st.fromM
                    val sub = gTop!!.copy(
                        polyline = piece, distanceMeters = len, legs = emptyList(), trafficSpans = emptyList(),
                        durationSeconds = if (gTop.distanceMeters > 0) gTop.durationSeconds * len / gTop.distanceMeters else 0.0,
                    )
                    val lines = app.vela.core.data.naming.RoadNameTiles.linesAlong(piece, fetchMissing = fetch).orEmpty()
                    app.vela.core.data.naming.LineNamer.name(sub, lines, mode, strict = true)?.maneuvers?.let {
                        app.vela.core.data.naming.StretchNamer.Named(
                            it, if (lines.isEmpty()) app.vela.core.data.naming.StretchNamer.Source.BARE else app.vela.core.data.naming.StretchNamer.Source.TILES,
                        )
                    }
                },
                // On a link where bytes are precious the tiles wait for the matcher to fail.
                hedgeAfterMs = when {
                    app.vela.core.data.LowDataMode.enabled -> TILE_HEDGE_NEVER_MS
                    urgent -> TILE_HEDGE_URGENT_MS
                    else -> TILE_HEDGE_MS
                },
            )
            suspend fun hybridOf(online: Boolean): Route? = coroutineScope {
                val named = hybridStretches.map { st ->
                    async(ioDispatcher) { st to (if (online) namer.name(st) else namer.inHand(st))?.steps }
                }.awaitAll()
                if (named.any { it.second == null }) return@coroutineScope null
                // The open router's steps that are carried over get their names checked first, at
                // their own positions (the stitch moves them onto Google's line). The request has
                // been running since the open router answered.
                val ed = openEdgesD
                val tally = IntArray(4)
                val openChecked = (if (online && ed != null) kotlinx.coroutines.withTimeoutOrNull(if (urgent) OPEN_NAMES_WAIT_URGENT_MS else OPEN_NAMES_WAIT_MS) { ed.await() } else null)
                    ?.let { app.vela.core.data.ValhallaRouter.recheck(open.first(), it, keepUnplaced = true, tally = tally) }
                if (openChecked != null) runCatching { graph.log.i("VelaDirections", "open names (hybrid): kept ${tally[0]} renamed ${tally[1]} bare ${tally[2]} unplaced ${tally[3]}") }
                val openUsed = openChecked ?: open.first()
                // THE DRAWN LINE ON THE ROADS' MIDDLE: a stretch with no matched shape would be
                // drawn on Google's own line, which runs in the driving lane and hangs off a
                // street drawn from OpenStreetMap. Its points are moved onto the map's roads
                // where one is within RoadCenter.MAX_OFF_M, from the tiles the naming already
                // read (nothing is requested for this), and left alone past that.
                val unshaped = hybridStretches.filter { matchedShapes[it] == null }
                val roads = unshaped.flatMap { app.vela.core.data.naming.RoadNameTiles.roadsAlong(pieceOf(it), fetchMissing = false, maxTiles = DRAW_ROADS_MAX_TILES).orEmpty() }
                nudgedM.store(0)
                val nudge: ((List<LatLng>) -> List<LatLng>)? = if (roads.isEmpty()) null else { piece ->
                    app.vela.core.data.naming.RoadCenter.nudgeCounted(piece, roads).let { (line, movedM) -> nudgedM.addAndFetch(movedM); line }
                }
                app.vela.core.data.naming.HybridRoute.stitch(gTop!!, openUsed, named.map { it.first to it.second!! }, untrusted.toList())
                    ?.let { r -> r.copy(drawPolyline = app.vela.core.data.naming.HybridRoute.drawLine(gTop.polyline, openUsed.polyline, hybridStretches, matchedShapes.snapshot(), nudge)) }
            }
            // Anything the matching or the stitch throws costs the hybrid, never the route: the
            // paths below it still answer. (A cancellation is the deadline or the caller, and passes.)
            suspend fun hybridOrNull(online: Boolean): Route? = try { hybridOf(online) } catch (c: kotlinx.coroutines.CancellationException) { throw c } catch (t: Throwable) {
                runCatching { graph.log.w("VelaDirections", "hybrid failed: ${t::class.simpleName}") }
                null
            }
            var namedInTime = false
            val hybridBuilt = if (hybridStretches.isEmpty()) null else
                kotlinx.coroutines.withTimeoutOrNull(if (urgent) HYBRID_WAIT_URGENT_MS else HYBRID_WAIT_MS) { hybridOrNull(online = true).also { namedInTime = true } }
                    ?: hybridOrNull(online = false)
            for (st in hybridStretches) {
                val r = namer.result(st) ?: continue
                when (r.source) {
                    app.vela.core.data.naming.StretchNamer.Source.MATCHED -> {
                        stretchSource[0]++
                        if (r.lanes) stretchSource[3]++
                        for (k in 0..2) stretchNames[k] += r.names[k]
                        if (r.noEdges) stretchNames[3]++
                    }
                    app.vela.core.data.naming.StretchNamer.Source.TILES -> stretchSource[1]++
                    app.vela.core.data.naming.StretchNamer.Source.BARE -> stretchSource[2]++
                }
            }
            // How the steps were made rides on the route into the trip file (Route.made): which
            // source named each stretch, how long it took, and whether the deadline passed first.
            val hybrid = hybridBuilt?.copy(
                made = listOfNotNull(
                    "open=${open.first().source.name.lowercase()}${open.first().maneuvers.size}",
                    "stretches=${hybridStretches.size}",
                    "stretchM=${hybridStretches.sumOf { it.toM - it.fromM }.toInt()}",
                    "matched=${stretchSource[0]}", "tiled=${stretchSource[1]}", "bare=${stretchSource[2]}", "lanes=${stretchSource[3]}",
                    "naming=${graph.clock.nowMillis() - tHybrid}ms",
                    "nudged=${nudgedM.load()}m".takeIf { nudgedM.load() > 0 },
                    "namingLate".takeIf { !namedInTime },
                    "urgent".takeIf { urgent },
                ).joinToString(";"),
                // A stretch that went out bare is asked for again during the drive (RouteHeal).
                namesShort = !namedInTime || stretchSource[2] > 0,
            )
            if (hybridStretches.isNotEmpty()) runCatching {
                graph.log.i("VelaDirections", "google line: ${hybridStretches.size} stretch(es) off the open route, " +
                    "${hybridStretches.sumOf { it.toM - it.fromM }.toInt()} m of ${gLineM.toInt()} m (Google states ${gTop?.distanceMeters?.toInt()} m), " +
                    (if (hybrid != null) "hybrid ${hybrid.maneuvers.size} steps (open ${open.first().maneuvers.size}); stretches matched ${stretchSource[0]} (${stretchSource[3]} with lane detail), from tiles ${stretchSource[1]}, bare ${stretchSource[2]}; their turn names kept ${stretchNames[0]} renamed ${stretchNames[1]} dropped ${stretchNames[2]}, no edges for ${stretchNames[3]}, off the line in ${untrusted.size} place(s), ${nudgedM.load()} m drawn on the roads' middle" else "NOT placed, older path") +
                    " in ${graph.clock.nowMillis() - tHybrid} ms")
                // Do the steps describe Google's line? Counts only (StepAudit).
                if (hybrid != null) {
                    val audit = app.vela.core.nav.StepAudit.check(hybrid)
                    graph.log.i("VelaDirections", audit.summary())
                    // The whole list with where each step came from, for reading a trip by hand:
                    // adb shell setprop log.tag.VelaSteps DEBUG. Distances along the route only.
                    if (graph.log.isLoggable("VelaSteps", LogLevel.DEBUG)) {
                        var at = 0.0
                        hybrid.maneuvers.forEach { m ->
                            val from = if (hybridStretches.any { at >= it.fromM && at <= it.toM }) "stretch" else "open"
                            graph.log.d("VelaSteps", "${at.toInt()} m [$from] ${m.type} len=${m.distanceMeters.toInt()} lanes=${m.lanes.size} | ${m.instruction}")
                            at += m.distanceMeters
                        }
                        hybridStretches.forEach { graph.log.d("VelaSteps", "stretch ${it.fromM.toInt()}..${it.toM.toInt()} m") }
                        audit.findings.forEach { graph.log.d("VelaSteps", "audit ${it.atM.toInt()} m: ${it.what}") }
                    }
                }
            }
            val viaRoute = when {
                hybrid != null -> hybrid
                (!urgent || avoidWanted) && topDivergent -> RouteGeometry.routeVia(
                    routeHttp, listOf(origin) + RouteGeometry.sampleVias(gTop!!.polyline) + destination, mode,
                    avoidTolls, avoidHighways, avoidFerries, departBearingDeg, strictVias = true,
                    tries = tries, callTimeoutMs = osrmTryMs, budget = budget,
                ).firstOrNull()?.copy(source = RouteSource.OSRM_VIA_SNAP) // a trip log can tell a jam snap from a plain route
                else -> null
            }
            // Cheap checks first, the shape test last (it walks the whole route): the via route
            // must reach the destination and not be markedly LONGER than the course it followed
            // (a via that snapped to a side road adds a detour).
            val viaReaches = viaRoute != null && gTop != null &&
                viaRoute.polyline.lastOrNull()?.let { it.distanceTo(destination) <= SNAP_REACH_M } == true &&
                viaRoute.distanceMeters <= gTop.distanceMeters * SNAP_LENGTH_SLACK + SNAP_LENGTH_SLACK_M
            // The "appendix": a stretch that travels without progressing along Google's line,
            // then comes back. Refused only when a TURN or U-TURN sits on it - a loop ramp that
            // OSM draws in full and Google's line chords is the same shape without one (review
            // 2026-09-06), and a loop ramp is a MERGE/RAMP, never a U-turn.
            val trafficRoute = viaRoute?.takeIf { r ->
                viaReaches && !spurWithTurn(r, gTop!!.polyline)
            }
            // OFFLINE fallback: OSRM (and Google) need the network. When OSRM came back empty — no
            // connectivity, or the FOSSGIS server is down — route fully ON-DEVICE from a downloaded
            // obf region file, if one covers this area. No traffic offline, but complete named turns.
            // (Planning only: a bounded fetch with an empty open router returned above.)
            val onDevice = if (open.isEmpty() && trafficRoute == null && routeEngine.isReady(mode))
                routeEngine.route(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, departBearingDeg).map { it.copy(offline = true) } else emptyList()
            // Lead with Google's jam-avoiding path (option 3) only when it EARNS it: its live in-traffic
            // ETA is within a small margin of OSRM's FREE-FLOW best, so even Google's detour is time-
            // competitive → the jam is real. The old code led with the snap on ANY >700 m divergence, so a
            // longer/wonky snapped path could win even when it wasn't faster (the "fucky reroute"); now such
            // a snap steps aside for OSRM's clean route. (A true per-alternate re-rank isn't possible: Google
            // hands back ONE live-traffic figure, so applyTraffic scales every route by the same ratio and
            // can't reorder the OSRM alternates — this ETA gate is the meaningful lever.)
            val avoidTag = when {
                !avoidWanted -> ""
                gTop != null -> " avoid=google"
                else -> " avoid=none"
            }
            val googleEtaS = gTop?.durationInTrafficSeconds ?: gTop?.durationSeconds
            // The snapped via-route must actually REACH the destination — a truncated one ending at an
            // intermediate via (short ETA, wrong last step) is the "10 min away" nav bug — AND be time-
            // competitive with OSRM's free-flow best.
            val snapReaches = trafficRoute != null
            // One calibration for the whole response (issue #227): OSRM's free-flow model has no
            // signal timing, so on an arterial it runs far under Google's TYPICAL for the same
            // road. Taken from the route that FOLLOWS Google's course: the top OSRM route when it
            // does, else the via-snap, which follows Google's course by construction. Before the
            // 2026-09-12 review the divergent case (Google routing around a jam, exactly when it
            // matters) got no calibration at all, so the plain OSRM route kept its fiction of an
            // ETA and sorted ahead of Google's honest alternates as "Fastest". Alternates share
            // the same optimiztic speed model, so rebasing them all by one factor keeps the
            // picker's ranking fair.
            val freeFlowCal = gTop?.takeIf { it.durationSeconds > 0 && it.polyline.size >= 5 }?.let { g ->
                // Never the hybrid: its times ARE Google's, so it says nothing about the open
                // router's speed model, which is what this factor corrects.
                val basis = open.firstOrNull()?.takeIf { !RouteGeometry.divergent(it, g) }
                    ?: trafficRoute?.takeIf { it.source != RouteSource.GOOGLE_HYBRID && !RouteGeometry.divergent(it, g) }
                basis?.takeIf { it.durationSeconds > 0 }?.let { b ->
                    val dScale = if (g.distanceMeters > 0) b.distanceMeters / g.distanceMeters else 1.0
                    ((g.durationSeconds * dScale) / b.durationSeconds).coerceIn(0.5, 3.0)
                }
            }
            // With avoid on, the snap is the point (Google's avoiding course is slower than the
            // open router's unrestricted one by construction), so the ETA margin test is skipped.
            // The margin compares Google's live ETA against OSRM's CALIBRATED free-flow: the raw
            // free-flow is the very number the calibration exists to correct, and judged against
            // it a jam-avoiding snap lost to the fiction every time.
            // The hybrid is Google's own line, the route Google would drive: it leads without the
            // margin test, which exists to keep a wonky SNAPPED path from winning.
            val snapWorthIt = trafficRoute != null && snapReaches && open.isNotEmpty() && googleEtaS != null &&
                (avoidWanted || hybrid != null || googleEtaS <= open.first().durationSeconds * (freeFlowCal ?: 1.0) * SNAP_ETA_MARGIN)
            // Avoid on, Google answered, but the open router could not be led along its course:
            // Google's own (abbreviated) steps beat a plain route that ignores the avoid.
            // Only when the open route actually left Google's avoiding course; when it already
            // follows it (no toll or motorway on the way anyway), the open route with its full
            // named turns IS the avoiding route (review 2026-09-06: this used to throw it away).
            val avoidFallbackToGoogle = avoidWanted && gTop != null && !snapWorthIt && topDivergent
            diag.record(
                "directions",
                "$mode → OSRM ${open.size} routes / ${open.firstOrNull()?.maneuvers?.size ?: 0} steps; " +
                    "google ${google.size} (typ=${gTop?.durationSeconds?.toInt()}s traf=${gTop?.durationInTrafficSeconds?.toInt()}s spans=${gTop?.trafficSpans?.size} " +
                    "ratio=${gTop?.durationInTrafficSeconds?.let { t -> gTop?.durationSeconds?.takeIf { it > 0 }?.let { Fmt.fixed(t / it, 2) } }}); " +
                    "rerouted=${trafficRoute != null} hybrid=${hybrid != null} stretches=${hybridStretches.size} (matched ${stretchSource[0]} tiles ${stretchSource[1]} bare ${stretchSource[2]}) snapKept=$snapWorthIt snapReaches=$snapReaches " +
                    "(gEta=${googleEtaS?.toInt()}s osrmFF=${open.firstOrNull()?.durationSeconds?.toInt()}s " +
                    "sameCourse=${open.firstOrNull()?.let { t -> gTop?.takeIf { it.polyline.size >= 5 }?.let { !RouteGeometry.divergent(t, it) } }} " +
                    "cal=${freeFlowCal?.let { Fmt.fixed(it, 2) }}); " +
                    "onDevice=${onDevice.size}$avoidTag",
                "",
            )
            if (open.isEmpty()) {
                // OSRM unreachable → the on-device offline route, or Google's abbreviated one, whichever
                // we have. The Google routes are TAGGED abbreviated so an adopted one can be silently
                // upgraded to full steps by the nav recheck once the open router recovers.
                if (onDevice.isNotEmpty()) onDevice else google.map { it.copy(abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED) }
            } else {
                if (avoidFallbackToGoogle) return@coroutineScope google.map { it.copy(abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED) }
                // With avoid on, the open router's unrestricted routes are not offered as alternates.
                // With the hybrid leading, which of the open router's routes are still offered:
                // none of them when Google went a genuinely different way (their times are the
                // open router's uncalibrated free-flow, which would sort ahead of honest ones), and
                // not its top route otherwise (that is the way Google chose not to go, a closure
                // as far as anyone can tell, and on time it would tie and lead again).
                val openOffered = when {
                    avoidWanted -> emptyList()
                    hybrid != null -> if (topDivergent) emptyList() else open.drop(1)
                    else -> open
                }
                val primary = if (snapWorthIt) (listOf(applyTraffic(trafficRoute!!, gTop, if (hybrid != null) 1.0 else freeFlowCal)) + openOffered.map { applyTraffic(it, gTop, freeFlowCal) })
                    // Avoid on and the open router's top route already follows Google's avoiding
                    // course: that one route IS the avoiding route, but the open router's OTHER
                    // routes were computed with no avoid at all (it cannot exclude), so they are
                    // not offered, the same rule as the snapped branch. Before this they were, and
                    // with Google having honored the avoid, without the "may still use" note.
                    else (if (avoidWanted && gTop != null) open.take(1) else open).map { applyTraffic(it, gTop, freeFlowCal) }
                // ALTERNATES to choose from = Google's OWN alternate routes (the real, traffic-aware ones you
                // miss). Kept PROVISIONAL: their polyline + live ETA are shown now, but turn-by-turn is named
                // only when you PICK one to drive ([nameRoute]) — so the picker loads fast and we never snap a
                // route you don't take. Google's routes already carry duration_in_traffic + congestion spans.
                val googleAlts = google.drop(1).filter { it.polyline.size >= 5 }.map { it.copy(provisional = true, source = RouteSource.GOOGLE_PROVISIONAL) }
                // Rank by live in-traffic ETA so the FASTEST-right-now route leads (Google-style), sorting by
                // the EXACT value the picker shows (`durationInTrafficSeconds ?: durationSeconds`, RouteOption)
                // so the top/selected route is always the one the picker tags "Fastest" — otherwise the sort
                // and the displayed times disagree and the fastest-shown route isn't at the top (the bug).
                // The traffic axis is already fair without a fudge factor: PRIMARY routes are run through
                // applyTraffic above (their durationInTrafficSeconds = free-flow × the top Google route's
                // in-traffic ratio), and Google's own alternates carry their real per-route duration_in_traffic
                // — so a route only falls back to raw durationSeconds when there's genuinely no traffic signal
                // for it, and then showing/sorting that free-flow time is the honest, self-consistent fallback.
                // Dedupe by path (keeps the fastest of look-alikes) + cap so the picker stays short.
                dedupeRoutes(
                    (listOf(primary.first()) + googleAlts + primary.drop(1))
                        .sortedWith(
                            compareBy(
                                { it.durationInTrafficSeconds ?: it.durationSeconds },
                                { it.provisional }, // stable tie-break: a fully-named route leads over a provisional look-alike
                            ),
                        ),
                ).take(MAX_ROUTES)
            }
        }
        // The open router's turn names, checked against the road pieces under its line: a turn
        // whose street is not the one the line is on right after it is renamed or goes out bare
        // (ValhallaRouter.recheck). Only the route on that very line; the hybrid's carried-over
        // steps were checked before the stitch. No answer in time = the names stand.
        val planned = openEdgesD?.let { d ->
            val t0 = graph.clock.nowMillis()
            val edges = kotlinx.coroutines.withTimeoutOrNull(if (urgent) OPEN_NAMES_WAIT_URGENT_MS else OPEN_NAMES_WAIT_MS) { d.await() }
                ?: return@let null
            // The open router drove through a farm track: its route goes, and the other
            // service's car route takes its place (ValhallaRouter.driveRoute). Only when that
            // route answers in time and is no great detour; otherwise the open route stands.
            val trackM = app.vela.core.data.ValhallaRouter.throughTrackM(edges)
            val onOpenLine = fetched.firstOrNull { it.polyline === openLine }
            val offTrack = if (trackM >= THROUGH_TRACK_MIN_M && onOpenLine != null) withContext(ioDispatcher) {
                app.vela.core.data.ValhallaRouter.driveRoute(
                    openHttp, listOf(origin, destination), avoidTolls, avoidHighways, avoidFerries, timeoutMs = if (urgent) OFF_TRACK_WAIT_URGENT_MS else OFF_TRACK_WAIT_MS,
                )
            }?.takeIf { it.distanceMeters <= onOpenLine.distanceMeters * OFF_TRACK_MAX_RATIO + OFF_TRACK_MAX_EXTRA_M } else null
            if (trackM >= THROUGH_TRACK_MIN_M) runCatching {
                graph.log.i("VelaDirections", "open route drives ${trackM.toInt()} m of track: " +
                    (if (offTrack != null) "replaced, ${offTrack.distanceMeters.toInt()} m for ${onOpenLine?.distanceMeters?.toInt()} m" else if (onOpenLine == null) "not offered" else "kept, no other route in time"))
            }
            if (offTrack != null) return@let dedupeRoutes(fetched.map { r -> if (r === onOpenLine) offTrack.copy(durationInTrafficSeconds = null) else r })
            val tally = IntArray(4)
            fetched.map { r ->
                if (r.polyline === openLine)
                    app.vela.core.data.ValhallaRouter.recheck(r, edges, keepUnplaced = true, tally = tally)
                        .let { it.copy(made = "openNames=kept${tally[0]}renamed${tally[1]}bare${tally[2]}unplaced${tally[3]}") } else r
            }.also {
                runCatching { graph.log.i("VelaDirections", "open names: kept ${tally[0]} renamed ${tally[1]} bare ${tally[2]} unplaced ${tally[3]}, waited ${graph.clock.nowMillis() - t0} ms more") }
            }
        } ?: fetched
        if ((avoidTolls || avoidHighways || avoidFerries) && mode == TravelMode.DRIVE && !avoidHonored) {
            planned.map { it.copy(avoidNotHonored = true) }
        } else planned
    }

    /**
     * The other open service's car route through [points] when [open], the open router's own
     * line, drives through a farm track; null when it does not, or when nothing better answers
     * in time. Two requests at most, both bounded. A line past the matcher's 200 km is not
     * checked: the edge request fails and the open route stands.
     */
    private suspend fun offTrackRoute(
        open: Route, points: List<LatLng>, avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean,
    ): Route? {
        if (open.source != RouteSource.OSRM) return null
        val edges = runCatching { ValhallaRouter.edges(openHttp, open.polyline, timeoutMs = if (urgent) 1_000 else 2_500) }.getOrNull() ?: return null
        val trackM = ValhallaRouter.throughTrackM(edges)
        if (trackM < THROUGH_TRACK_MIN_M) return null
        val other = ValhallaRouter.driveRoute(
            openHttp, points, avoidTolls, avoidHighways, avoidFerries, timeoutMs = if (urgent) OFF_TRACK_WAIT_URGENT_MS else OFF_TRACK_WAIT_MS,
        )?.takeIf { it.distanceMeters <= open.distanceMeters * OFF_TRACK_MAX_RATIO + OFF_TRACK_MAX_EXTRA_M }
        runCatching {
            graph.log.i("VelaDirections", "open route through ${points.size - 2} stop(s) drives ${trackM.toInt()} m of track: " +
                if (other != null) "replaced, ${other.distanceMeters.toInt()} m for ${open.distanceMeters.toInt()} m" else "kept, no other route in time")
        }
        return other
    }

    /**
     * Safety-weighted bike routes (issue #401). The on-device bicycle profile prefers signed cycle
     * routes and lanes and needs no network, so where a downloaded region covers the trip it is the
     * router, consistently, for planning and for every reroute; it is BOUNDED like the avoid branch
     * (the obf engine can spend seconds on a long route and the chooser must not hang), and past
     * the deadline the online router answers. Online that is FOSSGIS Valhalla with low `use_roads`
     * ([ValhallaRouter]); alternates only for a plain trip. No Google traffic overlay: bikes do not
     * sit in car traffic and Google's bike ETA models a different route. Null when nothing answered.
     */
    /**
     * Walking (issue #478): the open router's foot routes, plus Google's walk only when it is at least
     * [WALK_GOOGLE_SHORTER] shorter (OSM missing a crossing or a path), and then with its own line
     * kept and its steps named from the map tiles ([LineNamer]), never snapped. Null = the open
     * router gave nothing and Google's walk could not be named, so the general chain below runs.
     */
    private suspend fun walkRoutes(
        origin: LatLng, destination: LatLng, tries: Int, osrmTryMs: Long?, osrmBudget: RouteBudget,
        onOsrmFail: (String) -> Unit, urgent: Boolean,
    ): List<Route>? = coroutineScope {
        val openD = async {
            RouteGeometry.route(routeHttp, origin, destination, TravelMode.WALK, tries = tries, callTimeoutMs = osrmTryMs, budget = osrmBudget, onFailure = onOsrmFail)
        }
        val googleD = async {
            if (urgent || !app.vela.core.data.RoutingPrefs.googleTraffic) emptyList()
            else kotlinx.coroutines.withTimeoutOrNull(WALK_GOOGLE_WAIT_MS) {
                runCatching { googleDirections(origin, destination, TravelMode.WALK, walkCompare = true) }.getOrNull().orEmpty()
            }.orEmpty()
        }
        val open = openD.await()
        val gTop = googleD.await().firstOrNull()
        val openTop = open.firstOrNull()
        val shorter = gTop != null && gTop.polyline.size >= 2 && googleWalkIsShorter(openTop?.distanceMeters, gTop.distanceMeters)
        val t0 = graph.clock.nowMillis()
        var tilesMs = 0L
        var tileLines = 0
        val named = if (shorter) {
            kotlinx.coroutines.withTimeoutOrNull(WALK_NAME_WAIT_MS) {
                val lines = app.vela.core.data.naming.RoadNameTiles.linesAlong(gTop!!.polyline)
                tilesMs = graph.clock.nowMillis() - t0
                tileLines = lines?.size ?: -1
                lines?.let { app.vela.core.data.naming.LineNamer.name(gTop, it, TravelMode.WALK) }
            }
        } else null
        val line = "walk: open ${openTop?.distanceMeters?.toInt()} m, google ${gTop?.distanceMeters?.toInt()} m" +
            (if (shorter) (if (named != null) ", google named (${named.maneuvers.size} steps)" else ", google shorter but not named") else "") +
            (if (shorter) " tiles ${tilesMs} ms ($tileLines lines), named share ${app.vela.core.data.naming.LineNamer.lastNamedShare.fixedInDefaultLocale(2)}, total ${graph.clock.nowMillis() - t0} ms" else "")
        diag.record("directions", line)
        graph.log.d("VelaWalk", line)
        when {
            named != null -> listOf(named) + open
            open.isNotEmpty() -> open
            else -> null
        }
    }

    private suspend fun bikeSafeRoutes(
        origin: LatLng,
        destination: LatLng,
        waypoints: List<LatLng>,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
        urgent: Boolean,
    ): List<Route>? {
        val mode = TravelMode.BICYCLE
        val points = listOf(origin) + waypoints + destination
        if (routeEngine.isReady(mode)) {
            val budget = if (urgent) BIKE_ONDEVICE_URGENT_MS else BIKE_ONDEVICE_TIMEOUT_MS
            val onDeviceD = kotlinx.coroutines.CoroutineScope(ioDispatcher).async {
                runCatching {
                    if (waypoints.isEmpty()) routeEngine.route(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, maxMs = budget).map { it.copy(offline = true) }
                    else listOfNotNull(chainOnDevice(points, mode, avoidTolls, avoidHighways, avoidFerries, maxMs = budget))
                }.getOrDefault(emptyList())
            }
            val onDevice = kotlinx.coroutines.withTimeoutOrNull(budget) { onDeviceD.await() } ?: emptyList()
            if (onDevice.isNotEmpty()) {
                diag.record("directions", "BICYCLE safe → on-device ${onDevice.size} routes / ${onDevice.first().maneuvers.size} steps", "")
                return onDevice
            }
        }
        val online = ValhallaRouter.route(openHttp, points, alternates = waypoints.isEmpty(), tries = if (urgent) 1 else 2)
        if (online.isNotEmpty()) {
            diag.record("directions", "BICYCLE safe → valhalla ${online.size} routes / ${online.first().maneuvers.size} steps", "")
            return online
        }
        diag.record("directions", "BICYCLE safe → nothing answered, falling to the fastest chain", "")
        return null
    }

    /**
     * Whether Google's walk is offered: it is at least [WALK_GOOGLE_SHORTER] shorter than the open
     * foot route, or the open router gave nothing at all (SPEC 4.3). Kept as one function so the
     * threshold has a single definition and a JVM test can read the same rule the chooser uses.
     */
    fun googleWalkIsShorter(openMeters: Double?, googleMeters: Double): Boolean =
        openMeters == null || googleMeters <= openMeters * (1.0 - WALK_GOOGLE_SHORTER)

    /** True when [RouteGeometry.spurAt] finds a spur on [route] AND one of the route's own
     *  maneuvers within [SPUR_TURN_NEAR_M] of it is a turn or U-turn. */
    /**
     * The open router's own steps (lane arrows, exits, renames) for a path the map matcher
     * returned, or null when the open router cannot be shown to drive that same path. Vias sit
     * mid-step on the matched line, at most [LANE_VIAS_MAX], each with the line's heading.
     */
    private suspend fun laneDetail(matched: Route, tryMs: Long?, trimStartM: Double = 0.0, trimEndM: Double = 0.0): Pair<List<app.vela.core.model.Maneuver>, Boolean>? {
        val whole = matched.polyline
        if (whole.size < 2) return null
        val wholeCum = app.vela.core.nav.RouteProjection.cumulative(whole)
        val total = wholeCum.last()
        val from = trimStartM.coerceAtMost(total / 3); val to = total - trimEndM.coerceAtMost(total / 3)
        val trimmed = from > 0.0 || to < total
        // At a trip's ends the matched path runs through a parking lot the open router will not
        // drive, and one refused point used to cost the whole stretch its lanes: the open router
        // is asked only for the part past the lot.
        val line = if (trimmed) app.vela.core.data.naming.HybridRoute.slice(whole, from, to) else whole
        if (line.size < 2) return null
        val cum = app.vela.core.nav.RouteProjection.cumulative(line)
        var at = 0.0
        val mids = ArrayList<Double>()
        for (m in matched.maneuvers) {
            val mid = at + m.distanceMeters / 2
            if (m.distanceMeters >= LANE_VIA_MIN_STEP_M && mid > from + 20.0 && mid < to - 20.0) mids += mid - from
            at += m.distanceMeters
        }
        val picked = if (mids.size <= LANE_VIAS_MAX) mids else (0 until LANE_VIAS_MAX).map { mids[it * (mids.size - 1) / (LANE_VIAS_MAX - 1)] }
        val vias = picked.map { app.vela.core.nav.RouteProjection.pointAt(line, cum, it) }
        val pts = listOf(line.first()) + vias + line.last()
        val bearings = listOf(RouteGeometry.headingOnLine(line, line.first())) + vias.map { RouteGeometry.headingOnLine(line, it) } + listOf<Double?>(null)
        val r = RouteGeometry.routeVia(
            routeHttp, pts, TravelMode.DRIVE, strictVias = true, tries = 1, callTimeoutMs = tryMs ?: 3_000, waypointBearings = bearings,
        ).firstOrNull() ?: return null
        if (!trimmed && ValhallaRouter.followsLine(r.polyline, line, LANE_SAME_PATH_M)) return r.maneuvers to true
        // Not the same path end to end (or only part of it was asked for): take the open router's
        // LANES step by step, wherever it makes the same turn at the same junction and its path
        // through that junction is the matched path.
        val grid = RouteGeometry.SegmentGrid(whole, wholeCum)
        val rCum = app.vela.core.nav.RouteProjection.cumulative(r.polyline)
        fun side(t: app.vela.core.model.ManeuverType) = when { t.name.endsWith("LEFT") -> -1; t.name.endsWith("RIGHT") -> 1; else -> 0 }
        var rAt = 0.0
        val laned = r.maneuvers.mapNotNull { o ->
            val here = rAt; rAt += o.distanceMeters
            if (o.lanes.isEmpty()) return@mapNotNull null
            val through = listOf(-60.0, -30.0, 30.0, 60.0).all { d ->
                val x = here + d
                x < 0.0 || x > rCum.last() || grid.along(app.vela.core.nav.RouteProjection.pointAt(r.polyline, rCum, x), LANE_BORROW_PATH_M) != null
            }
            if (through) o else null
        }
        if (laned.isEmpty()) return null
        var any = false
        val out = matched.maneuvers.map { m ->
            val o = laned.filter { it.location.distanceTo(m.location) <= LANE_BORROW_AT_M && side(it.type) == side(m.type) }
                .minByOrNull { it.location.distanceTo(m.location) } ?: return@map m
            any = true
            m.copy(lanes = o.lanes, laneHint = o.laneHint ?: m.laneHint)
        }
        return if (any) out to false else null
    }

    private fun spurWithTurn(route: Route, course: List<LatLng>): Boolean {
        val at = RouteGeometry.spurAt(route.polyline, course) ?: return false
        val cum = app.vela.core.nav.RouteProjection.cumulative(route.polyline)
        val idx = cum.indexOfFirst { it >= at }.let { if (it < 0) route.polyline.lastIndex else it }
        val here = route.polyline[idx]
        return route.maneuvers.any { m ->
            (m.type == app.vela.core.model.ManeuverType.UTURN || m.type.name.startsWith("TURN")) &&
                m.location.distanceTo(here) <= SPUR_TURN_NEAR_M
        }
    }

    /** Drop routes that follow ~the same path as an earlier one (keeps the picker to genuinely distinct
     *  choices). Order is preserved, so the primary stays first. */
    private fun dedupeRoutes(routes: List<Route>): List<Route> {
        val kept = mutableListOf<Route>()
        for (r in routes) if (kept.none { routesSimilar(it, r) }) kept += r
        return kept
    }

    /** Two routes are "the same" if a handful of points sampled along one all sit within ~150 m of the
     *  other's line — i.e. they trace essentially the same roads. */
    private fun routesSimilar(a: Route, b: Route): Boolean {
        if (a.polyline.size < 2 || b.polyline.size < 2) return false
        return (1..4).all { k ->
            val p = b.polyline[(b.polyline.size * k / 5).coerceIn(0, b.polyline.size - 1)]
            a.polyline.minOf { p.distanceTo(it) } < 150.0
        }
    }

    /** Overlay Google's live-traffic ETA + congestion onto an open-router [route] (best-effort):
     *  scale the route's free-flow duration by Google's in-traffic/typical ratio, and map its
     *  congestion spans onto the open geometry by fraction. No Google traffic → keep free-flow. */
    private fun applyTraffic(route: Route, g: Route?, freeFlowCal: Double? = null, withSpans: Boolean = true): Route {
        val typical = g?.durationSeconds?.takeIf { it > 0 } ?: return route
        val inTraffic = g.durationInTrafficSeconds ?: return route
        val factor = (inTraffic / typical).coerceIn(0.5, 4.0)
        val scale = if (g.distanceMeters > 0) route.distanceMeters / g.distanceMeters else 1.0
        // FREE-FLOW CALIBRATION (issue #227): OSRM's speed model has no signal timing, so on
        // signalized arterials its free-flow time can run far below Google's TYPICAL for the very
        // same road (a reporter's diag: OSRM 16 min where Google's typical was 30 with a traffic
        // ratio of ~0.97 — the shown ETA was the ratio applied to the wrong baseline). When this
        // route follows Google's course, rebase it onto Google's typical: step/leg/route durations
        // scale up to the typical time (so nav's remaining-time sums agree), the live ETA becomes
        // Google's actual in-traffic figure, and trafficRatio stays traffic-vs-typical (colors
        // don't turn red just because OSRM was optimiztic). A divergent route (a genuinely
        // different path) can inherit the caller's calibration (the bias is the road network's,
        // not one route's); with none it keeps the old ratio-only overlay.
        val sameCourse = route.durationSeconds > 0 && route.polyline.size >= 2 &&
            g.polyline.size >= 5 && !RouteGeometry.divergent(route, g)
        val cal = freeFlowCal ?: if (sameCourse) ((typical * scale) / route.durationSeconds).coerceIn(0.5, 3.0) else 1.0
        val calibrated = if (cal == 1.0) route else route.copy(
            durationSeconds = route.durationSeconds * cal,
            legs = route.legs.map { leg ->
                leg.copy(
                    durationSeconds = leg.durationSeconds * cal,
                    maneuvers = leg.maneuvers.map { m -> m.copy(durationSeconds = m.durationSeconds * cal) },
                )
            },
        )
        return calibrated.copy(
            durationInTrafficSeconds = calibrated.durationSeconds * factor,
            // Google's per-leg times belong to its course too, stretched like its typical.
            legTimes = if (sameCourse && g.legTimes.isNotEmpty()) g.legTimes.map {
                it.copy(distanceMeters = it.distanceMeters * scale, typicalSeconds = it.typicalSeconds * scale, trafficSeconds = it.trafficSeconds?.times(scale))
            } else route.legTimes,
            // Google's "usually X-Y" typical range belongs to its course; on a same-course route the
            // primary's durationSeconds IS Google's typical now, so the range applies to it too and
            // the depart-time chooser can show it (before, only provisional alternates had one).
            typicalLowSeconds = if (sameCourse) g.typicalLowSeconds?.times(scale) else route.typicalLowSeconds,
            typicalHighSeconds = if (sameCourse) g.typicalHighSeconds?.times(scale) else route.typicalHighSeconds,
            // Google's congestion spans belong to Google's course: mapped by fraction onto a route
            // that takes different roads they painted red segments on roads Google never reported
            // on (review 2026-09-06).
            // Same course: Google's spans map by fraction. Any other geometry (a divergent open
            // route, an alternate, a trip with stops): carry the spans over wherever the two
            // share the road (issue #403); the stretches Google did not drive stay uncolored.
            trafficSpans = when {
                !withSpans -> emptyList()
                sameCourse -> g.trafficSpans.map { it.copy(startMeters = it.startMeters * scale, lengthMeters = it.lengthMeters * scale) }
                else -> RouteGeometry.transferSpans(g, route)
            },
        )
    }

    /** Offline multi-stop: route each leg (origin→w1, w1→w2, …, wn→dest) on the on-device engine and
     *  stitch them into ONE continuous route — polylines joined (dropping each leg's duplicated joint
     *  point), each non-final leg's ARRIVE and non-first leg's DEPART dropped (mirroring what routeVia's
     *  parser does for via boundaries), distances/durations summed. Null if any leg can't be routed
     *  (cross-region or off-graph), so the caller can fall through. */
    private fun chainOnDevice(
        points: List<LatLng>,
        mode: TravelMode,
        avoidTolls: Boolean = false,
        avoidHighways: Boolean = false,
        avoidFerries: Boolean = false,
        departBearingDeg: Double? = null,
        maxMs: Long? = null,
    ): Route? {
        val startMs = graph.clock.nowMillis()
        val legs = points.zipWithNext().mapIndexed { i, (a, b) ->
            // Only the first leg starts where the car is pointing; a stop is just a place.
            val bearing = if (i == 0) departBearingDeg else null
            // One limit for the whole chain: each leg gets what is left of it.
            val left = maxMs?.let { it - (graph.clock.nowMillis() - startMs) }
            runCatching { routeEngine.route(a, b, mode, avoidTolls, avoidHighways, avoidFerries, bearing, maxMs = left).firstOrNull()?.copy(offline = true) }.getOrNull() ?: return null
        }
        val polyline = legs.flatMapIndexed { i, leg -> if (i == 0) leg.polyline else leg.polyline.drop(1) }
        // Boundary DEPART/ARRIVE steps are dropped, but their step distance is FOLDED into the
        // last kept maneuver so step lengths keep TILING the stitched polyline — NavEngine locates
        // each maneuver by a prefix-sum of them (same fold as parseOsrmRoute's via filter).
        val maneuvers = mutableListOf<app.vela.core.model.Maneuver>()
        legs.forEachIndexed { i, leg ->
            leg.maneuvers.forEach { m ->
                val boundary = (m.type == app.vela.core.model.ManeuverType.ARRIVE && i != legs.lastIndex) ||
                    (m.type == app.vela.core.model.ManeuverType.DEPART && i != 0)
                if (!boundary) {
                    maneuvers += m
                } else if (maneuvers.isNotEmpty() && (m.distanceMeters > 0.0 || m.durationSeconds > 0.0)) {
                    val prev = maneuvers.removeAt(maneuvers.lastIndex)
                    maneuvers += prev.copy(distanceMeters = prev.distanceMeters + m.distanceMeters, durationSeconds = prev.durationSeconds + m.durationSeconds)
                }
            }
        }
        if (polyline.size < 2 || maneuvers.size < 2) return null
        val dist = legs.sumOf { it.distanceMeters }
        val dur = legs.sumOf { it.durationSeconds }
        return Route(
            polyline = polyline,
            legs = listOf(app.vela.core.model.RouteLeg(dist, dur, null, maneuvers)),
            distanceMeters = dist,
            durationSeconds = dur,
            durationInTrafficSeconds = null, // offline: no live traffic
            legTimes = legs.map { app.vela.core.model.LegTime(it.distanceMeters, it.durationSeconds, null) },
            summary = legs.firstOrNull()?.summary,
            offline = true,
            source = legs.firstOrNull()?.source ?: RouteSource.UNKNOWN,
        )
    }

    /** Free-flow calibration for a route that does NOT follow Google's course (a stops trip is
     *  routed through its stops while Google's keyless answer is the direct trip): compare average
     *  SPEEDS instead of times, so the distance difference cancels and what is left is the speed
     *  model's bias for that network. Null when either side lacks a duration or a distance. */
    private fun speedCal(route: Route, g: Route?): Double? {
        if (g == null || g.durationSeconds <= 0 || g.distanceMeters <= 0 || route.durationSeconds <= 0 || route.distanceMeters <= 0) return null
        val gSpeed = g.distanceMeters / g.durationSeconds
        val rSpeed = route.distanceMeters / route.durationSeconds
        return (rSpeed / gSpeed).coerceIn(0.5, 3.0)
    }

    /** Name a provisional alternate the moment the user picks it to drive: snap its (Google) polyline
     *  through OSRM for real named turn-by-turn, guarded to reach the destination, and re-apply Google's
     *  live-traffic overlay. Failure keeps Google's own (abbreviated) steps so nav still works.
     *  (An on-device map-match for downloaded regions could plug in here next.) */
    override suspend fun nameRoute(route: Route, origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean): Route {
        val named = nameRoutePlain(route, origin, destination, mode, avoidTolls, avoidHighways, avoidFerries)
        return if (mode == TravelMode.DRIVE) io { withLotTurn(named, urgent = false) } else named
    }

    private suspend fun nameRoutePlain(route: Route, origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean): Route = io {
        if (!route.provisional || route.polyline.size < 3) return@io route.copy(provisional = false)
        val vias = listOf(origin) + RouteGeometry.sampleVias(route.polyline) + destination
        // The avoid flags ride along on the snap, but they add nothing on the public server:
        // OSRM_SUPPORTS_EXCLUDE is off, so no `exclude=` is sent and the vias alone hold the
        // snap to Google's chosen path.
        // The traffic snap's guards (issue #478): a sampled point that lands on a flyover deck, the
        // far carriageway or a dead-end lane forces an out-and-back or a loop, so the snap must reach
        // the destination, stay within SNAP_LENGTH_SLACK of the route it names, and carry no spur.
        val named = RouteGeometry.routeVia(routeHttp, vias, mode, avoidTolls, avoidHighways, avoidFerries, strictVias = true).firstOrNull()
            ?.takeIf { it.polyline.lastOrNull()?.let { p -> p.distanceTo(destination) <= SNAP_REACH_M } == true }
            ?.takeIf { it.distanceMeters <= route.distanceMeters * SNAP_LENGTH_SLACK + SNAP_LENGTH_SLACK_M }
            ?.takeIf { !spurWithTurn(it, route.polyline) }
        // Keep the route's OWN time figures through the snap. The picker sorted and displayed this
        // route by its Google per-route ETA; applyTraffic here would swap in a recomputed one
        // (OSRM free-flow x the ratio) IN PLACE, which can leapfrog a neighboring row and leave
        // the "Fastest" tag sitting below a slower first row. Naming is for geometry + named
        // turn-by-turn (and the congestion spans remapped onto that geometry), not a new ETA.
        if (named != null) applyTraffic(named, route).copy(
            provisional = false,
            source = RouteSource.OSRM_VIA_SNAP,
            durationSeconds = route.durationSeconds,
            durationInTrafficSeconds = route.durationInTrafficSeconds,
        )
        // The snap failed or was refused: keep Google's line and name its turns from the map tiles
        // (LineNamer). Only when that fails too does nav run on Google's abbreviated steps, tagged so
        // the in-drive recheck can silently upgrade to full steps once the open router answers.
        else kotlinx.coroutines.withTimeoutOrNull(WALK_NAME_WAIT_MS) {
            app.vela.core.data.naming.RoadNameTiles.linesAlong(route.polyline)
                ?.let { app.vela.core.data.naming.LineNamer.name(route, it, mode) }
        } ?: route.copy(provisional = false, abbreviatedSteps = true, source = RouteSource.GOOGLE_ABBREVIATED)
    }

    override suspend fun withShortLinesDrawn(routes: List<Route>, origin: LatLng, destination: LatLng, mode: TravelMode): List<Route> {
        val geoms = RouteGeometry.fetchAll(routeHttp, origin, destination, mode)
        return routes.mapIndexed { i, r ->
            if (r.polyline.size > 2) r
            else RouteGeometry.reposition(r, geoms.getOrNull(i) ?: listOf(origin, destination))
        }
    }

    private companion object {
        // Cap on waiting for the on-device avoid route: the obf engine can take many seconds on a
        // long route, and the route chooser must not hang.
        const val AVOID_ONDEVICE_TIMEOUT_MS = 4_000L
        /** A mid-drive reroute waits this long for Google's traffic once the open router has answered. */
        const val URGENT_GOOGLE_GRACE_MS = 2_500L
        /** PHONE FIRST (2026-09-28): with a downloaded region under the whole trip, a mid-drive
         *  reroute starts the on-device route at once and takes it when the open router has not
         *  answered inside this wait; a healthy open router answers in 1 to 3 s, a hung one used to
         *  hold the driver on "Re-routing" for the attempt's whole deadline (issues #557, #258).
         *  The on-device route is trafficless, so the degraded recheck (20 s) swaps in the online
         *  route on the same course, or offers it as a faster route on another. */
        const val PHONE_FIRST_ONLINE_WAIT_MS = 2_500L
        /** How long past that the on-device compute may still take before the attempt goes back
         *  to waiting on the open router; a city reroute finishes well inside it. */
        const val PHONE_FIRST_ONDEVICE_WAIT_MS = 4_000L
        /** Issue #557: the urgent reroute's one open-router call, connect + read included. FOSSGIS
         *  answers a healthy reroute in 1-3 s; a hung call used to hold the attempt for the shared
         *  client's 12 s call timeout (and 15 s connect, 20 s read) before any fallback was asked. */
        const val URGENT_OSRM_TIMEOUT_MS = 6_000L
        /** An urgent fetch with no budget from the caller gets this much in total. */
        const val URGENT_DEFAULT_BUDGET_MS = 16_000L
        /** The escalated reroute's per-try open-router timeout, and the share of its budget the
         *  open router may use before the fallbacks get the rest. */
        const val LADDER_OSRM_TRY_MS = 8_000L
        const val LADDER_OSRM_SHARE = 0.55
        /** Room the escalated reroute keeps for the traffic snap after waiting on Google. */
        const val LADDER_SNAP_RESERVE_MS = 6_000L
        /** The bike-safe branch's on-device budgets (issue #401): a bike trip is short, so the obf
         *  engine usually answers well inside these; past them the online router takes over. */
        const val BIKE_ONDEVICE_TIMEOUT_MS = 6_000L
        const val BIKE_ONDEVICE_URGENT_MS = 3_000L
        // Follow Google's jam-avoiding reroute only if its live ETA is within this ×OSRM-free-flow-best
        // (its detour is time-competitive with OSRM's ideal → the jam justifies the reroute). Tunable from
        // real side-by-side data — the `directions` diag logs gEta/osrmFF so the threshold can be pinned.
        const val SNAP_ETA_MARGIN = 1.2
        /** How long naming the stretches where Google leaves the open route may take (tile
         *  fetches, usually cached and under a second) before the older paths are used. */
        /** The map-matching service refuses a line over 200 km; a stretch that long is rare
         *  (two routes that differ for hours) and goes to the tiles. */
        const val MATCH_MAX_M = 180_000.0
        /** Lane detail for a matched stretch: a via in the middle of every step at least this
         *  long, at most this many, and the open router's path within this of the matched one. */
        const val LANE_VIA_MIN_STEP_M = 80.0
        const val LANE_VIAS_MAX = 20
        const val LANE_SAME_PATH_M = 8.0
        /** How long the route waits, after Google is back, for the road pieces that check the
         *  open router's turn names. They were asked for when the open router answered. */
        /** How much of Google's line at the very start or end of the trip may sit off the matched
         *  path (the loop out of a parking lot, the last turn into a driveway). */
        const val MATCH_TRIP_END_SLACK_M = 150.0
        const val OPEN_NAMES_WAIT_MS = 1_500L
        /** A farm track driven through for less than this is matching noise, not a route choice. */
        const val THROUGH_TRACK_MIN_M = 30.0
        /** How long the car route that keeps off tracks may take to answer. */
        const val OFF_TRACK_WAIT_MS = 4_000L
        const val OFF_TRACK_WAIT_URGENT_MS = 1_500L
        /** It replaces the open route only up to this much longer: past it the track is the road. */
        const val OFF_TRACK_MAX_RATIO = 1.3
        const val OFF_TRACK_MAX_EXTRA_M = 2_000.0
        const val OPEN_NAMES_WAIT_URGENT_MS = 300L
        const val HYBRID_WAIT_MS = 5_500L // a match (2.5 s) and its lane detail (1.8 s) at their slowest
        /** How long a stretch's match may run before the map tiles under it are read as well, so
         *  the names are in hand if the match is late. The matcher answers a town stretch in 0.35
         *  to 1.2 s (replayed captured lines, 2026-10-09), so a healthy one costs no tile request. */
        const val TILE_HEDGE_MS = 1_000L
        /** How long a built route waits for the map's word on whether its last turn enters the
         *  destination's parking lot. The tiles are asked for when the fetch starts, so this is
         *  normally no wait at all. */
        const val LOT_WORD_WAIT_MS = 1_200L
        /** The most tiles whose roads are read to draw a stretch on the roads' middle (the same
         *  bound the street names have). */
        const val DRAW_ROADS_MAX_TILES = 48
        const val LOT_WORD_WAIT_URGENT_MS = 300L
        const val TILE_HEDGE_URGENT_MS = 300L
        /** Longer than any deadline: the tiles are read only once the match has failed. */
        const val TILE_HEDGE_NEVER_MS = 60_000L
        const val LANE_TRY_MS = 1_800L
        /** Borrowing lanes step by step: the open router's step within this of the matcher's, and
         *  its path within [LANE_BORROW_PATH_M] of the matched path 60 m either side. */
        const val LANE_BORROW_AT_M = 20.0
        const val LANE_BORROW_PATH_M = 12.0
        const val HYBRID_WAIT_URGENT_MS = 1_500L
        /** Google's walk is offered only this much shorter than the open router's (issue #478). */
        const val WALK_GOOGLE_SHORTER = 0.15
        private const val WALK_GOOGLE_WAIT_MS = 6_000L
        private const val WALK_NAME_WAIT_MS = 8_000L
        private const val SPUR_TURN_NEAR_M = 150.0
    private const val SNAP_LENGTH_SLACK = 1.05
        private const val SNAP_LENGTH_SLACK_M = 400.0
        const val SNAP_REACH_M = 500.0 // the snapped route's last point must be within this of the destination
        const val MAX_ROUTES = 4       // primary + up to 3 alternates in the picker
    }
}
