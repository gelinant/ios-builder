package app.vela.ios.transit

import app.vela.core.data.transit.TransitLineClient
import app.vela.core.data.transit.TransitLineRun
import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The ribbon's rules: the stop order and times are the feed's, the vehicle position is an
 * interpolation between two of those times, and a line without a `routeColor` takes the mode
 * colour while saying so. The run and board are the captured San Francisco values of
 * [TransitLineFixtures].
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TransitLineRouteTest {
    private val now = TransitLineFixtures.NOW_EPOCH_SEC
    private val run = assertNotNull(TransitLineFixtures.run(TransitLineFixtures.TRIP_ID))

    private val transfers = listOf(
        TransitLineBadge("L", "TRAM", "#942d83"),
        TransitLineBadge("M", "TRAM", "#008547"),
        TransitLineBadge("N", "TRAM", "#005b95"),
        TransitLineBadge("J", "TRAM", "#a96614"),
    )

    @Test
    fun `the ribbon keeps the feed order and its times and delays`() {
        val plan = TransitLineRoute.build(
            run = run, nowEpochSec = now, transfers = transfers,
            openedStopId = "us-ca-SF-bayarea_15419", openedStopName = "Metro Van Ness Station",
        )
        assertEquals(20, plan.stopCount)
        assertEquals("San Jose Ave & Geneva Ave", plan.stops.first().name)
        assertEquals("Metro Embarcadero Station", plan.stops.last().name)
        assertEquals("San Jose Ave & Geneva Ave", plan.fromName)
        assertEquals("Metro Embarcadero Station", plan.toName)
        // The feed is two minutes late from Church onwards; that is written, not inferred.
        val church = plan.stops.first { it.name == "Metro Church Station/Downtown" }
        assertEquals(1, church.delayMin)
        assertTrue(church.hasDelay)
        val geneva = plan.stops.first()
        assertFalse(geneva.hasDelay)
        // Only the opened stop carries the board's other lines, and only that row.
        val vanNess = plan.stops.first { it.name == "Metro Van Ness Station" }
        assertEquals(listOf("L", "M", "N", "J"), vanNess.transferLines.map { it.label })
        assertEquals(1, plan.stops.count { it.transferLines.isNotEmpty() })
        assertEquals("#942d83", vanNess.transferLines.first().colorHex)
    }

    @Test
    fun `the vehicle sits between the two calls that bracket the clock`() {
        val plan = TransitLineRoute.build(run, now)
        val position = assertNotNull(plan.position)
        assertTrue(position.estimated)
        assertFalse(position.beforeStart)
        assertFalse(position.finished)
        assertEquals(14, position.fromIndex)
        assertEquals(15, position.toIndex)
        assertEquals(15, position.stopIndex)
        // 14:00:30 is a quarter of the way from Church (14:00) to Van Ness (14:02).
        assertEquals(0.25, position.fraction, 0.001)
        assertEquals("Metro Van Ness Station", position.nextStopName)
        assertEquals(90, position.secondsToNextStop)
        // Church already called, Van Ness is next: fifteen stops are behind the vehicle.
        assertEquals(15, position.passedCount)
        assertEquals(15, plan.stops.indexOfFirst { it.next })
        assertTrue(plan.stops.take(15).all { it.passed })
        assertFalse(plan.stops[15].passed)
    }

    @Test
    fun `before the origin and after the terminus are said as such`() {
        val before = assertNotNull(TransitLineRoute.build(run, now - 3_600).position)
        assertTrue(before.beforeStart)
        assertEquals(0, before.stopIndex)
        assertEquals(0, before.passedCount)

        val after = assertNotNull(TransitLineRoute.build(run, now + 3_600).position)
        assertTrue(after.finished)
        assertEquals(19, after.stopIndex)
        assertEquals(1.0, after.fraction)
        assertEquals(20, after.passedCount)
    }

    @Test
    fun `a run with no timed stop has no position and no invented row`() {
        val untimed = run.copy(stops = run.stops.map { it.copy(expectedEpochSec = null, clockText = null) })
        val plan = TransitLineRoute.build(untimed, now)
        assertNull(plan.position)
        assertEquals(20, plan.stopCount)
        assertTrue(plan.stops.none { it.next || it.passed })
    }

    @Test
    fun `the feed colour wins and the mode colour is the named fallback`() {
        assertEquals("#437c93", TransitLineColor.hex("#437c93", TransitMode.TRAM))
        assertEquals(TransitLineColor.SOURCE_FEED, TransitLineColor.source("#437c93"))
        // No routeColor in the feed: Vela's own mode colour, and the source says so.
        assertEquals("#437c93", TransitLineColor.hex(null, TransitMode.TRAM))
        assertEquals(TransitLineColor.SOURCE_MODE, TransitLineColor.source(null))
        assertEquals("#0f6cbd", TransitLineColor.hex("", TransitMode.BUS))
        assertEquals("#d93025", TransitLineColor.hex("not-a-colour", TransitMode.SUBWAY))
        assertEquals(TransitLineColor.SOURCE_MODE, TransitLineColor.source("not-a-colour"))
    }

    @Test
    fun `the whole line geometry is the feed shape or the stop chain and is labelled`() {
        val stopsOnly = TransitLineRoute.geometryOf(run)
        assertEquals(TransitLineRoute.SHAPE_STOPS, stopsOnly.second)
        assertEquals(20, stopsOnly.first.size)

        val shaped = run.copy(shape = listOf(run.stops.first().let { app.vela.core.model.LatLng(it.latitude, it.longitude) },
            run.stops.last().let { app.vela.core.model.LatLng(it.latitude, it.longitude) }))
        val geometry = TransitLineRoute.geometryOf(shaped)
        assertEquals(TransitLineRoute.SHAPE_FEED, geometry.second)
        assertEquals(2, geometry.first.size)
    }

    // --- the store -------------------------------------------------------------------------------

    private fun departure(iso: String, live: Boolean, tripId: String? = null) = StopDeparture(
        epochSec = kotlin.time.Instant.parse(iso).epochSeconds, realtime = live, tripId = tripId,
    )

    private fun board(vararg lines: StopDepartureLine) =
        StopDepartures(stationName = "Metro Van Ness Station", lines = lines.toList())

    @Test
    fun `opening loads the board and the run and its transfers`() = runTest {
        val store = TransitLineStore(
            scope = backgroundScope,
            board = { TransitLineFixtures.board() },
            run = { tripId -> TransitLineFixtures.run(tripId) },
            nowMillis = { now * 1000L },
        )
        store.open(TransitLineFixtures.target)
        runCurrent()

        val state = store.state.value
        assertFalse(state.loading)
        assertNull(state.error)
        assertEquals(20, state.stopCount)
        assertEquals("#437c93", state.colorHex)
        assertEquals(TransitLineColor.SOURCE_FEED, state.colorSource)
        assertEquals(listOf("Embarcadero Station", "Balboa Park"), state.directions)
        assertEquals("Embarcadero Station", state.direction)
        assertEquals(3, state.departures.size)
        assertTrue(state.departures.first().live)
        assertTrue(state.estimated)
        assertEquals("San Jose Ave & Geneva Ave", state.fromName)
        assertEquals("Metro Embarcadero Station", state.toName)
        assertFalse(state.sequenceUnavailable)
        assertEquals(4, state.transfers.size)
        assertEquals(TransitLineRoute.SHAPE_STOPS, state.shapeSource)
        assertTrue(state.shape.isNotEmpty())
    }

    @Test
    fun `a run with no trip id shows the departures and says the sequence is missing`() = runTest {
        val noTrips = board(
            StopDepartureLine(
                label = "K", mode = TransitMode.TRAM, headsign = "Embarcadero Station", colorHex = "#437c93",
                upcoming = listOf(departure("2026-10-28T14:02:00Z", live = true)),
            ),
        )
        val store = TransitLineStore(
            scope = backgroundScope,
            board = { noTrips },
            run = { null },
            nowMillis = { now * 1000L },
        )
        store.open(TransitLineFixtures.target)
        runCurrent()

        val state = store.state.value
        assertTrue(state.sequenceUnavailable)
        assertEquals(0, state.stopCount)
        assertEquals(1, state.departures.size)
        assertNull(state.position)
        assertEquals("Embarcadero Station", state.toName)
    }

    @Test
    fun `a line the board does not serve is named and never invented`() = runTest {
        val other = board(
            StopDepartureLine(
                label = "14", mode = TransitMode.BUS, headsign = "Ferry Plaza", colorHex = "#0f6cbd",
                upcoming = listOf(departure("2026-10-28T14:05:00Z", live = false)),
            ),
        )
        val store = TransitLineStore(backgroundScope, { other }, { null }, { now * 1000L })
        store.open(TransitLineFixtures.target)
        runCurrent()
        assertEquals("no_line", store.state.value.error)
        assertEquals(0, store.state.value.stopCount)

        val empty = TransitLineStore(backgroundScope, { null }, { null }, { now * 1000L })
        empty.open(TransitLineFixtures.target)
        runCurrent()
        assertEquals("no_departures", empty.state.value.error)
    }

    @Test
    fun `switching direction reuses the board and asks only for that run`() = runTest {
        var boardCalls = 0
        var runCalls = 0
        val store = TransitLineStore(
            scope = backgroundScope,
            board = { boardCalls += 1; TransitLineFixtures.board() },
            run = { tripId -> runCalls += 1; TransitLineFixtures.run(tripId) },
            nowMillis = { now * 1000L },
        )
        store.open(TransitLineFixtures.target)
        runCurrent()
        assertEquals(1, boardCalls)
        assertEquals(1, runCalls)

        store.selectDirection("Balboa Park")
        runCurrent()
        assertEquals(1, boardCalls, "the board already lists both directions")
        assertEquals(2, runCalls)
        val state = store.state.value
        assertEquals("Balboa Park", state.direction)
        assertEquals(2, state.departures.size)
        // The fixture has no run for the other direction: the sheet says so instead of showing K's
        // Embarcadero stops as if they were the way back.
        assertTrue(state.sequenceUnavailable)
        assertEquals(0, state.stopCount)
    }

    @Test
    fun `the fair-use gate stops the request and names it`() = runTest {
        var asked = 0
        val store = TransitLineStore(
            scope = backgroundScope,
            board = { asked += 1; TransitLineFixtures.board() },
            run = { asked += 1; TransitLineFixtures.run(it) },
            nowMillis = { now * 1000L },
            allowRequest = { false },
        )
        store.open(TransitLineFixtures.target)
        runCurrent()
        assertEquals(0, asked)
        assertEquals("budget_exhausted", store.state.value.error)
    }

    @Test
    fun `closing clears everything`() = runTest {
        val store = TransitLineStore(
            backgroundScope, { TransitLineFixtures.board() }, { TransitLineFixtures.run(it) }, { now * 1000L },
        )
        store.open(TransitLineFixtures.target)
        runCurrent()
        assertTrue(store.state.value.open)
        store.close()
        assertEquals(TransitLineState(), store.state.value)
    }

    @Test
    fun `a run with no colour at all keeps the mode colour and the source`() {
        val grey = TransitLineRun(
            tripId = "t", label = "42", headsign = "Downtown", mode = TransitMode.BUS, colorHex = null,
            textColorHex = null, realTime = false, canceled = false, shape = emptyList(),
            stops = run.stops.take(2).map { it.copy(expectedEpochSec = now, scheduledEpochSec = now) },
        )
        assertEquals("#0f6cbd", TransitLineColor.hex(grey.colorHex, grey.mode))
        assertEquals(TransitLineColor.SOURCE_MODE, TransitLineColor.source(grey.colorHex))
    }

    @Test
    fun `the fixture clock is inside the captured run`() {
        // Guard: a moved fixture clock would silently drop the estimated marker from the screenshot.
        val first = assertNotNull(run.stops.first().expectedEpochSec)
        val last = assertNotNull(run.stops.last().expectedEpochSec)
        assertTrue(now > first && now < last)
        assertEquals("America/Los_Angeles", run.stops.first().tz)
        assertFalse(TransitLineClient.colorOf(run.colorHex).isNullOrBlank())
    }
}
