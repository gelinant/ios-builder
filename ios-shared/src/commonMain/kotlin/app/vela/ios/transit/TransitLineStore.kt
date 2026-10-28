package app.vela.ios.transit

import app.vela.core.data.transit.TransitLineClient
import app.vela.core.data.transit.TransitLineRun
import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitMode
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
 * What the line sheet was opened on: one line, one direction (the feed's headsign) and one stop.
 * [stopId] is the Transitous id when the surface had one; a search result or a map label may only
 * have a coordinate, and the board is then resolved by proximity.
 */
data class TransitLineTarget(
    val label: String,
    val direction: String? = null,
    val stopId: String? = null,
    val parentId: String? = null,
    val stopName: String = "",
    val lat: Double = 0.0,
    val lng: Double = 0.0,
    val siblingIds: List<String> = emptyList(),
    val modes: List<String> = emptyList(),
)

/** One departure of the line at the stop. [live] is the feed's own flag, never a Vela guess. */
data class TransitLineDeparture(
    val clockText: String?,
    val epochSec: Long,
    val live: Boolean,
    val minutes: Int,
)

/**
 * The open line sheet. [colorHex] is the feed's `routeColor` or, when it carried none, the mode
 * color; [colorSource] says which (`feed` or `mode`). [stops] is the full run in order, empty when
 * [sequenceUnavailable] is true and only the departures the board sent can be shown. [position] is
 * always an estimate interpolated between the feed's times. [error] is a key, never a sentence.
 */
data class TransitLineState(
    val open: Boolean = false,
    val loading: Boolean = false,
    val label: String = "",
    val mode: String = TransitMode.GENERIC.name,
    val direction: String = "",
    val directions: List<String> = emptyList(),
    val stopName: String = "",
    val colorHex: String = "#5f6368",
    val colorSource: String = TransitLineColor.SOURCE_MODE,
    val live: Boolean = false,
    val fromName: String = "",
    val toName: String = "",
    val departures: List<TransitLineDeparture> = emptyList(),
    val stops: List<TransitLineStop> = emptyList(),
    val position: TransitLinePosition? = null,
    val transfers: List<TransitLineBadge> = emptyList(),
    val shape: List<LatLng> = emptyList(),
    val shapeSource: String = TransitLineRoute.SHAPE_STOPS,
    val sequenceUnavailable: Boolean = false,
    val error: String? = null,
    val fetchedAtMillis: Long = 0L,
    val revision: Int = 0,
) {
    val stopCount: Int get() = stops.size
    val directionCount: Int get() = directions.size
    val estimated: Boolean get() = position?.estimated == true
    val durationMinutes: Int get() = position?.secondsToNextStop?.let { (it + 59) / 60 } ?: -1
}

/**
 * The line sheet's data. One board request when it opens (or refreshes), then one run request for
 * the departure it shows; switching direction reuses the board already in hand and asks only for
 * that direction's run. [allowRequest] is the fair-use gate: when it says no, nothing is sent and
 * the sheet says the budget is spent rather than showing stale data as live.
 */
class TransitLineStore(
    private val scope: CoroutineScope,
    private val board: suspend (TransitLineTarget) -> StopDepartures?,
    private val run: suspend (String) -> TransitLineRun?,
    private val nowMillis: () -> Long,
    private val allowRequest: () -> Boolean = { true },
) {
    private val _state = MutableStateFlow(TransitLineState())
    val state: StateFlow<TransitLineState> = _state.asStateFlow()

    private var target: TransitLineTarget? = null
    private var loadedBoard: StopDepartures? = null
    private var job: Job? = null
    private var generation = 0

    /** Opens the sheet for a line at a stop, in [direction] when the caller knows it. */
    fun open(target: TransitLineTarget, direction: String? = null) {
        if (target.label.isBlank()) return
        if (target.lat !in -90.0..90.0 || target.lng !in -180.0..180.0) return
        this.target = target
        loadedBoard = null
        fetch(target, direction, reuseBoard = false)
    }

    /** Switches direction: the board already lists both, so only the chosen run is asked for. */
    fun selectDirection(direction: String) {
        val open = target ?: return
        if (direction.isBlank() || direction == _state.value.direction) return
        fetch(open, direction, reuseBoard = loadedBoard != null)
    }

    /** Re-queries the board and the run; a user action, never a timer. */
    fun refresh() {
        val open = target ?: return
        fetch(open, _state.value.direction.takeIf { it.isNotBlank() }, reuseBoard = false)
    }

    fun close() {
        job?.cancel()
        generation += 1
        target = null
        loadedBoard = null
        _state.value = TransitLineState()
    }

    private fun fetch(target: TransitLineTarget, direction: String?, reuseBoard: Boolean) {
        job?.cancel()
        val gen = ++generation
        _state.update {
            it.copy(
                open = true,
                loading = true,
                error = null,
                label = target.label,
                stopName = target.stopName,
            )
        }
        job = scope.launch {
            val now = nowMillis() / 1000L
            val loaded = if (reuseBoard) loadedBoard else {
                if (!allowRequest()) {
                    fail(gen, "budget_exhausted")
                    return@launch
                }
                board(target)?.also { loadedBoard = it }
            }
            if (gen != generation) return@launch
            if (loaded == null) {
                fail(gen, "no_departures")
                return@launch
            }
            val matches = loaded.lines.filter { it.label?.trim() == target.label.trim() }
            if (matches.isEmpty()) {
                fail(gen, "no_line")
                return@launch
            }
            val directions = matches.mapNotNull { it.headsign?.takeIf { h -> h.isNotBlank() } }.distinct()
            val chosen = direction?.takeIf { it in directions }
                ?: target.direction?.takeIf { it in directions }
                ?: directions.firstOrNull()
                ?: ""
            val line = matches.firstOrNull { it.headsign == chosen } ?: matches.first()
            val mode = line.mode
            val colorHex = TransitLineColor.hex(line.colorHex, mode)
            val departures = line.upcoming.map { departure ->
                val epoch = departure.epochSec ?: 0L
                TransitLineDeparture(
                    clockText = departure.clockText,
                    epochSec = epoch,
                    live = departure.realtime,
                    minutes = if (epoch > 0) ((epoch - now) / 60).toInt() else 0,
                )
            }
            val transfers = transfersOf(loaded, line)
            val tripId = line.upcoming.firstOrNull { !it.tripId.isNullOrBlank() }?.tripId
            var loadedRun: TransitLineRun? = null
            var sequenceUnavailable = false
            if (tripId == null) {
                sequenceUnavailable = true
            } else if (!allowRequest()) {
                sequenceUnavailable = true
            } else {
                loadedRun = run(tripId)
                sequenceUnavailable = loadedRun == null
            }
            if (gen != generation) return@launch
            val plan = loadedRun?.let {
                TransitLineRoute.build(
                    run = it,
                    nowEpochSec = now,
                    transfers = transfers,
                    openedStopId = target.stopId,
                    openedStopName = target.stopName,
                )
            }
            val geometry = loadedRun?.let { TransitLineRoute.geometryOf(it) }
            _state.update {
                it.copy(
                    open = true,
                    loading = false,
                    label = line.label?.trim()?.takeIf { l -> l.isNotEmpty() } ?: target.label,
                    mode = mode.name,
                    direction = chosen,
                    directions = directions,
                    stopName = loaded.stationName?.takeIf { n -> n.isNotBlank() } ?: target.stopName,
                    colorHex = colorHex,
                    colorSource = TransitLineColor.source(line.colorHex),
                    live = departures.any { d -> d.live } || loadedRun?.realTime == true,
                    fromName = plan?.fromName ?: "",
                    toName = plan?.toName ?: chosen,
                    departures = departures,
                    stops = plan?.stops.orEmpty(),
                    position = plan?.position,
                    transfers = transfers,
                    shape = geometry?.first.orEmpty(),
                    shapeSource = geometry?.second ?: TransitLineRoute.SHAPE_STOPS,
                    sequenceUnavailable = sequenceUnavailable,
                    error = null,
                    fetchedAtMillis = nowMillis(),
                    revision = it.revision + 1,
                )
            }
        }
    }

    private fun fail(gen: Int, key: String) {
        if (gen != generation) return
        _state.update {
            it.copy(
                open = true,
                loading = false,
                error = key,
                stops = emptyList(),
                position = null,
                sequenceUnavailable = true,
                fetchedAtMillis = nowMillis(),
                revision = it.revision + 1,
            )
        }
    }

    /** The other lines of the same board, one badge per line, in the board's order. */
    private fun transfersOf(board: StopDepartures, own: StopDepartureLine): List<TransitLineBadge> =
        board.lines
            .filter { it !== own && it.label?.trim() != own.label?.trim() }
            .mapNotNull { line ->
                val label = line.label?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                TransitLineBadge(
                    label = label,
                    mode = line.mode.name,
                    colorHex = TransitLineColor.hex(line.colorHex, line.mode),
                )
            }
            .distinctBy { it.label }
            .take(MAX_TRANSFERS)

    companion object {
        const val MAX_TRANSFERS = 5
    }
}

/**
 * Production wiring: the shared Transitous client, the fair-use counter, and the two requests the
 * sheet makes. The counter is this service's own, like the trip screen's; every service counts its
 * own calls against the same published policy and stops before the window is full.
 */
class TransitLineService(private val http: TransitousHttp, clock: Clock) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    val budget = TransitRequestBudget(nowMillis = { clock.nowMillis() })

    val store = TransitLineStore(
        scope = scope,
        board = { target ->
            if (target.stopId != null) {
                Transitous.boardFor(
                    http,
                    Transitous.MapStop(
                        name = target.stopName,
                        stopId = target.stopId,
                        parentId = target.parentId,
                        lat = target.lat,
                        lon = target.lng,
                        modes = target.modes,
                        siblingIds = target.siblingIds,
                    ),
                )
            } else {
                Transitous.board(http, target.lat, target.lng)
            }
        },
        run = { tripId -> TransitLineClient.run(http, tripId) },
        nowMillis = { clock.nowMillis() },
        allowRequest = { budget.take() },
    )
}

/**
 * The Debug fixture of the line sheet. Every value is a recorded answer around Metro Van Ness
 * Station on 2026-10-28: the board is `GET /api/v1/stoptimes?stopId=us-ca-SF-bayarea_15419` and
 * the run is `GET /api/v1/trip?tripId=20261028_06:31_us-ca-SFMTA_12133263_M11` (K towards
 * Embarcadero, 20 stops, real-time calls at the last six). The clock is pinned so the estimated
 * position is stable between runs. No stop, color or time here is invented.
 */
object TransitLineFixtures {
    const val NOW_EPOCH_SEC = 1_793_196_030L // 2026-10-28T14:00:30Z
    const val TRIP_ID = "20261028_06:31_us-ca-SFMTA_12133263_M11"

    val target: TransitLineTarget
        get() = TransitLineTarget(
            label = "K",
            direction = "Embarcadero Station",
            stopId = "us-ca-SF-bayarea_15419",
            stopName = "Metro Van Ness Station",
            lat = 37.775127,
            lng = -122.419250,
            modes = listOf("TRAM"),
        )

    private fun ep(iso: String): Long = kotlin.time.Instant.parse(iso).epochSeconds

    private fun departure(iso: String, live: Boolean, tripId: String? = null): app.vela.core.model.StopDeparture =
        app.vela.core.model.StopDeparture(
            epochSec = ep(iso), realtime = live, tripId = tripId, clockText = null,
        )

    /** The recorded board, lines and directions in the feed's order. */
    fun board(): StopDepartures = StopDepartures(
        stationName = "Metro Van Ness Station",
        lines = listOf(
            StopDepartureLine(
                label = "K", mode = TransitMode.TRAM, headsign = "Embarcadero Station", colorHex = "#437c93",
                upcoming = listOf(
                    departure("2026-10-28T14:02:00Z", live = true, tripId = TRIP_ID),
                    departure("2026-10-28T14:09:00Z", live = true),
                    departure("2026-10-28T14:18:00Z", live = true),
                ),
            ),
            StopDepartureLine(
                label = "K", mode = TransitMode.TRAM, headsign = "Balboa Park", colorHex = "#437c93",
                upcoming = listOf(
                    departure("2026-10-28T14:02:00Z", live = true, tripId = "20261028_06:53_us-ca-SFMTA_12133119_M11"),
                    departure("2026-10-28T14:20:00Z", live = true, tripId = "20261028_07:11_us-ca-SFMTA_12133185_M11"),
                ),
            ),
            StopDepartureLine(
                label = "L", mode = TransitMode.TRAM, headsign = "Embarcadero Station", colorHex = "#942d83",
                upcoming = listOf(
                    departure("2026-10-28T13:59:00Z", live = true),
                    departure("2026-10-28T14:09:00Z", live = true),
                ),
            ),
            StopDepartureLine(
                label = "M", mode = TransitMode.TRAM, headsign = "Embarcadero Station", colorHex = "#008547",
                upcoming = listOf(
                    departure("2026-10-28T13:59:00Z", live = true),
                    departure("2026-10-28T14:09:00Z", live = true),
                ),
            ),
            StopDepartureLine(
                label = "N", mode = TransitMode.TRAM, headsign = "Caltrain/Ballpark", colorHex = "#005b95",
                upcoming = listOf(
                    departure("2026-10-28T14:00:00Z", live = true),
                    departure("2026-10-28T14:10:00Z", live = true),
                ),
            ),
            StopDepartureLine(
                label = "J", mode = TransitMode.TRAM, headsign = "Embarcadero Station", colorHex = "#a96614",
                upcoming = listOf(departure("2026-10-28T14:08:00Z", live = true)),
            ),
        ),
    )

    private fun stop(
        name: String, stopId: String, code: String, lat: Double, lng: Double,
        expected: String, scheduled: String,
    ) = TransitLineClient.TripStopDto(
        name = name, stopId = stopId, lat = lat, lon = lng,
        departure = expected, scheduledDeparture = scheduled,
        tz = "America/Los_Angeles", stopCode = code,
    )

    /** The recorded run, in order. The last six calls are two minutes late in the feed. */
    fun run(tripId: String): TransitLineRun? {
        if (tripId != TRIP_ID) return null
        val leg = TransitLineClient.TripLegDto(
            from = stop("San Jose Ave & Geneva Ave", "us-ca-SFMTA_17778", "17778", 37.721237, -122.446220,
                "2026-10-28T13:31:00Z", "2026-10-28T13:31:00Z"),
            intermediateStops = listOf(
                stop("Ocean Ave/Ccsf Pedestrian Bridge", "us-ca-SFMTA_15784", "15784", 37.723040, -122.451450,
                    "2026-10-28T13:34:00Z", "2026-10-28T13:34:00Z"),
                stop("Ocean Ave & Lee St", "us-ca-SFMTA_15794", "15794", 37.723457, -122.454000,
                    "2026-10-28T13:35:00Z", "2026-10-28T13:35:00Z"),
                stop("Ocean Ave & Miramar Ave", "us-ca-SFMTA_15797", "15797", 37.724390, -122.458080,
                    "2026-10-28T13:37:00Z", "2026-10-28T13:37:00Z"),
                stop("Ocean Ave & Dorado Ter", "us-ca-SFMTA_15787", "15787", 37.724957, -122.461060,
                    "2026-10-28T13:38:00Z", "2026-10-28T13:38:00Z"),
                stop("Ocean Ave & Fairfield Way", "us-ca-SFMTA_15788", "15788", 37.726010, -122.464070,
                    "2026-10-28T13:39:00Z", "2026-10-28T13:39:00Z"),
                stop("Ocean Ave & Aptos Ave", "us-ca-SFMTA_15779", "15779", 37.728287, -122.467560,
                    "2026-10-28T13:41:00Z", "2026-10-28T13:41:00Z"),
                stop("Ocean Ave & San Leandro Way", "us-ca-SFMTA_15806", "15806", 37.729990, -122.469090,
                    "2026-10-28T13:42:00Z", "2026-10-28T13:42:00Z"),
                stop("Junipero Serra Blvd & Ocean Ave", "us-ca-SFMTA_17113", "17113", 37.731630, -122.471710,
                    "2026-10-28T13:44:00Z", "2026-10-28T13:44:00Z"),
                stop("West Portal/Sloat/St Francis Circle", "us-ca-SFMTA_17109", "17109", 37.734825, -122.471440,
                    "2026-10-28T13:46:00Z", "2026-10-28T13:46:00Z"),
                stop("West Portal Ave & 14th Ave", "us-ca-SFMTA_16898", "16898", 37.737858, -122.469040,
                    "2026-10-28T13:48:00Z", "2026-10-28T13:48:00Z"),
                stop("West Portal Station", "us-ca-SFMTA_16740", "16740", 37.741516, -122.465220,
                    "2026-10-28T13:51:00Z", "2026-10-28T13:51:00Z"),
                stop("Metro Forest Hill Station/Downtown", "us-ca-SFMTA_15730", "15730", 37.748352, -122.458626,
                    "2026-10-28T13:52:00Z", "2026-10-28T13:52:00Z"),
                stop("Metro Castro Station/Downtown", "us-ca-SFMTA_15728", "15728", 37.762620, -122.435234,
                    "2026-10-28T13:58:00Z", "2026-10-28T13:58:00Z"),
                stop("Metro Church Station/Downtown", "us-ca-SFMTA_15726", "15726", 37.767193, -122.429170,
                    "2026-10-28T14:00:00Z", "2026-10-28T13:59:00Z"),
                stop("Metro Van Ness Station", "us-ca-SFMTA_15419", "15419", 37.775127, -122.419250,
                    "2026-10-28T14:02:00Z", "2026-10-28T14:01:00Z"),
                stop("Metro Civic Center Station/Downtn", "us-ca-SFMTA_15727", "15727", 37.779713, -122.413345,
                    "2026-10-28T14:03:00Z", "2026-10-28T14:02:00Z"),
                stop("Metro Powell Station/Downtown", "us-ca-SFMTA_15417", "15417", 37.784653, -122.407090,
                    "2026-10-28T14:04:00Z", "2026-10-28T14:03:00Z"),
                stop("Metro Montgomery Station/Downtown", "us-ca-SFMTA_15731", "15731", 37.789220, -122.401350,
                    "2026-10-28T14:05:00Z", "2026-10-28T14:04:00Z"),
            ),
            to = stop("Metro Embarcadero Station", "us-ca-SFMTA_16992", "16992", 37.793133, -122.396430,
                "2026-10-28T14:08:00Z", "2026-10-28T14:06:00Z").copy(arrival = "2026-10-28T14:08:00Z", departure = null),
            mode = "TRAM",
            headsign = "Embarcadero Station",
            routeShortName = "K",
            routeColor = "437c93",
            routeTextColor = "ffffff",
            realTime = true,
        )
        return TransitLineClient.runOf(leg, tripId)
    }

    /** A store wired to the fixture, with no network and a pinned clock. */
    fun store(): TransitLineStore = TransitLineStore(
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
        board = { board() },
        run = { tripId -> run(tripId) },
        nowMillis = { NOW_EPOCH_SEC * 1000L },
    )
}
