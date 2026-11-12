package app.vela.ios.transit

import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class TransitTripsTest {
    private fun walk(from: Long, to: Long) =
        TransitStep(mode = TransitMode.WALK, durationText = "x", departEpochSec = from, arriveEpochSec = to)

    private fun ride(name: String, from: Long, to: Long, live: Boolean = false) = TransitStep(
        mode = TransitMode.BUS, line = TransitLine(name, TransitMode.BUS), departEpochSec = from, arriveEpochSec = to,
        realTime = live,
    )

    private fun trip(dep: Long?, arr: Long?, vararg steps: TransitStep) =
        TransitItinerary(departureEpochSec = dep, arrivalEpochSec = arr, steps = steps.toList())

    @AfterTest fun disarm() {
        TransitTripsFixture.json = null
    }

    @Test fun transfersAreRidesMinusOne() {
        assertEquals(0, TransitTrips.transfers(trip(0, 10, walk(0, 60), ride("14R", 60, 600))))
        assertEquals(2, TransitTrips.transfers(trip(0, 10, ride("A", 0, 1), ride("B", 1, 2), walk(2, 3), ride("C", 3, 4))))
        assertEquals(0, TransitTrips.transfers(trip(0, 10, walk(0, 60))))
    }

    @Test fun walkingAddsEveryWalkOnItsOwnClocks() {
        val t = trip(0, 900, walk(0, 60), ride("Yellow-N", 60, 600), walk(600, 720), ride("14R", 720, 780), walk(780, 960))
        assertEquals(360L, TransitTrips.walkSeconds(t))
        // Without clocks the walk's own text is read; an unreadable one counts nothing.
        val text = TransitStep(mode = TransitMode.WALK, durationText = "1 h 5 min")
        assertEquals(3900L, TransitTrips.walkSeconds(trip(null, null, text, TransitStep(mode = TransitMode.WALK))))
    }

    @Test fun liveIsTheFirstRideOnly() {
        assertTrue(TransitTrips.live(trip(0, 1, walk(0, 1), ride("14R", 1, 2, live = true), ride("F", 2, 3))))
        assertFalse(TransitTrips.live(trip(0, 1, walk(0, 1), ride("Blue-N", 1, 2), ride("M", 2, 3, live = true))))
        assertFalse(TransitTrips.live(trip(0, 1, walk(0, 1))))
    }

    @Test fun bestLeadsWithTheEarliestArrival() {
        val a = trip(100, 1900, ride("14R", 100, 1900))
        val b = trip(200, 1200, ride("Green-N", 200, 1200))
        val c = trip(300, 1200, ride("Yellow-N", 300, 1200))
        val noClock = trip(null, null, ride("?", 0, 0))
        val ordered = TransitTrips.order(listOf(noClock, a, b, c), TransitPlanQuery.ROUTE_BEST, TransitPlanQuery.TIME_NOW)
        // Same arrival keeps the planner's order; a trip without clocks goes last.
        assertEquals(listOf(b, c, a, noClock), ordered)
        assertEquals(ordered, TransitTrips.order(listOf(noClock, a, b, c), 0, TransitPlanQuery.TIME_DEPART_AT))
    }

    @Test fun arriveByLeadsWithTheLatestDeparture() {
        val early = trip(100, 900, ride("A", 100, 900))
        val late = trip(400, 950, ride("B", 400, 950))
        assertEquals(listOf(late, early), TransitTrips.order(listOf(early, late), 0, TransitPlanQuery.TIME_ARRIVE_BY))
    }

    @Test fun preferencesSortFirstThenByArrival() {
        val direct = trip(0, 1800, walk(0, 60), ride("14R", 60, 1800))
        val transfer = trip(0, 1000, walk(0, 300), ride("Blue-N", 300, 600), walk(600, 700), ride("M", 700, 1000))
        val directLate = trip(0, 2400, walk(0, 30), ride("14", 30, 2400))
        val trips = listOf(transfer, directLate, direct)
        assertEquals(listOf(direct, directLate, transfer),
            TransitTrips.order(trips, TransitPlanQuery.ROUTE_FEWER_TRANSFERS, 0))
        assertEquals(listOf(directLate, direct, transfer),
            TransitTrips.order(trips, TransitPlanQuery.ROUTE_LESS_WALKING, 0))
        assertEquals(listOf(transfer, direct, directLate), TransitTrips.order(trips, 0, 0))
    }

    @Test fun theChooserKeepsTheFirstFiveInItsOrder() {
        val trips = (0 until 7).map { i -> trip(0, 2000L - i * 100, ride("L$i", 0, 2000L - i * 100)) }
        val shown = TransitTrips.forChooser(trips, TransitPlanQuery.ROUTE_BEST, TransitPlanQuery.TIME_NOW)
        assertEquals(TransitTrips.SHOWN, shown.size)
        assertEquals(listOf("L6", "L5", "L4", "L3", "L2"), shown.map { it.steps[0].line!!.name })
        assertEquals(2, TransitTrips.forChooser(trips.take(2), 0, 0).size)
    }

    @Test fun theFixtureIsOffUntilArmed() {
        assertNull(TransitTripsFixture.trips())
        TransitTripsFixture.json = """{"itineraries":[]}"""
        assertEquals(emptyList(), TransitTripsFixture.trips())
    }
}
