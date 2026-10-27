package app.vela.ios.transit

import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What a board request names: a known Transitous stop, or a tap point resolved by proximity. */
data class TransitBoardTarget(
    val stopId: String? = null,
    val parentId: String? = null,
    val name: String = "",
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val modes: List<String> = emptyList(),
    val siblingIds: List<String> = emptyList(),
)

/** One departure as the board shows it. [minutes] is ceiled from the feed's epoch at fetch time;
 *  Swift keeps its own countdown because the board only refreshes every 30 s. [realtime] is true
 *  only when the feed marked this run live. Nothing here is inferred. */
data class TransitBoardDeparture(
    val clockText: String?,
    val epochSec: Long,
    val realtime: Boolean,
    val minutes: Int,
    val tripId: String?,
)

/** One line and direction served by the stop, with its next departures. */
data class TransitBoardLine(
    val label: String?,
    val mode: String,
    val headsign: String?,
    val color: String?,
    val departures: List<TransitBoardDeparture>,
)

/** The open stop board. [error] is a key (`no_departures`), never a formatted sentence. */
data class TransitBoardState(
    val open: Boolean = false,
    val loading: Boolean = false,
    val stopName: String = "",
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val lines: List<TransitBoardLine> = emptyList(),
    val fetchedAtMillis: Long = 0L,
    val refreshFailed: Boolean = false,
    val error: String? = null,
    val revision: Int = 0,
) {
    val departureCount: Int get() = lines.sumOf { it.departures.size }
    val realtimeCount: Int get() = lines.sumOf { line -> line.departures.count { it.realtime } }
    val soonestMinutes: Int get() = lines.mapNotNull { it.departures.firstOrNull()?.minutes }.minOrNull() ?: -1
}

/**
 * The stop board of one tapped stop (SPEC 8, "Stops and boards"). It asks the open feed for the
 * next departures and refreshes every 30 s while open, exactly like Android. Transitous supplies
 * every route at the stop; a miss is shown as "no departures", never replaced by invented data.
 * Construction does nothing; calls must come from the session's main thread.
 */
class TransitBoardStore(
    private val scope: CoroutineScope,
    private val source: suspend (TransitBoardTarget) -> StopDepartures?,
    private val nowMillis: () -> Long,
    private val refreshMillis: Long = 30_000L,
) {
    private val _state = MutableStateFlow(TransitBoardState())
    val state: StateFlow<TransitBoardState> = _state.asStateFlow()

    private var target: TransitBoardTarget? = null
    private var job: Job? = null
    private var generation = 0

    /** Opens the board for a coordinate, resolving the stop group by proximity (Transitous.board). */
    fun open(lat: Double, lng: Double, name: String = "") {
        if (lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        fetch(TransitBoardTarget(name = name, lat = lat, lng = lng))
    }

    /** Opens the board for a stop icon that already carries its Transitous id (boardFor). */
    fun openStop(
        stopId: String,
        name: String,
        lat: Double,
        lng: Double,
        modes: List<String> = emptyList(),
        parentId: String? = null,
        siblingIds: List<String> = emptyList(),
    ) {
        if (stopId.isBlank() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        fetch(
            TransitBoardTarget(
                stopId = stopId, parentId = parentId, name = name, lat = lat, lng = lng,
                modes = modes, siblingIds = siblingIds,
            ),
        )
    }

    /** Re-queries the open board at once; the 30 s loop stays in place. */
    fun refresh() {
        val open = target ?: return
        fetch(open, keepLines = true)
    }

    fun close() {
        job?.cancel()
        job = null
        generation += 1
        target = null
        _state.value = TransitBoardState()
    }

    private fun fetch(open: TransitBoardTarget, keepLines: Boolean = false) {
        job?.cancel()
        target = open
        val gen = ++generation
        _state.update {
            it.copy(
                open = true, loading = it.lines.isEmpty() && !keepLines, stopName = open.name,
                latitude = open.lat, longitude = open.lng, refreshFailed = false,
                error = if (keepLines) it.error else null,
            )
        }
        job = scope.launch {
            while (true) {
                val board = runCatching { source(open) }.getOrNull()
                if (gen != generation) return@launch
                apply(board, gen)
                // A manual refresh starts a fresh loop; the open board itself refreshes in place.
                delay(refreshMillis)
                if (gen != generation || !_state.value.open) return@launch
            }
        }
    }

    private fun apply(board: StopDepartures?, gen: Int) {
        val at = nowMillis()
        val lines = board?.lines.orEmpty().map(::lineRow).filter { it.departures.isNotEmpty() }
        val error = if (lines.isEmpty()) "no_departures" else null
        _state.update {
            if (gen != generation) it
            else it.copy(
                open = true,
                loading = false,
                stopName = board?.stationName ?: it.stopName,
                lines = if (lines.isEmpty() && it.lines.isNotEmpty()) it.lines else lines,
                fetchedAtMillis = if (lines.isEmpty() && it.lines.isNotEmpty()) it.fetchedAtMillis else at,
                refreshFailed = lines.isEmpty() && it.lines.isNotEmpty(),
                error = if (lines.isEmpty() && it.lines.isNotEmpty()) null else error,
                revision = it.revision + 1,
            )
        }
    }

    /** One line's departures, sorted by time, with the duplicate collapse Android uses. */
    private fun lineRow(line: StopDepartureLine): TransitBoardLine {
        val nowSec = nowMillis() / 1000L
        val departures = line.upcoming
            .mapNotNull { departureRow(it, nowSec) }
            .distinctBy { it.epochSec }
            .sortedBy { it.epochSec }
        return TransitBoardLine(
            label = line.label?.takeIf { it.isNotBlank() },
            mode = line.mode.name,
            headsign = line.headsign?.takeIf { it.isNotBlank() },
            color = line.colorHex,
            departures = departures,
        )
    }

    private fun departureRow(departure: StopDeparture, nowSec: Long): TransitBoardDeparture? {
        val epoch = departure.epochSec ?: return null
        val seconds = epoch - nowSec
        // A run that left less than a minute ago is still useful; older ones are gone.
        if (seconds < -60) return null
        val minutes = if (seconds <= 0) 0 else ((seconds + 59) / 60).toInt()
        return TransitBoardDeparture(
            clockText = departure.clockText,
            epochSec = epoch,
            realtime = departure.realtime,
            minutes = minutes,
            tripId = departure.tripId,
        )
    }

    companion object {
        /** The transit-category gate of SPEC 8: "station", "stop", "bus", "rail" and their
         *  translations, minus fuel, charging, emergency and broadcast places. */
        private val TRANSIT_WORDS = Regex(
            """station|stop|subway|metro|transit|transport|\bhub\b|\bbus\b|train|\brail\b|tram|""" +
                """light rail|terminal|ferry|bahnhof|haltestelle|gare|estaci|estaç|stazione|fermata|""" +
                """arrêt|parada|paragem|hållplats|przystanek|dworzec|зупинка|станція|megálló|állomás|""" +
                """pályaudvar|stație|statie|gară|autogară|вокзал|станц|остановка|停|駅|车站|車站|""" +
                """תחנ|אוטובוס|רכבת|מסוף|רציף|지하철""",
            RegexOption.IGNORE_CASE,
        )
        private val NON_TRANSIT_WORDS = Regex(
            """gas|fuel|petrol|filling|gasolin|benzin|essence|carburant|charging|laadstation|""" +
                """ladestation|recharge|recarga|ricarica|fire|police|power|pumping|weigh|radio|""" +
                """television|\btv\b|pompiers|bomberos|feuerwehr|заправ|азс|טעינה|加油|ガソリン|주유""",
            RegexOption.IGNORE_CASE,
        )

        /** Whether a tap's basemap kind names a transit stop, with Android's exclusions. */
        fun isTransitKind(kind: String?): Boolean {
            val text = kind?.takeIf { it.isNotBlank() } ?: return false
            return TRANSIT_WORDS.containsMatchIn(text) && !NON_TRANSIT_WORDS.containsMatchIn(text)
        }

        internal fun modeName(mode: TransitMode): String = mode.name
    }
}

/** The one Swift-facing transit-kind gate; a Kotlin object exports as `TransitKinds.shared`. */
object TransitKinds {
    fun isTransit(kind: String?): Boolean = TransitBoardStore.isTransitKind(kind)
}
