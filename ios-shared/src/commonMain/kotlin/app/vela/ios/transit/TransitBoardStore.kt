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
    /** True only while the shown lines came from the on-disk cache because the feed did not
     *  answer. Such a board carries no live mark and says when it was fetched. */
    val offline: Boolean = false,
    val cachedAtMillis: Long = 0L,
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
    private val cache: TransitBoardCache? = null,
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
            // The board the user saw last is shown before the feed answers, so a dead network
            // still explains itself instead of blanking the sheet.
            if (!keepLines && _state.value.lines.isEmpty()) {
                val cached = runCatching { cache?.load(open, nowMillis()) }.getOrNull()
                if (cached != null && gen == generation) applyCached(cached, gen)
            }
            while (true) {
                val board = runCatching { source(open) }.getOrNull()
                if (gen != generation) return@launch
                if (board != null) {
                    apply(board, gen)
                    runCatching { cache?.save(open, board, nowMillis()) }
                } else {
                    applyFailure(gen)
                }
                // A manual refresh starts a fresh loop; the open board itself refreshes in place.
                delay(refreshMillis)
                if (gen != generation || !_state.value.open) return@launch
            }
        }
    }

    /** A successful feed answer replaces any cached board and restores live marks. */
    private fun apply(board: StopDepartures, gen: Int) {
        val at = nowMillis()
        val lines = board.lines.map(::lineRow).filter { it.departures.isNotEmpty() }
        _state.update {
            if (gen != generation) it
            else it.copy(
                open = true,
                loading = false,
                stopName = board.stationName ?: it.stopName,
                lines = if (lines.isEmpty() && it.lines.isNotEmpty()) it.lines else lines,
                fetchedAtMillis = if (lines.isEmpty() && it.lines.isNotEmpty()) it.fetchedAtMillis else at,
                refreshFailed = lines.isEmpty() && it.lines.isNotEmpty(),
                error = if (lines.isEmpty() && it.lines.isEmpty()) "no_departures" else null,
                offline = false,
                cachedAtMillis = 0L,
                revision = it.revision + 1,
            )
        }
    }

    /** The feed failed: keep the last board if there is one. A board that came from the cache stays
     *  labeled offline; a live board is only marked stale. */
    private fun applyFailure(gen: Int) {
        _state.update {
            if (gen != generation) it
            else {
                val kept = it.lines.isNotEmpty()
                it.copy(
                    open = true,
                    loading = false,
                    refreshFailed = kept && !it.offline,
                    error = if (kept) null else "no_departures",
                    revision = it.revision + 1,
                )
            }
        }
    }

    /** Shows a cached board: unchanged lines, its own fetch time, and no live mark at all. */
    private fun applyCached(cached: CachedBoard, gen: Int) {
        val lines = cached.board.lines.map { line -> lineRow(line, live = false) }
            .filter { it.departures.isNotEmpty() }
        _state.update {
            if (gen != generation) it
            else it.copy(
                open = true,
                loading = false,
                stopName = cached.board.stationName ?: it.stopName,
                lines = if (lines.isEmpty()) it.lines else lines,
                fetchedAtMillis = cached.fetchedAtMillis,
                cachedAtMillis = cached.fetchedAtMillis,
                offline = lines.isNotEmpty(),
                refreshFailed = false,
                error = if (lines.isEmpty() && it.lines.isEmpty()) "no_departures" else null,
                revision = it.revision + 1,
            )
        }
    }

    /**
     * Debug-only: seeds the cache with a fixed board then opens it without asking the feed, so the
     * offline state can be tested on a simulator that still has a network.
     */
    fun openOfflineFixture(lat: Double, lng: Double, name: String) {
        if (lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        job?.cancel()
        job = null
        val open = TransitBoardTarget(name = name, lat = lat, lng = lng)
        target = open
        val gen = ++generation
        _state.value = TransitBoardState(
            open = true, loading = true, stopName = name, latitude = lat, longitude = lng,
        )
        job = scope.launch {
            val at = nowMillis()
            val board = TransitBoardFixtures.offlineSample(at)
            runCatching { cache?.save(open, board, at) }
            val cached = runCatching { cache?.load(open, at) }.getOrNull()
            if (gen != generation) return@launch
            if (cached != null) {
                applyCached(cached, gen)
            } else {
                applyFailure(gen)
            }
        }
    }

    /** One line's departures, sorted by time, with the duplicate collapse Android uses.
     *  [live] false comes from the cache: a stored realtime flag is never shown as live. */
    private fun lineRow(line: StopDepartureLine, live: Boolean = true): TransitBoardLine {
        val nowSec = nowMillis() / 1000L
        val departures = line.upcoming
            .mapNotNull { departureRow(it, nowSec) }
            .map { if (live) it else it.copy(realtime = false) }
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

/** Deterministic departure data for the offline-board UI scenario; production never calls it. */
object TransitBoardFixtures {
    /** A Ferry Building board whose first departures are still ahead of [nowMillis]. Some rows
     *  arrive live, which is exactly what the cache must drop when it shows them offline. */
    fun offlineSample(nowMillis: Long): StopDepartures {
        val nowSec = nowMillis / 1000L
        fun departure(offsetMin: Long, live: Boolean, clock: String) =
            StopDeparture(clockText = clock, epochSec = nowSec + offsetMin * 60L, realtime = live)
        return StopDepartures(
            stationName = "Ferry Building",
            lines = listOf(
                StopDepartureLine(
                    label = "14", mode = TransitMode.BUS, headsign = "Ferry Plaza",
                    colorHex = "#0f6cbd",
                    upcoming = listOf(
                        departure(3, true, "9:41 AM"),
                        departure(11, false, "9:49 AM"),
                    ),
                ),
                StopDepartureLine(
                    label = "K", mode = TransitMode.TRAM, headsign = "Embarcadero",
                    colorHex = "#437c93",
                    upcoming = listOf(
                        departure(6, true, "9:44 AM"),
                        departure(16, false, "9:54 AM"),
                    ),
                ),
            ),
        )
    }
}
