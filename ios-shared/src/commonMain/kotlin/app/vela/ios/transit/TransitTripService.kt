package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitMode
import app.vela.core.platform.Clock
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * The trip screen's own board feed. It owns one [TransitBoardStore], so the map's stop board and the
 * trip screen never steal each other's target; the store keeps the 30 s refresh, the countdown rules
 * and the offline behavior of T-1. The service is the only place that builds a Transitous request
 * for this screen, and it is keyless like the rest of Transitous.
 */
class TransitTripService(private val http: TransitousHttp, clock: Clock) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** The shared fair-use counter; reachability and live lines use the same one. */
    val budget = TransitRequestBudget(nowMillis = { clock.nowMillis() })

    val board = TransitBoardStore(
        scope = scope,
        source = { target ->
            if (target.stopId != null) {
                Transitous.boardFor(
                    http,
                    Transitous.MapStop(
                        name = target.name,
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
        nowMillis = { clock.nowMillis() },
    )

    /** The nearest stop group at a coordinate; the header and the nearby tab both use it. */
    fun openAt(lat: Double, lng: Double, name: String) {
        board.open(lat = lat, lng = lng, name = name)
    }

    fun refresh() {
        board.refresh()
    }

    fun close() {
        board.close()
    }

    /** One via search for a chosen intermediate stop; null when the stop or the answer is absent. */
    suspend fun viaOptions(
        trip: TransitItinerary,
        segment: TransitTripSegment,
        candidate: TransitViaCandidate,
    ): TransitViaOptions? = TransitAlternatives.plan(http, trip, segment, candidate)
}

/**
 * Deterministic data for the offline trip-screen scenarios. Production never calls it; the Debug
 * guide and the UI tests use it so a run without the feed still proves the screen, the shift query
 * and the nearby mapping. No value here is presented as live outside these scenarios.
 */
object TransitTripFixtures {
    /** A Van Ness board whose K run is the one the recorded itinerary rides ("9:28 AM"). */
    fun headerBoard(nowSec: Long): StopDepartures = StopDepartures(
        stationName = "Metro Van Ness Station",
        lines = listOf(
            StopDepartureLine(
                label = "K", mode = TransitMode.TRAM, headsign = "Embarcadero Station",
                colorHex = "#437c93",
                upcoming = listOf(
                    departure(nowSec, 120, live = true, clock = "9:28 AM"),
                    departure(nowSec, 480, live = false, clock = "9:36 AM"),
                    departure(nowSec, 960, live = true, clock = "9:44 AM"),
                    departure(nowSec, 1_440, live = false, clock = "9:52 AM"),
                ),
            ),
            StopDepartureLine(
                label = "14", mode = TransitMode.BUS, headsign = "Ferry Plaza",
                colorHex = "#0f6cbd",
                upcoming = listOf(
                    departure(nowSec, 180, live = false, clock = "9:31 AM"),
                    departure(nowSec, 600, live = false, clock = "9:38 AM"),
                ),
            ),
        ),
    )

    /** The trip's origin stop: two lines, enough for the nearby tab to show real rows. */
    fun nearbyBoard(nowSec: Long): StopDepartures = StopDepartures(
        stationName = "Van Ness Station",
        lines = listOf(
            StopDepartureLine(
                label = "K", mode = TransitMode.TRAM, headsign = "Embarcadero Station",
                colorHex = "#437c93",
                upcoming = listOf(
                    departure(nowSec, 120, live = true, clock = "9:28 AM"),
                    departure(nowSec, 480, live = false, clock = "9:36 AM"),
                ),
            ),
            StopDepartureLine(
                label = "14", mode = TransitMode.BUS, headsign = "Ferry Plaza",
                colorHex = "#0f6cbd",
                upcoming = listOf(
                    departure(nowSec, 180, live = false, clock = "9:31 AM"),
                    departure(nowSec, 600, live = false, clock = "9:38 AM"),
                ),
            ),
            StopDepartureLine(
                label = "47", mode = TransitMode.BUS, headsign = "Fisherman's Wharf",
                colorHex = "#c0392b",
                upcoming = listOf(
                    departure(nowSec, 240, live = true, clock = "9:33 AM"),
                    departure(nowSec, 900, live = false, clock = "9:44 AM"),
                ),
            ),
        ),
    )

    /**
     * Two display-only options for the via screenshot. They are the recorded trip with a shifted
     * pair of clock texts and no rewritten stop; the Debug screen never lets them be adopted.
     */
    fun via(trip: TransitItinerary): List<TransitItinerary> = shifted(trip, 0)

    /**
     * Two display-only options for the shifted-segment screenshot. They carry the recorded trip's
     * lines and a shifted pair of clock texts; their step times are not rewritten, so the Debug
     * screen never lets them be adopted as a trip.
     */
    fun shifted(trip: TransitItinerary, minutes: Int): List<TransitItinerary> = listOf(0, 15).map { extra ->
        val delta = (minutes + extra) * 60L
        trip.copy(
            departureEpochSec = trip.departureEpochSec?.plus(delta),
            arrivalEpochSec = trip.arrivalEpochSec?.plus(delta),
            departureText = shiftClock(trip.departureText, minutes + extra),
            arrivalText = shiftClock(trip.arrivalText, minutes + extra),
        )
    }

    private fun departure(nowSec: Long, offsetSec: Long, live: Boolean, clock: String) =
        StopDeparture(clockText = clock, epochSec = nowSec + offsetSec, realtime = live)

    /** "9:27 AM" plus minutes, in the same 12-hour shape the fixture was recorded with. */
    private fun shiftClock(text: String?, minutes: Int): String? {
        val match = Regex("""(\d{1,2}):(\d{2})\s*(AM|PM)""").find(text ?: return null) ?: return text
        val hour = match.groupValues[1].toInt()
        val minute = match.groupValues[2].toInt()
        val pm = match.groupValues[3] == "PM"
        val day = if (pm) (hour % 12) + 12 else hour % 12
        val total = (day * 60 + minute + minutes) % (24 * 60)
        val shownHour = (total / 60) % 12
        val suffix = if (total / 60 < 12) "AM" else "PM"
        val clockMinute = (total % 60).toString().padStart(2, '0')
        return "${if (shownHour == 0) 12 else shownHour}:$clockMinute $suffix"
    }
}
