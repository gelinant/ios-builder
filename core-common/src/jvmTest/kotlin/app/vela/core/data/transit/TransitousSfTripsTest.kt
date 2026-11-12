package app.vela.core.data.transit

import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * A recorded Transitous reply with several itineraries (San Francisco, 24th Street / Mission to
 * the Ferry Building, asked with `numItineraries=5`). The iOS chooser lists every one of them, so
 * the parser must keep them all, with the agency colors and the real-time flag of each ride.
 */
class TransitousSfTripsTest {
    private val json = javaClass.getResourceAsStream("/transitous/plan-sf-trips.json")!!
        .bufferedReader().readText()
    private val trips = Transitous.parsePlan(json, LatLng(37.7522, -122.4184), LatLng(37.7955, -122.3937))

    @Test fun `every itinerary of the reply is kept in the planner's order`() {
        assertEquals(6, trips.size)
        assertEquals(
            listOf("14R", "Green-N", "14", "Yellow-N", "14R", "Blue-N"),
            trips.map { t -> t.steps.first { it.line != null }.line!!.name },
        )
        assertEquals(listOf(1, 2, 1, 2, 1, 2), trips.map { t -> t.steps.count { it.line != null } })
    }

    @Test fun `rides keep the agency colors and the real-time flag`() {
        val yellow = trips[3].steps[1]
        assertEquals(TransitMode.SUBWAY, yellow.mode)
        assertEquals("#ffff33", yellow.line!!.colorHex)
        assertEquals("#000000", yellow.line!!.textColorHex)
        assertFalse(yellow.realTime)
        val bus = trips[3].steps[3]
        assertEquals("#bf2b45", bus.line!!.colorHex)
        assertTrue(bus.realTime)
        // Walks are never real-time, whatever the feed did for the rides around them.
        assertTrue(trips.flatMap { it.steps }.filter { it.line == null }.none { it.realTime })
        // The cable car keeps its raw mode name; the coarse mode does not guess a vehicle.
        val cable = trips[1].steps[3]
        assertEquals("FUNICULAR", cable.modeName)
        assertEquals(TransitMode.GENERIC, cable.mode)
    }
}
