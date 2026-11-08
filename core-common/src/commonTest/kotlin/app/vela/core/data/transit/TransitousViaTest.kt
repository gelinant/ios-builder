package app.vela.core.data.transit

import app.vela.core.model.LatLng
import app.vela.core.platform.NormalForm
import app.vela.core.platform.TextNormalizer
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A `via` stop resolved by name, and the plan that carries its id; captured 2026-10-28. */
class TransitousViaTest {
    private val text = object : TextNormalizer {
        override fun normalize(text: String, form: NormalForm) = text
    }

    private val stops = Json { ignoreUnknownKeys = true }
        .decodeFromString<List<Transitous.MapStop>>(TransitFixtures.MAP_STOPS_ALEXANDERPLATZ)

    @Test
    fun aStopIsMatchedByNameBeforeAnyPlan() {
        val match = Transitous.pickStopByName(
            stops, "S+U Alexanderplatz Bhf (Berlin)", text, 52.5219, 13.4132)
        // The stop of that name nearest the coordinate the current trip gave; the station has
        // several platforms, so the id is asserted by its feed prefix, not by one platform.
        assertTrue(match?.stopId?.startsWith("de-") == true)
        assertEquals("S+U Alexanderplatz Bhf (Berlin)", match?.name)
        // A stop the lookup does not list is not replaced by a guess at the nearest other stop.
        assertNull(Transitous.pickStopByName(stops, "Nowhere Square", text, 52.5219, 13.4132))
        // Case, street type and order do not matter, as for a board's stop key.
        assertEquals(
            match?.stopId,
            Transitous.pickStopByName(stops, "s+u alexanderplatz bhf (berlin)", text, 52.5219, 13.4132)?.stopId)
    }

    @Test
    fun theViaGoesOnTheWireAsAStopIdOnly() {
        val url = Transitous.planViaUrl(
            LatLng(52.503, 13.469), LatLng(52.5251, 13.3694),
            "de-DELFI_de:11000:900100708", 1, 1_792_945_620L, setOf(2))
        assertTrue(url.contains("&via=de-DELFI_de%3A11000%3A900100708"), url)
        assertTrue(url.contains("&time=2026-10-25T"))
        assertTrue(url.contains("&transitModes=RAIL"))
        assertTrue(!url.contains("arriveBy"))
    }

    @Test
    fun thePlannerHonoursTheViaStop() {
        val origin = LatLng(52.503, 13.469)
        val destination = LatLng(52.5251, 13.3694)
        val trips = Transitous.parsePlan(TransitFixtures.PLAN_VIA_ALEXANDERPLATZ, origin, destination)
        assertEquals(3, trips.size)
        val stopsThroughAlexanderplatz = trips.flatMap { trip ->
            trip.steps.flatMap { step ->
                (listOfNotNull(step.boardStop, step.alightStop) + step.intermediateStops)
                    .filter { it.name.contains("Alexanderplatz") }
            }
        }
        assertTrue(stopsThroughAlexanderplatz.isNotEmpty(), "the via stop is on the returned legs")
        assertTrue(stopsThroughAlexanderplatz.all { it.stopId != null }, "the stop id is kept for a next via")
    }
}
