package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import app.vela.core.model.defaultColorHex
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * One drawn line of the live map. [colorHex] is the agency's `routeColor` when the feed carried
 * one, else Vela's mode color ([TransitMode.defaultColorHex]); [feedColorHex] keeps which of the
 * two it was. [delayLevel] is `green`, `amber`, `red` or `none`: the last means the feed did not
 * carry both a scheduled and a live time, so Vela says nothing about lateness. [live] is true only
 * when the feed itself marked a stretch realtime; the API has no vehicle position.
 */
data class TransitLiveLine(
    val label: String,
    val mode: String,
    val colorHex: String,
    val feedColorHex: String?,
    val destination: String?,
    val segmentCount: Int,
    val delayMinutes: Int?,
    val delayLevel: String,
    val live: Boolean,
    val paths: List<List<LatLng>>,
)

/** The live-line panel's state. [error] is a key, never a sentence. */
data class TransitLiveLinesState(
    val lines: List<TransitLiveLine> = emptyList(),
    val fetchedAtMillis: Long = 0L,
    val loading: Boolean = false,
    val error: String? = null,
    val truncated: Boolean = false,
    val segmentCount: Int = 0,
    val revision: Int = 0,
) {
    val lineCount: Int get() = lines.size
    val liveCount: Int get() = lines.count { it.live }
    val coloredCount: Int get() = lines.count { it.feedColorHex != null }
    val delayedCount: Int get() = lines.count { it.delayMinutes != null }
    val greenCount: Int get() = lines.count { it.delayLevel == TransitLiveLines.LEVEL_GREEN }
    val amberCount: Int get() = lines.count { it.delayLevel == TransitLiveLines.LEVEL_AMBER }
    val redCount: Int get() = lines.count { it.delayLevel == TransitLiveLines.LEVEL_RED }
}

/**
 * `map/trips` behind one viewport action: a two-minute cache, no polling and one request at a time.
 * A box is the map's, so the caller decides when the user's action changes it.
 */
class TransitLiveLinesStore(
    private val scope: CoroutineScope,
    private val source: suspend (south: Double, west: Double, north: Double, east: Double, zoom: Int, start: Long, end: Long) -> Transitous.MapTripsReply,
    private val nowMillis: () -> Long,
    private val cacheMillis: Long = CACHE_MILLIS,
    private val budget: TransitRequestBudget? = null,
) {
    private val _state = MutableStateFlow(TransitLiveLinesState())
    val state: StateFlow<TransitLiveLinesState> = _state.asStateFlow()

    private var job: Job? = null
    private var key = ""
    private var cached = 0L
    private var requests = 0

    /**
     * Asks for the stretches in a box and a time window. The window is capped at [WINDOW_SEC] so a
     * caller cannot turn one action into a whole day of vehicle drawing.
     */
    fun request(south: Double, west: Double, north: Double, east: Double, zoom: Int, startEpochSec: Long, endEpochSec: Long) {
        if (south !in -90.0..90.0 || north !in -90.0..90.0 || west !in -180.0..180.0 || east !in -180.0..180.0) return
        val windowEnd = minOf(endEpochSec, startEpochSec + WINDOW_SEC)
        val next = "${round3(south)},${round3(west)},${round3(north)},${round3(east)},$zoom,$startEpochSec,$windowEnd"
        val now = nowMillis()
        if (_state.value.lines.isNotEmpty() && next == key && now - cached < cacheMillis) return
        if (budget?.take() == false) {
            _state.update { it.copy(loading = false, error = "budget_exhausted") }
            return
        }
        job?.cancel()
        key = next
        _state.update { it.copy(loading = true, error = null) }
        job = scope.launch {
            requests += 1
            val reply = source(south, west, north, east, zoom, startEpochSec, windowEnd)
            if (reply.rateLimited) {
                budget?.refused()
                _state.update { it.copy(loading = false, error = "rate_limited") }
                return@launch
            }
            if (reply.segmentCount == 0 && reply.lines.isEmpty()) {
                _state.update { it.copy(loading = false, error = "failed") }
                return@launch
            }
            val lines = reply.lines.map { TransitLiveLines.line(it) }
            cached = nowMillis()
            _state.update {
                it.copy(
                    lines = lines, loading = false, error = null,
                    fetchedAtMillis = cached, truncated = reply.truncated,
                    segmentCount = reply.segmentCount,
                )
            }
        }
    }

    fun requestCount(): Int = requests

    fun clear() {
        job?.cancel()
        job = null
        key = ""
        cached = 0L
        _state.value = TransitLiveLinesState()
    }

    companion object {
        const val CACHE_MILLIS = 2L * 60L * 1000L
        const val WINDOW_SEC = 10L * 60L
        fun round3(v: Double): String = ((v * 1_000).toInt()).toString()
    }
}

/** The pure half: colors, delay bands and the live flag, all from the feed. */
object TransitLiveLines {
    const val LEVEL_NONE = "none"
    const val LEVEL_GREEN = "green"
    const val LEVEL_AMBER = "amber"
    const val LEVEL_RED = "red"

    /** Green under 2 minutes, amber from 2 to 5, red above 5; an early run is judged on the same
     *  distance, because a ten-minute early run is as wrong as a ten-minute late one. */
    fun delayLevel(minutes: Int?): String {
        if (minutes == null) return LEVEL_NONE
        val drift = if (minutes < 0) -minutes else minutes
        return when {
            drift < 2 -> LEVEL_GREEN
            drift <= 5 -> LEVEL_AMBER
            else -> LEVEL_RED
        }
    }

    /** The line's fill: the feed's own color, else the mode color. Never both mixed. */
    fun colorOf(mode: TransitMode, feedColor: String?): String = feedColor ?: mode.defaultColorHex

    /**
     * A line from values a test or a Debug fixture already holds. [hasDelay] exists because a
     * nullable Int is boxed across the Swift bridge; a caller that has no delay passes false and
     * the delay stays null, never a made-up zero.
     */
    fun mappedLine(
        label: String, mode: String, colorHex: String, feedColorHex: String?, destination: String?,
        segmentCount: Int, delayMinutes: Int, hasDelay: Boolean, live: Boolean, paths: List<List<LatLng>>,
    ): TransitLiveLine = TransitLiveLine(
        label = label,
        mode = mode,
        colorHex = colorHex,
        feedColorHex = feedColorHex,
        destination = destination,
        segmentCount = segmentCount,
        delayMinutes = if (hasDelay) delayMinutes else null,
        delayLevel = delayLevel(if (hasDelay) delayMinutes else null),
        live = live,
        paths = paths,
    )

    fun line(line: Transitous.MapTripLine): TransitLiveLine = TransitLiveLine(
        label = line.label,
        mode = line.mode.name,
        colorHex = colorOf(line.mode, line.colorHex),
        feedColorHex = line.colorHex,
        destination = line.destination,
        segmentCount = line.segmentCount,
        delayMinutes = line.delayMinutes,
        delayLevel = delayLevel(line.delayMinutes),
        live = line.live,
        paths = line.paths,
    )
}
