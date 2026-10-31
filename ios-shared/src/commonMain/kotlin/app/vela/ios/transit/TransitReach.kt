package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
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

/** One stop the reachability answer lists, with the travel time the planner measured. */
data class TransitReachStop(
    val name: String,
    val stopId: String,
    val lat: Double,
    val lng: Double,
    val minutes: Int,
    val transfers: Int,
)

/**
 * The area a rider can reach from one point in [maxMinutes]. [hull] is Vela's own convex hull of
 * [stops], not an official isochrone polygon: it can cover a block or a bay between two stops that
 * the service did not reach. It is only the outline the map draws around the reachable stop dots.
 */
data class TransitReachArea(
    val originName: String,
    val originLat: Double,
    val originLng: Double,
    val maxMinutes: Int,
    val stops: List<TransitReachStop>,
    val hull: List<LatLng>,
    val fetchedAtMillis: Long,
    val rateLimited: Boolean = false,
) {
    /** The stops sorted by travel time, then transfers, then name: the order the screen reads. */
    val stopsByTime: List<TransitReachStop>
        get() = stops.sortedWith(compareBy({ it.minutes }, { it.transfers }, { it.name }))

    /** True when the feed answered with no reachable stop. A clean empty answer, not a failure. */
    val isEmpty: Boolean get() = stops.isEmpty()
}

/** The reachability panel's state. [error] is a key, never a sentence. */
data class TransitReachState(
    val area: TransitReachArea? = null,
    val loading: Boolean = false,
    val error: String? = null,
    val revision: Int = 0,
) {
    val stopCount: Int get() = area?.stops?.size ?: 0
    val hullCount: Int get() = area?.hull?.size ?: 0
    val rateLimited: Boolean get() = area?.rateLimited == true || error == "rate_limited"
    /** The feed answered and reached nothing inside the budget. */
    val empty: Boolean get() = area != null && area.stops.isEmpty()
    /** The screen could not ask: offline, NoGoogle, or no transit service in this build. */
    val needsNetwork: Boolean get() = error == "needs_transitous"
}

/**
 * The fair-use budget Transitous publishes: more than 720 calls a day to `/plan`, `/one-to-all` or
 * `/one-to-many` is beyond the community instance's guidance. The app counts its own calls and
 * stops before the limit rather than wait for a 429. A 429 is also remembered, so a UI cannot spin.
 */
class TransitRequestBudget(
    private val limit: Int = LIMIT_PER_DAY,
    private val windowMillis: Long = WINDOW_MILLIS,
    private val nowMillis: () -> Long,
) {
    private val stamps = ArrayDeque<Long>()
    private var limitedAt = 0L

    /** True when the call may go out; false once the window is full or a 429 was seen. */
    fun take(): Boolean {
        val now = nowMillis()
        prune(now)
        if (limitedAt > 0 && now - limitedAt <= RATE_LIMIT_BACKOFF_MILLIS) return false
        if (stamps.size >= limit) return false
        stamps.addLast(now)
        return true
    }

    private fun prune(now: Long) {
        while (stamps.isNotEmpty() && now - stamps.first() > windowMillis) stamps.removeFirst()
    }

    /** Records the service's own refusal, so every panel stops asking for a while. */
    fun refused() {
        limitedAt = nowMillis()
    }

    fun used(): Int { prune(nowMillis()); return stamps.size }
    fun remaining(): Int = (limit - used()).coerceAtLeast(0)

    companion object {
        const val LIMIT_PER_DAY = 720
        const val WINDOW_MILLIS = 24L * 60L * 60L * 1000L
        const val RATE_LIMIT_BACKOFF_MILLIS = 30L * 60L * 1000L
    }
}

/**
 * `one-to-all` behind one user action: no polling, a five-minute answer cache, and one request at
 * a time. A second request for the same point and budget inside the cache window is answered from
 * the last area. A 429 keeps the previous area on screen and raises `rate_limited`.
 */
class TransitReachStore(
    private val scope: CoroutineScope,
    private val source: suspend (lat: Double, lng: Double, minutes: Int) -> Transitous.OneToAllReply,
    private val nowMillis: () -> Long,
    private val cacheMillis: Long = CACHE_MILLIS,
    private val budget: TransitRequestBudget? = null,
) {
    private val _state = MutableStateFlow(TransitReachState())
    val state: StateFlow<TransitReachState> = _state.asStateFlow()

    private var job: Job? = null
    private var key = ""
    private var cached = 0L
    private var requests = 0

    /** Asks for the area around ([lat],[lng]) within [minutes]. The budget is clamped to 5..60. */
    fun request(lat: Double, lng: Double, minutes: Int = 30) {
        if (lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        val budgetMin = minutes.coerceIn(Transitous.MIN_REACH_MIN, Transitous.MAX_REACH_MIN)
        val next = "${round4(lat)},${round4(lng)},$budgetMin"
        val now = nowMillis()
        if (_state.value.area != null && next == key && now - cached < cacheMillis) return
        if (budget?.take() == false) {
            _state.update {
                it.copy(loading = false, error = "budget_exhausted",
                    area = it.area?.copy(rateLimited = false))
            }
            return
        }
        job?.cancel()
        key = next
        _state.update { it.copy(loading = true, error = null) }
        job = scope.launch {
            requests += 1
            val reply = source(lat, lng, budgetMin)
            if (reply.rateLimited) {
                budget?.refused()
                _state.update {
                    it.copy(loading = false, error = "rate_limited",
                        area = it.area?.copy(rateLimited = true))
                }
                return@launch
            }
            val result = reply.result
            if (result == null) {
                _state.update { it.copy(loading = false, error = "failed") }
                return@launch
            }
            val area = TransitReach.area(result, budgetMin, nowMillis())
            cached = nowMillis()
            _state.update { it.copy(loading = false, area = area, error = null) }
        }
    }

    fun requestCount(): Int = requests

    fun clear() {
        job?.cancel()
        job = null
        key = ""
        cached = 0L
        _state.value = TransitReachState()
    }

    companion object {
        const val CACHE_MILLIS = 5L * 60L * 1000L
        fun round4(v: Double): String = ((v * 10_000).toInt()).toString()
    }
}

/** The pure half of the reachability panel. */
object TransitReach {
    /** The budgets the "Reachable in N minutes" screen offers, in minutes, smallest first. */
    val MINUTE_OPTIONS: List<Int> = listOf(15, 30, 45, 60)
    /** The area of [result] within [maxMinutes], with Vela's own hull of the stop dots. */
    fun area(result: Transitous.ReachResult, maxMinutes: Int, nowMillis: Long): TransitReachArea {
        val stops = result.stops
            .filter { it.minutes <= maxMinutes }
            .map { TransitReachStop(it.name, it.stopId, it.lat, it.lon, it.minutes, it.transfers) }
        return areaOf(result.originName, result.originLat, result.originLon, maxMinutes, stops, nowMillis)
    }

    /** The same area from stops already mapped, for a Debug fixture or a cached list. */
    fun areaOf(
        originName: String, originLat: Double, originLng: Double, maxMinutes: Int,
        stops: List<TransitReachStop>, nowMillis: Long,
    ): TransitReachArea = TransitReachArea(
        originName = originName,
        originLat = originLat,
        originLng = originLng,
        maxMinutes = maxMinutes,
        stops = stops.filter { it.minutes <= maxMinutes },
        hull = hullOf(stops.filter { it.minutes <= maxMinutes }.map { LatLng(it.lat, it.lng) }),
        fetchedAtMillis = nowMillis,
        rateLimited = false,
    )

    /**
     * The convex hull of [points], counter-clockwise, without a repeated last point. Monotone chain
     * on (longitude, latitude). Fewer than three distinct points give an empty outline: a line is
     * not a polygon, and the map then draws the dots alone.
     */
    fun hullOf(points: List<LatLng>): List<LatLng> {
        val unique = points.distinctBy { "${it.lat},${it.lng}" }.sortedWith(compareBy({ it.lng }, { it.lat }))
        if (unique.size < 3) return emptyList()
        fun cross(o: LatLng, a: LatLng, b: LatLng): Double =
            (a.lng - o.lng) * (b.lat - o.lat) - (a.lat - o.lat) * (b.lng - o.lng)
        val lower = ArrayList<LatLng>()
        for (p in unique) {
            while (lower.size >= 2 && cross(lower[lower.size - 2], lower.last(), p) <= 0) lower.removeAt(lower.size - 1)
            lower.add(p)
        }
        val upper = ArrayList<LatLng>()
        for (p in unique.asReversed()) {
            while (upper.size >= 2 && cross(upper[upper.size - 2], upper.last(), p) <= 0) upper.removeAt(upper.size - 1)
            upper.add(p)
        }
        lower.removeAt(lower.size - 1)
        upper.removeAt(upper.size - 1)
        val hull = lower + upper
        return if (hull.size < 3) emptyList() else hull
    }
}

/**
 * The two panels T-2 adds, behind one owner: the reachability store and the live-line store. They
 * share one [TransitRequestBudget] so the 720 calls a day the Transitous policy names are counted
 * across both, and neither polls. The map lot can lift the descriptors from the two states; nothing
 * here draws on the map.
 */
class TransitLiveService(http: TransitousHttp, clock: Clock) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val budget = TransitRequestBudget(nowMillis = { clock.nowMillis() })

    val reach = TransitReachStore(
        scope = scope,
        source = { lat, lng, minutes -> Transitous.oneToAll(http, LatLng(lat, lng), minutes) },
        nowMillis = { clock.nowMillis() },
        budget = budget,
    )

    val lines = TransitLiveLinesStore(
        scope = scope,
        source = { s, w, n, e, zoom, start, end ->
            Transitous.mapTrips(http, s, w, n, e, zoom, start, end)
        },
        nowMillis = { clock.nowMillis() },
        budget = budget,
    )

    fun requestReach(lat: Double, lng: Double, minutes: Int) {
        reach.request(lat, lng, minutes)
    }

    fun requestLines(south: Double, west: Double, north: Double, east: Double, zoom: Int, startEpochSec: Long, endEpochSec: Long) {
        lines.request(south, west, north, east, zoom, startEpochSec, endEpochSec)
    }

    fun close() {
        reach.clear()
        lines.clear()
    }
}
