package app.vela.ios.transit

import app.vela.core.model.LatLng
import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** T-3: the trip screen's cards, header, shift query, skip and nearby mapping. */
class TransitTripTest {
    private val nowSec = 1_800_000_000L
    private val trip = TransitPreview.sf
    private val segments = TransitTrip.segmentsOf(trip)
    private val ride = segments.first { it.kind == TransitTrip.KIND_RIDE }
    private val header = TransitTrip.header(
        TransitTripFixtures.headerBoard(nowSec), ride, nowSec,
    )

    @Test fun aTripBecomesWalkWaitRideWalkCards() {
        assertEquals(
            listOf(
                TransitTrip.KIND_WALK, TransitTrip.KIND_WAIT,
                TransitTrip.KIND_RIDE, TransitTrip.KIND_WALK,
            ),
            segments.map { it.kind },
        )
        val walk = segments.first()
        assertEquals("Metro Van Ness Station", walk.alightName)
        assertEquals("1 min", walk.durationText)
        assertFalse(walk.live)
        assertFalse(walk.skippable)
        val wait = segments[1]
        assertEquals("9:28 AM", wait.waitUntil)
        assertEquals("Metro Van Ness Station", wait.boardName)
        assertNull(wait.lineLabel)
    }

    @Test fun theRideCardKeepsTheFeedsLineColorsTimesAndRealtimePair() {
        assertEquals("K", ride.lineLabel)
        assertEquals("#437c93", ride.lineColor)
        assertEquals("#FFFFFF", ride.lineTextColor)
        assertEquals("TRAM", ride.mode)
        assertEquals("Embarcadero Station", ride.direction)
        assertEquals("Metro Van Ness Station", ride.boardName)
        assertEquals("Metro Embarcadero Station", ride.alightName)
        assertEquals("15419", ride.boardCode)
        assertEquals("16992", ride.alightCode)
        assertEquals("9:24 AM", ride.scheduledDeparture)
        assertEquals("9:28 AM", ride.estimatedDeparture)
        assertEquals("9:29 AM", ride.scheduledArrival)
        assertEquals("9:35 AM", ride.estimatedArrival)
        assertEquals(4, ride.delayMinutes)
        assertEquals(4, ride.stopCount)
        assertTrue(ride.live)
        assertTrue(ride.skippable)
    }

    @Test fun aWalkBetweenTwoRidesIsATransferAndEachRideGetsItsWait() {
        val line = TransitLine("K", TransitMode.TRAM, "#437c93", "#FFFFFF")
        val second = TransitLine("14", TransitMode.BUS, "#0f6cbd", "#FFFFFF")
        fun rideStep(line: TransitLine, name: String) = TransitStep(
            mode = line.mode, line = line, headsign = "Downtown",
            boardStop = TransitStopTime(name = name, timeText = "10:00 AM"),
            alightStop = TransitStopTime(name = "$name off", timeText = "10:05 AM"),
            numStops = 2,
        )
        val trip = TransitItinerary(
            steps = listOf(
                TransitStep(mode = TransitMode.WALK, walkFrom = LatLng(37.1, -122.1)),
                rideStep(line, "A"),
                TransitStep(mode = TransitMode.WALK),
                rideStep(second, "B"),
                TransitStep(mode = TransitMode.WALK),
            ),
        )
        assertEquals(
            listOf("WALK", "WAIT", "RIDE", "TRANSFER", "WAIT", "RIDE", "WALK"),
            TransitTrip.segmentsOf(trip).map { it.kind },
        )
    }

    @Test fun theHeaderKeepsOnlyTheRidesLineAndDirection() {
        val board = StopDepartures(
            stationName = "Metro Van Ness Station",
            lines = listOf(
                StopDepartureLine(
                    label = "K", mode = TransitMode.TRAM, headsign = "Balboa Park",
                    colorHex = "#437c93",
                    upcoming = listOf(StopDeparture("8:55 AM", nowSec - 600, true)),
                ),
                StopDepartureLine(
                    label = "K", mode = TransitMode.TRAM, headsign = "Embarcadero Station",
                    colorHex = "#437c93",
                    upcoming = listOf(
                        StopDeparture("9:32 AM", nowSec + 120, true),
                        StopDeparture("9:40 AM", nowSec + 480, false),
                    ),
                ),
                StopDepartureLine(
                    label = "14", mode = TransitMode.BUS, headsign = "Ferry Plaza",
                    colorHex = "#0f6cbd",
                    upcoming = listOf(StopDeparture("9:31 AM", nowSec + 180, false)),
                ),
            ),
        )
        val h = TransitTrip.header(board, ride, nowSec)
        assertTrue(h.available)
        assertEquals("Metro Van Ness Station", h.stopName)
        assertEquals("K", h.lineLabel)
        assertEquals("Embarcadero Station", h.direction)
        assertEquals(listOf(nowSec + 120, nowSec + 480), h.departures.map { it.epochSec })
        assertEquals(listOf(true, false), h.departures.map { it.realtime })
        assertEquals(listOf(2, 8), h.departures.map { it.minutes })
    }

    @Test fun aHeaderNeverInventsADepartureWhenTheFeedIsSilent() {
        val missing = TransitTrip.header(null, ride, nowSec)
        assertFalse(missing.available)
        assertTrue(missing.departures.isEmpty())
        assertEquals("Metro Van Ness Station", missing.stopName)

        val unmatched = TransitTrip.header(
            StopDepartures(stationName = "Elsewhere", lines = emptyList()), ride, nowSec,
        )
        assertTrue(unmatched.available)
        assertTrue(unmatched.departures.isEmpty())
    }

    @Test fun leaveLaterAnchorsOnTheStopsOwnDepartureAndAsksForALaterStart() {
        val shift = TransitTrip.shift(trip, ride, header, TransitTrip.SHIFT_DEPART_AT, 15)
        assertEquals(TransitTrip.SHIFT_DEPART_AT, shift?.timeMode)
        assertEquals(nowSec + 120 + 900, shift?.epochSec)
        assertEquals(nowSec + 120, shift?.anchorEpochSec)
        assertEquals("board", shift?.anchorSource)
        assertEquals("K", shift?.lineLabel)
        assertEquals("Metro Van Ness Station", shift?.stopName)
    }

    @Test fun leaveLaterFallsBackToTheTripsStartOnlyForItsFirstSegment() {
        val first = segments.first()
        val silent = TransitTrip.header(null, first, nowSec)
        val shift = TransitTrip.shift(trip, first, silent, TransitTrip.SHIFT_DEPART_AT, 5)
        assertEquals(trip.departureEpochSec!! + 300, shift?.epochSec)
        assertEquals("trip_start", shift?.anchorSource)

        // A later segment without a matching board departure has no honest anchor.
        val unmatched = TransitTrip.header(
            StopDepartures(stationName = "Metro Van Ness Station", lines = emptyList()), ride, nowSec,
        )
        assertNull(TransitTrip.shift(trip, ride, unmatched, TransitTrip.SHIFT_DEPART_AT, 5))
    }

    @Test fun arriveByOnlyConstrainsTheDestination() {
        val last = segments.last()
        val shift = TransitTrip.shift(trip, last, header, TransitTrip.SHIFT_ARRIVE_BY, 10)
        assertEquals(TransitTrip.SHIFT_ARRIVE_BY, shift?.timeMode)
        assertEquals(trip.arrivalEpochSec!! + 600, shift?.epochSec)
        assertEquals("trip_end", shift?.anchorSource)
        // Neither the middle ride nor a walk before the last step is the destination.
        assertNull(TransitTrip.shift(trip, ride, header, TransitTrip.SHIFT_ARRIVE_BY, 10))
        assertNull(TransitTrip.shift(trip, segments[0], header, TransitTrip.SHIFT_ARRIVE_BY, 10))
        assertNull(TransitTrip.shift(trip, last, header, 9, 10))
    }

    @Test fun skipAdvancesToTheNextRunOfTheSameLineAndKeepsTheRest() {
        val skip = TransitTrip.skip(header, ride)
        assertEquals(nowSec + 480, skip?.epochSec)
        assertEquals("9:36 AM", skip?.clockText)
        assertFalse(skip!!.realtime)
        assertEquals(8, skip.minutes)
        assertEquals("K", skip.lineLabel)
        assertEquals(nowSec + 120, skip.passedEpochSec)

        val taken = TransitTrip.shiftTo(trip, ride, skip.epochSec)
        assertEquals(TransitTrip.SHIFT_DEPART_AT, taken.timeMode)
        assertEquals(skip.epochSec, taken.epochSec)
        assertEquals("skip", taken.anchorSource)

        val advanced = TransitTrip.withoutDeparture(header, skip.passedEpochSec)
        assertEquals(listOf(nowSec + 480, nowSec + 960, nowSec + 1_440), advanced.departures.map { it.epochSec })
        // Letting pass the last listed run leaves nothing to skip to.
        assertNull(TransitTrip.skip(transitTripHeader(listOf(header.departures.first())), ride))
    }

    @Test fun skipNeedsARideAndAKnownRun() {
        assertNull(TransitTrip.skip(header, segments[0]))
        val empty = TransitTrip.header(null, ride, nowSec)
        assertNull(TransitTrip.skip(empty, ride))
    }

    @Test fun nearbyListsEveryServedLineWithItsOwnDepartures() {
        val lines = TransitTrip.nearby(TransitTripFixtures.nearbyBoard(nowSec), nowSec)
        assertEquals(listOf("K", "14", "47"), lines.map { it.label })
        assertEquals(listOf("Embarcadero Station", "Ferry Plaza", "Fisherman's Wharf"), lines.map { it.headsign })
        assertEquals(listOf(2, 3, 4), lines.map { it.departures.first().minutes })
        assertTrue(lines.first().departures.first().realtime)
        assertFalse(lines[1].departures.first().realtime)
        assertEquals("#c0392b", lines[2].color)
    }

    @Test fun nearbyDropsLinesWithNoRunLeftAndInventsNothing() {
        val stale = StopDepartures(
            stationName = "Old stop",
            lines = listOf(
                StopDepartureLine(
                    label = "N", mode = TransitMode.TRAM, headsign = "Ocean Beach",
                    upcoming = listOf(StopDeparture("9:00 AM", nowSec - 600, false)),
                ),
                StopDepartureLine(label = "J", mode = TransitMode.TRAM, headsign = "Church"),
            ),
        )
        assertTrue(TransitTrip.nearby(stale, nowSec).isEmpty())
        assertTrue(TransitTrip.nearby(null, nowSec).isEmpty())
    }

    @Test fun optionsKeepThePlannersOrderAndItsRealtimeFlags() {
        val later = TransitTripFixtures.shifted(trip, 15)
        val rows = TransitTrip.options(later)
        assertEquals(2, rows.size)
        assertEquals("9:42 AM", rows[0].departureText)
        assertEquals("9:54 AM", rows[0].arrivalText)
        assertEquals(listOf("K"), rows[0].lines)
        assertTrue(rows[0].live)
        assertEquals("9:57 AM", rows[1].departureText)
    }

    @Test fun theHeaderAlsoReadsTheStoresMappedBoard() {
        val state = TransitBoardState(
            open = true,
            stopName = "Metro Van Ness Station",
            lines = listOf(
                TransitBoardLine(
                    label = "K", mode = "TRAM", headsign = "Embarcadero Station",
                    color = "#437c93",
                    departures = listOf(
                        TransitBoardDeparture("9:32 AM", nowSec + 120, true, 2, "trip-1"),
                        TransitBoardDeparture("9:40 AM", nowSec + 480, false, 8, null),
                    ),
                ),
                TransitBoardLine(
                    label = "14", mode = "BUS", headsign = "Ferry Plaza", color = "#0f6cbd",
                    departures = listOf(TransitBoardDeparture("9:31 AM", nowSec + 180, false, 3, null)),
                ),
            ),
        )
        val h = TransitTrip.header(state, ride)
        assertEquals("Metro Van Ness Station", h.stopName)
        assertEquals("K", h.lineLabel)
        assertEquals(listOf(nowSec + 120, nowSec + 480), h.departures.map { it.epochSec })
        assertEquals("trip-1", h.departures.first().tripId)
        assertEquals(listOf("K", "14"), TransitTrip.nearby(state).map { it.label })
    }

    private fun transitTripHeader(departures: List<TransitTripDeparture>) =
        header.copy(departures = departures)
}
