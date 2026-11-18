package app.vela.core.data.transit

import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** `map/trips`, on the reply captured from the public instance on 2026-10-28 at precision 5. */
class TransitousMapTripsTest {
    private val lines = Transitous.parseMapTrips(TransitFixtures.MAP_TRIPS_BERLIN, precision = 5)

    @Test
    fun linesAreGroupedByRouteAndDestination() {
        assertEquals(33, lines.size, "a route in each direction is two groups, as the destination differs")
        assertEquals(44, lines.sumOf { it.segmentCount }, "every captured stretch is on one line")
        assertTrue(lines.all { it.label.isNotBlank() && it.destination != null })
        assertTrue(lines.all { it.paths.isNotEmpty() && it.paths.all { p -> p.size >= 2 } })
        assertTrue(lines.all { it.mode in setOf(TransitMode.BUS, TransitMode.TRAM, TransitMode.SUBWAY, TransitMode.TRAIN, TransitMode.FERRY) })
        // Numeric short names lead, like a station sign.
        assertEquals(listOf("100", "100"), lines.take(2).map { it.label }, "the two directions of route 100 lead")
    }

    @Test
    fun routeColorIsKeptAndNormalized() {
        val flix = lines.first { it.label == "FlixBus 070" }
        assertEquals("#73d700", flix.colorHex)
        assertEquals(TransitMode.BUS, flix.mode)
        assertEquals("Hamburg central bus station", flix.destination)
        // A line the feed gave no color is null here; the UI picks the mode color, not this layer.
        val m4 = lines.first { it.label == "M4" }
        assertNull(m4.colorHex)
        assertEquals(TransitMode.TRAM, m4.mode)
    }

    @Test
    fun delayNeedsARealtimeStretchWithBothTimes() {
        val flix = lines.first { it.label == "FlixBus 070" }
        assertEquals(3, flix.delayMinutes)
        assertTrue(flix.live)
        val s7 = lines.first { it.label == "S7" }
        assertEquals(0, s7.delayMinutes, "a live run on time is a zero delay, not a missing one")
        assertTrue(s7.live)
        // U2 was in the box but not marked realtime: no delay and not live, even with a timetable.
        val u2 = lines.first { it.label == "U2" }
        assertNull(u2.delayMinutes)
        assertTrue(!u2.live)
    }

    @Test
    fun theSegmentCapIsReported() {
        val capped = Transitous.parseMapTrips(TransitFixtures.MAP_TRIPS_BERLIN, precision = 5, maxSegments = 5)
        assertEquals(5, capped.sumOf { it.segmentCount })
        assertTrue(capped.size < lines.size)
    }

    @Test
    fun theUrlCarriesTheBoxTheClockAndThePrecision() {
        val url = Transitous.mapTripsUrl(52.5, 13.3, 52.6, 13.5, 30, 1_792_945_620L, 1_792_949_000L, 9)
        assertTrue(url.startsWith("https://api.transitous.org/api/v1/map/trips?min=52.5,13.3&max=52.6,13.5"))
        assertTrue(url.contains("&zoom=22"), "the zoom is capped at the service's own range")
        assertTrue(url.contains("&startTime=2026-10-25T"))
        assertTrue(url.contains("&precision=6"), "the precision is capped at 6")
    }

    @Test
    fun aChangedReplyIsNoLines() {
        assertTrue(Transitous.parseMapTrips("{\"error\":\"moved\"}").isEmpty())
        assertTrue(Transitous.parseMapTrips("not json").isEmpty())
    }
}
