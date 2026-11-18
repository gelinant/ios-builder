package app.vela.core.data.transit

import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull

/**
 * A recorded Transitous reply for a two-ride trip with a transfer (Paris, Hôtel de Ville to
 * La Défense: Metro 1 at Charles de Gaulle - Étoile, then RER A). The iOS detail sheet must show
 * every leg of it, so the parser's own output is pinned here: five steps, in travel order, each
 * with the mode name and agency the feed sent.
 */
class TransitousParisTransferTest {
    private val json = javaClass.getResourceAsStream("/transitous/plan-paris-transfer.json")!!
        .bufferedReader().readText()

    @Test fun `a transfer reply keeps every leg in travel order`() {
        val trips = Transitous.parsePlan(json, LatLng(48.8566, 2.3522), LatLng(48.8974, 2.2385))
        assertEquals(1, trips.size)
        val trip = trips[0]
        assertEquals(5, trip.steps.size)
        assertEquals(
            listOf(TransitMode.WALK, TransitMode.SUBWAY, TransitMode.WALK, TransitMode.TRAIN, TransitMode.WALK),
            trip.steps.map { it.mode },
        )
        assertEquals(
            listOf("WALK", "SUBWAY", "WALK", "REGIONAL_RAIL", "WALK"),
            trip.steps.map { it.modeName },
        )
        val metro = trip.steps[1]
        assertEquals("1", metro.line!!.name)
        assertEquals("RATP", metro.agencyName)
        assertEquals("Charles de Gaulle - Étoile", metro.alightStop!!.name)
        val transfer = trip.steps[2]
        assertNotNull(transfer.departEpochSec)
        assertEquals(120L, transfer.arriveEpochSec!! - transfer.departEpochSec!!)
        val rer = trip.steps[3]
        assertEquals("A", rer.line!!.name)
        assertEquals("RER", rer.agencyName)
        assertEquals("La Défense", rer.alightStop!!.name)
        // The waiting time between the two rides is the feed's own clocks, not an estimate.
        assertEquals(180L, rer.departEpochSec!! - metro.arriveEpochSec!!)
    }
}
