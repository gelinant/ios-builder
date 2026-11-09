package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import app.vela.core.model.bearingTo
import app.vela.core.model.defaultColorHex
import app.vela.core.model.distanceTo
import app.vela.core.platform.Clock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * One in-service vehicle drawn from the feed's times. [lat] and [lng] are an ESTIMATE: the
 * feed gives no vehicle coordinate, so the point is interpolated along the stretch polyline
 * between the stop the vehicle left and the next one, using the live times. [estimated] is
 * therefore always true and every surface says so; anything else would present an estimate as
 * a measurement. [nextStopName] and [headsign] are the stretch's stops, never an invented call.
 */
data class TransitVehicle(
    val id: String,
    val label: String,
    val mode: String,
    val colorHex: String,
    val feedColorHex: String?,
    val headsign: String,
    val fromStopName: String,
    val nextStopName: String,
    val lat: Double,
    val lng: Double,
    val bearing: Double,
    val fraction: Double,
    val delayMinutes: Int?,
    val destinationEpochSec: Long,
    val estimated: Boolean = true,
)

/** The vehicles panel's state. [error] is a key, never a sentence. */
data class TransitVehiclesState(
    val vehicles: List<TransitVehicle> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    val fetchedAtMillis: Long = 0L,
    val runs: Int = 0,
    val liveTimes: Int = 0,
    val revision: Int = 0,
) {
    val count: Int get() = vehicles.size
    val estimatedCount: Int get() = vehicles.count { it.estimated }
    val liveLineCount: Int get() = vehicles.map { it.label }.distinct().size
}

/**
 * The pure half: turns live stretches into estimated vehicle points. A stretch only yields a
 * marker when the feed marked it realtime AND it carries a departure, and only while the clock
 * sits inside its two stops. The fraction is elapsed over the stretch duration, clamped to
 * [0,1]; a missing live time yields no marker rather than a scheduled guess.
 */
object TransitVehicles {
    /** How many vertices on each side of the nearest one a stretch may use. */
    private const val BEARING_STEP = 0.01

    /** The live stretches whose clock window holds [nowEpochSec], one point each. */
    fun markers(runs: List<Transitous.MapTripRun>, nowEpochSec: Long): List<TransitVehicle> {
        val markers = runs.mapNotNull { run -> marker(run, nowEpochSec) }
        // A trip can be drawn as several adjacent stretches. Only one of them is current, but a
        // feed overlap could produce two; the latest departure is the vehicle's real position.
        val chosen = LinkedHashMap<String, TransitVehicle>()
        for (marker in markers) {
            val key = marker.id
            val previous = chosen[key]
            if (previous == null || marker.destinationEpochSec > previous.destinationEpochSec) {
                chosen[key] = marker
            }
        }
        return chosen.values.sortedWith(compareBy({ it.label }, { it.destinationEpochSec }, { it.nextStopName }))
    }

    /** The fraction of a stretch already travelled, or null outside its live window. */
    fun fractionAt(departureEpochSec: Long?, destinationEpochSec: Long?, nowEpochSec: Long): Double? {
        if (departureEpochSec == null || destinationEpochSec == null) return null
        val duration = destinationEpochSec - departureEpochSec
        if (duration <= 0) return null
        val elapsed = nowEpochSec - departureEpochSec
        // Before the departure the vehicle is not on this stretch yet; after the arrival the next
        // stretch owns it. The clamp only absorbs sub-second rounding at the two ends.
        if (elapsed < 0 || elapsed > duration) return null
        return (elapsed.toDouble() / duration.toDouble()).coerceIn(0.0, 1.0)
    }

    /**
     * The point at [fraction] of the polygon length between the vertices closest to the two
     * stops. `map/trips` sometimes draws more vertices than the stop pair, so the closest vertex
     * to each stop bounds the walked chain instead of assuming the path starts and ends there.
     * A one-vertex chain falls back to a straight line between the stops.
     */
    fun pointOnPath(path: List<LatLng>, from: LatLng, to: LatLng, fraction: Double): LatLng {
        val chain = chain(path, from, to)
        if (chain.isEmpty()) return from
        if (chain.size == 1) return chain.first()
        val lengths = DoubleArray(chain.size - 1) { chain[it].distanceTo(chain[it + 1]) }
        val total = lengths.sum()
        if (total <= 0.0) return chain.first()
        var remaining = total * fraction.coerceIn(0.0, 1.0)
        for (index in lengths.indices) {
            if (remaining <= lengths[index] || index == lengths.lastIndex) {
                val share = if (lengths[index] <= 0.0) 0.0 else (remaining / lengths[index]).coerceIn(0.0, 1.0)
                val a = chain[index]
                val b = chain[index + 1]
                return LatLng(a.lat + (b.lat - a.lat) * share, a.lng + (b.lng - a.lng) * share)
            }
            remaining -= lengths[index]
        }
        return chain.last()
    }

    /** The glyph's heading along the stretch, in degrees clockwise from north. */
    fun bearingOnPath(path: List<LatLng>, from: LatLng, to: LatLng, fraction: Double): Double {
        val chain = chain(path, from, to)
        if (chain.size < 2) return from.bearingTo(to)
        val a = pointOnPath(chain, chain.first(), chain.last(), fraction)
        val b = pointOnPath(chain, chain.first(), chain.last(), (fraction + BEARING_STEP).coerceAtMost(1.0))
        return if (a.distanceTo(b) < 0.5) {
            val index = (fraction * (chain.size - 1)).toInt().coerceIn(0, chain.size - 2)
            chain[index].bearingTo(chain[index + 1])
        } else {
            a.bearingTo(b)
        }
    }

    /** The shortest walkable chain between the vertices nearest the two stops, in travel order. */
    fun chain(path: List<LatLng>, from: LatLng, to: LatLng): List<LatLng> {
        if (path.size < 2) return listOf(from, to)
        val start = nearestIndex(path, from)
        val end = nearestIndex(path, to)
        if (start == end) return listOf(from, to)
        return if (start < end) path.subList(start, end + 1).toList() else path.subList(end, start + 1).reversed()
    }

    /** Linear interpolation is exact enough for a stop-to-stop hop; no projection is invented. */
    fun nearestIndex(path: List<LatLng>, point: LatLng): Int {
        var index = 0
        var best = Double.MAX_VALUE
        for (i in path.indices) {
            val distance = path[i].distanceTo(point)
            if (distance < best) {
                best = distance
                index = i
            }
        }
        return index
    }

    private fun marker(run: Transitous.MapTripRun, nowEpochSec: Long): TransitVehicle? {
        // No realtime flag means the times are timetable only: no live data, no marker.
        if (!run.realTime) return null
        val departure = run.departureEpochSec ?: return null
        val destination = destinationOf(run) ?: return null
        val fraction = fractionAt(departure, destination, nowEpochSec) ?: return null
        val point = pointOnPath(run.path, run.from, run.to, fraction)
        val scheduledDeparture = run.scheduledDepartureEpochSec
        val delay = if (scheduledDeparture != null) {
            ((departure - scheduledDeparture) / 60.0).toInt()
        } else {
            null
        }
        val label = run.label.ifBlank { "?" }
        val key = run.tripId.ifBlank { "$label|${run.fromName}|${run.toName}" }
        return TransitVehicle(
            id = key,
            label = label,
            mode = run.mode.name,
            colorHex = run.colorHex ?: run.mode.defaultColorHex,
            feedColorHex = run.colorHex,
            headsign = run.toName,
            fromStopName = run.fromName,
            nextStopName = run.toName,
            lat = point.lat,
            lng = point.lng,
            bearing = bearingOnPath(run.path, run.from, run.to, fraction),
            fraction = fraction,
            delayMinutes = delay,
            destinationEpochSec = destination,
        )
    }

    /**
     * The live arrival, or the scheduled one shifted by the departure's own lateness. A stretch
     * with no live arrival and no scheduled arrival has no duration, so it yields no marker.
     */
    fun destinationOf(run: Transitous.MapTripRun): Long? {
        val departure = run.departureEpochSec ?: return null
        run.arrivalEpochSec?.let { return it }
        val scheduledArrival = run.scheduledArrivalEpochSec ?: return null
        val scheduledDeparture = run.scheduledDepartureEpochSec ?: return null
        return scheduledArrival + (departure - scheduledDeparture)
    }

    /** A marker shaped from values a test or a Debug fixture already holds. */
    fun mapped(
        id: String, label: String, mode: String, colorHex: String, feedColorHex: String?,
        headsign: String, fromStopName: String, nextStopName: String,
        lat: Double, lng: Double, bearing: Double, fraction: Double,
        delayMinutes: Int, hasDelay: Boolean, destinationEpochSec: Long,
    ): TransitVehicle = TransitVehicle(
        id = id,
        label = label,
        mode = mode,
        colorHex = colorHex,
        feedColorHex = feedColorHex,
        headsign = headsign,
        fromStopName = fromStopName,
        nextStopName = nextStopName,
        lat = lat,
        lng = lng,
        bearing = bearing,
        fraction = fraction,
        delayMinutes = if (hasDelay) delayMinutes else null,
        destinationEpochSec = destinationEpochSec,
    )
}

/**
 * `map/trips` behind the vehicles layer. One request at a time, at most one per [refreshMillis]
 * while the layer is on, counted against the same 720-a-day fair-use budget as the other panels.
 * [tick] recomputes the points from the stored stretches and the clock, so the markers advance
 * without a request; the layer's 20-second timer is what calls it.
 */
class TransitVehicleStore(
    private val scope: CoroutineScope,
    private val source: suspend (south: Double, west: Double, north: Double, east: Double, zoom: Int, start: Long, end: Long) -> Transitous.MapTripsReply,
    private val nowMillis: () -> Long,
    private val budget: TransitRequestBudget? = null,
    private val refreshMillis: Long = REFRESH_MILLIS,
) {
    private val _state = MutableStateFlow(TransitVehiclesState())
    val state: StateFlow<TransitVehiclesState> = _state.asStateFlow()

    private var runs: List<Transitous.MapTripRun> = emptyList()
    private var job: Job? = null
    private var lastRequestMs = 0L
    private var requests = 0
    private var revision = 0

    /**
     * Asks for the in-service stretches in a box when the refresh window has elapsed. [force] is
     * for the layer's own on switch; a timer tick never forces, so a tick cannot outrun the
     * policy. The window is capped at [WINDOW_SEC] like the live-line panel.
     */
    fun request(
        south: Double, west: Double, north: Double, east: Double,
        zoom: Int, startEpochSec: Long, endEpochSec: Long,
        force: Boolean = false,
    ) {
        if (south !in -90.0..90.0 || north !in -90.0..90.0) return
        if (west !in -180.0..180.0 || east !in -180.0..180.0) return
        val windowEnd = minOf(endEpochSec, startEpochSec + WINDOW_SEC)
        val now = nowMillis()
        if (!force && lastRequestMs > 0 && now - lastRequestMs < refreshMillis) return
        if (budget?.take() == false) {
            _state.update { it.copy(loading = false, error = "budget_exhausted") }
            return
        }
        job?.cancel()
        lastRequestMs = now
        requests += 1
        _state.update { it.copy(loading = true, error = null) }
        job = scope.launch {
            val reply = source(south, west, north, east, zoom, startEpochSec, windowEnd)
            if (reply.rateLimited) {
                budget?.refused()
                _state.update { it.copy(loading = false, error = "rate_limited") }
                return@launch
            }
            if (reply.runs.isEmpty() && reply.lines.isEmpty()) {
                // Keep the last points: an empty answer is not proof that service stopped.
                _state.update { it.copy(loading = false, error = "failed") }
                return@launch
            }
            runs = reply.runs
            publish(nowMillis(), loading = false, error = null)
        }
    }

    /** Recomputes every point from the stored stretches and the clock. Sends nothing. */
    fun tick() {
        if (runs.isEmpty()) return
        publish(nowMillis(), loading = _state.value.loading, error = _state.value.error)
    }

    fun requestCount(): Int = requests

    fun clear() {
        job?.cancel()
        job = null
        runs = emptyList()
        lastRequestMs = 0L
        revision = 0
        _state.value = TransitVehiclesState()
    }

    private fun publish(nowMs: Long, loading: Boolean, error: String?) {
        val vehicles = TransitVehicles.markers(runs, nowMs / 1_000L)
        revision += 1
        _state.value = TransitVehiclesState(
            vehicles = vehicles,
            loading = loading,
            error = error,
            fetchedAtMillis = if (vehicles.isEmpty()) _state.value.fetchedAtMillis else nowMs,
            runs = runs.size,
            liveTimes = vehicles.size,
            revision = revision,
        )
    }

    companion object {
        /** Four minutes: one always-on viewport stays at 360 calls a day, inside the 720 line. */
        const val REFRESH_MILLIS = 4L * 60L * 1000L
        const val WINDOW_SEC = 10L * 60L
    }
}

/** The vehicles layer's owner: one store, one budget shared with the live panels. */
class TransitVehicleService(http: TransitousHttp, clock: Clock, budget: TransitRequestBudget?) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val vehicles = TransitVehicleStore(
        scope = scope,
        source = { s, w, n, e, zoom, start, end -> Transitous.mapTrips(http, s, w, n, e, zoom, start, end) },
        nowMillis = { clock.nowMillis() },
        budget = budget,
    )

    /** The on switch: asks at once, inside the same budget and window as every other panel. */
    fun request(
        south: Double, west: Double, north: Double, east: Double,
        zoom: Int, startEpochSec: Long, endEpochSec: Long,
    ) {
        vehicles.request(south, west, north, east, zoom, startEpochSec, endEpochSec, force = true)
    }

    /** A timer beat: the store refuses while its four-minute window is still open. */
    fun refresh(
        south: Double, west: Double, north: Double, east: Double,
        zoom: Int, startEpochSec: Long, endEpochSec: Long,
    ) {
        vehicles.request(south, west, north, east, zoom, startEpochSec, endEpochSec, force = false)
    }

    fun tick() {
        vehicles.tick()
    }

    fun close() {
        vehicles.clear()
    }
}
