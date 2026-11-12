package app.vela.core.data.transit

import app.vela.core.model.LatLng
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** `one-to-all`, on the reply captured from the public instance on 2026-10-28. */
class TransitousOneToAllTest {
    @Test
    fun reachableStopsCarryTheRepliesOwnTravelTime() {
        val result = Transitous.parseOneToAll(TransitFixtures.ONE_TO_ALL_BERLIN)!!
        assertEquals(52.52, result.originLat)
        assertEquals(13.405, result.originLon)
        assertEquals(149, result.stops.size, "platforms are kept apart by their own stop id")
        assertTrue(result.stops.all { it.minutes in 0..10 }, "every time is inside the requested budget")
        assertTrue(result.stops.all { it.name.isNotBlank() && it.stopId.isNotBlank() })
        assertTrue(result.stops.all { it.arrivalEpochSec != null }, "the reply sent an arrival for every stop")
        assertEquals(result.stops.sortedBy { it.minutes }, result.stops, "soonest first")
        assertEquals(149, result.stops.map { it.stopId }.distinct().size)
        // Ten minutes is the requested budget, so no stop may claim a longer ride.
        assertTrue(result.stops.maxOf { it.minutes } <= 10)
    }

    @Test
    fun aMissingStopTimeIsNotInvented() {
        val reply = """
          {"one":{"name":"Here","lat":1.0,"lon":2.0,"departure":"2026-10-28T10:00:00Z"},
           "all":[{"place":{"name":"No time","stopId":"a","lat":1.1,"lon":2.1,"vertexType":"TRANSIT"},"duration":4,"k":0}]}
        """.trimIndent()
        val result = Transitous.parseOneToAll(reply)!!
        assertEquals(4, result.stops.single().minutes)
        assertNull(result.stops.single().arrivalEpochSec, "no arrival in the reply, none on the stop")
    }

    @Test
    fun theUrlAsksForTheBudgetAndTheClock() {
        val url = Transitous.oneToAllUrl(LatLng(37.7955, -122.3937), 120, 1_792_945_620L, arriveBy = true)
        assertTrue(url.startsWith("https://api.transitous.org/api/v1/one-to-all?one=37.7955,-122.3937"))
        assertTrue(url.contains("&maxTravelTime=60"), "the budget is capped at 60 minutes")
        assertTrue(url.contains("&time=2026-10-25T"))
        assertTrue(url.contains("&arriveBy=true"))
        val plain = Transitous.oneToAllUrl(LatLng(1.0, 2.0), 2, null, false)
        assertTrue(plain.contains("&maxTravelTime=5"), "the budget is floored at 5 minutes")
        assertTrue(!plain.contains("&time="))
        assertTrue(!plain.contains("arriveBy"))
    }

    @Test
    fun aChangedReplyIsNoReachability() {
        assertNull(Transitous.parseOneToAll("{\"error\":\"moved\"}"))
        assertNull(Transitous.parseOneToAll("not json"))
    }

}
