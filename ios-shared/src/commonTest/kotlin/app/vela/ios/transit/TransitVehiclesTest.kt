package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The interpolation of TRANSIT-INTERP, on hand-written stretches shaped like the captured
 * `map/trips` extract: `from` and `to` with both times, `realTime` and a polyline. The feed has
 * no vehicle coordinate, so these cases pin the estimate, not a measured point.
 */
class TransitVehiclesTest {
    private val a = LatLng(37.0000, -122.0000)
    private val b = LatLng(37.0000, -121.9990)
    private val c = LatLng(37.0000, -121.9980)

    private fun run(
        departure: Long? = 1_000L,
        arrival: Long? = 1_060L,
        scheduledDeparture: Long? = 1_000L,
        scheduledArrival: Long? = 1_060L,
        realTime: Boolean = true,
        path: List<LatLng> = listOf(a, b),
        from: LatLng = a,
        to: LatLng = b,
        tripId: String = "trip-1",
        label: String = "9",
    ) = Transitous.MapTripRun(
        tripId = tripId,
        label = label,
        mode = TransitMode.BUS,
        colorHex = "#73d700",
        from = from,
        fromName = "From stop",
        to = to,
        toName = "Next stop",
        departureEpochSec = departure,
        arrivalEpochSec = arrival,
        scheduledDepartureEpochSec = scheduledDeparture,
        scheduledArrivalEpochSec = scheduledArrival,
        realTime = realTime,
        path = path,
    )

    @Test fun midSegmentInterpolatesOnTheClock() {
        val marker = TransitVehicles.markers(listOf(run()), 1_030L).single()
        assertEquals(0.5, marker.fraction, 0.0001)
        assertEquals(37.0, marker.lat, 1e-9)
        assertEquals(-121.9995, marker.lng, 1e-9)
        assertEquals("9", marker.label)
        assertEquals("BUS", marker.mode)
        assertEquals("#73d700", marker.colorHex)
        assertEquals("Next stop", marker.nextStopName)
        assertEquals("Next stop", marker.headsign)
        // An estimate is always published as one.
        assertTrue(marker.estimated)
        assertEquals(0, marker.delayMinutes)
    }

    @Test fun aTerminusStopOfTheStretchMarksTheDelay() {
        val late = run(departure = 1_120L, arrival = 1_180L)
        val marker = TransitVehicles.markers(listOf(late), 1_150L).single()
        assertEquals(2, marker.delayMinutes)
    }

    @Test fun beforeDepartureThereIsNoMarker() {
        assertTrue(TransitVehicles.markers(listOf(run()), 940L).isEmpty())
        assertNull(TransitVehicles.fractionAt(1_000L, 1_060L, 999L))
    }

    @Test fun afterArrivalThereIsNoMarker() {
        assertTrue(TransitVehicles.markers(listOf(run()), 1_060L + 1).isEmpty())
        assertNull(TransitVehicles.fractionAt(1_000L, 1_060L, 1_061L))
    }

    @Test fun aStretchWithoutRealTimeYieldsNoMarker() {
        // Both times are present, but the feed did not mark them realtime.
        assertTrue(TransitVehicles.markers(listOf(run(realTime = false)), 1_030L).isEmpty())
    }

    @Test fun aStopWithoutATimeYieldsNoMarker() {
        assertTrue(TransitVehicles.markers(listOf(run(departure = null)), 1_030L).isEmpty())
        assertTrue(TransitVehicles.markers(listOf(run(arrival = null, scheduledArrival = null)), 1_030L).isEmpty())
    }

    @Test fun aMissingLiveArrivalUsesTheScheduledOneShiftedByTheDelay() {
        val run = run(
            departure = 1_060L, arrival = null,
            scheduledDeparture = 1_000L, scheduledArrival = 1_060L)
        val destination = TransitVehicles.destinationOf(run)
        assertNotNull(destination)
        assertEquals(1_120L, destination)
        assertEquals(0.5, TransitVehicles.fractionAt(1_060L, destination, 1_090L)!!, 0.0001)
    }

    @Test fun theVertexHopWalksOnlyBetweenTheTwoStopVertices() {
        // The drawn stretch starts before the from stop and ends after the next one.
        val before = LatLng(37.0200, -122.0200)
        val after = LatLng(37.0200, -121.9800)
        val path = listOf(before, a, b, after)
        val marker = TransitVehicles.markers(listOf(run(path = path)), 1_030L).single()
        assertEquals(0.5, marker.fraction, 0.0001)
        assertEquals(-121.9995, marker.lng, 1e-9, "the extra vertices must not stretch the hop")
        assertEquals(37.0, marker.lat, 1e-9)
    }

    @Test fun aReversedPolylineIsWalkedFromTheFromStop() {
        // The drawn path runs from the next stop back to the from stop; the walk still starts
        // at the stop the vehicle left.
        val path = listOf(b, a)
        val marker = TransitVehicles.markers(listOf(run(path = path, from = b, to = a)), 1_030L).single()
        assertEquals(37.0, marker.lat, 1e-9)
        assertEquals(-121.9995, marker.lng, 1e-9)
        assertTrue(marker.bearing in 240.0..300.0, "the glyph must point west, not east: ${marker.bearing}")
    }

    @Test fun aDegenerateVertexHopFallsBackToAStraightLine() {
        val path = listOf(a, a, b)
        val marker = TransitVehicles.markers(listOf(run(path = path)), 1_030L).single()
        assertEquals(-121.9995, marker.lng, 1e-9)
    }

    @Test fun oneTripGetsOneMarkerAtTheCurrentStretch() {
        val first = run(arrival = 1_060L)
        val second = run(departure = 1_060L, arrival = 1_120L, tripId = "trip-1")
        val markers = TransitVehicles.markers(listOf(first, second), 1_061L)
        assertEquals(1, markers.size)
        assertEquals(1_120L, markers.single().destinationEpochSec)
    }

    @Test fun thePointMayStartAndEndOnTheTwoStops() {
        val start = TransitVehicles.markers(listOf(run()), 1_000L).single()
        assertEquals(a.lat, start.lat, 1e-9)
        assertEquals(a.lng, start.lng, 1e-9)
        val end = TransitVehicles.markers(listOf(run()), 1_060L).single()
        assertEquals(b.lng, end.lng, 1e-9)
    }
}
