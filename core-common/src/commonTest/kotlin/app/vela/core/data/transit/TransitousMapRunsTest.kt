package app.vela.core.data.transit

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** TRANSIT-INTERP: the ungrouped stretches the map-trips parser keeps for interpolation. */
class TransitousMapRunsTest {
    private val lines = Transitous.parseMapTrips(TransitFixtures.MAP_TRIPS_BERLIN, precision = 5)
    private val runs = Transitous.parseMapTripRuns(TransitFixtures.MAP_TRIPS_BERLIN, precision = 5)

    @Test fun everyAcceptedStretchIsKeptWhole() {
        assertTrue(runs.isNotEmpty())
        assertEquals(lines.sumOf { it.segmentCount }, runs.size, "one run per accepted stretch")
        assertTrue(runs.all { it.path.size >= 2 })
        assertTrue(runs.all { it.fromName.isNotBlank() && it.toName.isNotBlank() })
    }

    @Test fun theLiveStretchKeepsBothTimesAndItsColor() {
        val live = runs.first { it.label == "S7" && it.realTime }
        assertTrue(live.tripId.startsWith("20261028_"), live.tripId)
        assertNotNull(live.departureEpochSec)
        assertNotNull(live.arrivalEpochSec)
        assertEquals(live.departureEpochSec, live.scheduledDepartureEpochSec)
        assertEquals("#816da6", live.colorHex)
        assertTrue(live.fromName.contains("Berlin"), live.fromName)
        assertTrue(live.toName.contains("Berlin"), live.toName)
        assertTrue(live.arrivalEpochSec!! > live.departureEpochSec!!)
    }

    @Test fun aTimetableOnlyStretchIsKeptWithItsFalseFlag() {
        val scheduled = runs.first { !it.realTime }
        assertEquals(false, scheduled.realTime)
        assertTrue(scheduled.departureEpochSec != null)
    }

    @Test fun theCapAppliesToRunsToo() {
        val capped = Transitous.parseMapTripRuns(TransitFixtures.MAP_TRIPS_BERLIN, precision = 5, maxSegments = 3)
        assertEquals(3, capped.size)
    }

    @Test fun aBrokenReplyKeepsNoRun() {
        assertTrue(Transitous.parseMapTripRuns("not json").isEmpty())
    }
}
