package app.vela.core.data.transit

import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The full-run reader behind the line sheet. The JSON is an extract of a real
 * `GET /api/v1/trip?tripId=20261028_06:31_us-ca-SFMTA_12133263_M11` capture (San Francisco,
 * 2026-10-28), cut to its last two calls so the test keeps the feed's own field names.
 */
class TransitLineClientTest {
    private val reply = """
        {"duration":2220,"startTime":"2026-10-28T13:31:00Z","endTime":"2026-10-28T14:08:00Z","transfers":0,
         "legs":[{"mode":"TRAM","headsign":"Embarcadero Station","realTime":true,"cancelled":false,
          "routeShortName":"K","displayName":"K","routeColor":"437c93","routeTextColor":"ffffff",
          "from":{"name":"Metro Church Station/Downtown","stopId":"us-ca-SFMTA_15726","lat":37.767193,
            "lon":-122.42917,"departure":"2026-10-28T14:00:00Z","scheduledDeparture":"2026-10-28T13:59:00Z",
            "tz":"America/Los_Angeles","stopCode":"15726"},
          "to":{"name":"Metro Van Ness Station","stopId":"us-ca-SFMTA_15419","lat":37.775127,
            "lon":-122.41925,"arrival":"2026-10-28T14:02:00Z","scheduledArrival":"2026-10-28T14:01:00Z",
            "tz":"America/Los_Angeles","stopCode":"15419"},
          "intermediateStops":[]}]}
    """.trimIndent()

    @Test
    fun `trip reply keeps the whole run with the feed times and colour`() {
        val run = assertNotNull(TransitLineClient.parseRun(reply, "trip-1"))
        assertEquals("trip-1", run.tripId)
        assertEquals("K", run.label)
        assertEquals("Embarcadero Station", run.headsign)
        assertEquals(TransitMode.TRAM, run.mode)
        assertEquals("#437c93", run.colorHex)
        assertEquals("#ffffff", run.textColorHex)
        assertTrue(run.realTime)
        assertEquals(2, run.stops.size)
        assertEquals("Metro Church Station/Downtown", run.stops[0].name)
        assertEquals("15726", run.stops[0].code)
        assertEquals("Metro Van Ness Station", run.stops[1].name)
        assertEquals(120L, run.stops[1].expectedEpochSec!! - run.stops[0].expectedEpochSec!!)
        // The live call moved one minute past the timetable, so the sheet can show both.
        assertNotNull(run.stops[0].scheduledText)
        assertNotNull(run.stops[0].clockText)
        assertTrue(run.shape.isEmpty(), "a run with no legGeometry has no shape")
    }

    @Test
    fun `a run with fewer than two stops is not a sequence`() {
        val single = """
            {"legs":[{"mode":"BUS","routeShortName":"7","from":{"name":"Only Stop","lat":1.0,"lon":2.0,
             "departure":"2026-10-28T14:00:00Z"},"to":{"name":"","lat":0.0,"lon":0.0}}]}
        """.trimIndent()
        assertNull(TransitLineClient.parseRun(single, "trip-2"))
        assertNull(TransitLineClient.parseRun("{}", "trip-3"))
        assertNull(TransitLineClient.parseRun("not json", "trip-4"))
    }

    @Test
    fun `only a real six digit colour is kept`() {
        assertEquals("#73d700", TransitLineClient.colorOf("73D700"))
        assertEquals("#73d700", TransitLineClient.colorOf("#73d700"))
        assertNull(TransitLineClient.colorOf("red"))
        assertNull(TransitLineClient.colorOf("73d70"))
        assertNull(TransitLineClient.colorOf(""))
        assertNull(TransitLineClient.colorOf(null))
    }
}
