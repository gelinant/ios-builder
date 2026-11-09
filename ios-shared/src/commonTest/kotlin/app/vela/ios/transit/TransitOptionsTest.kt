package app.vela.ios.transit

import app.vela.core.model.TransitMode
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The options Transitous' `/api/v1/plan` really takes, and the ones it does not. */
class TransitOptionsTest {
    @Test fun vehicleIndicesAreThePlannersFourModes() {
        assertEquals(0, TransitPlanQuery.modeIndex(TransitMode.BUS))
        assertEquals(1, TransitPlanQuery.modeIndex(TransitMode.SUBWAY))
        assertEquals(2, TransitPlanQuery.modeIndex(TransitMode.TRAIN))
        assertEquals(3, TransitPlanQuery.modeIndex(TransitMode.TRAM))
        // No planner mode exists for a boat, a walk or a generic ride: never guessed as a bus.
        assertNull(TransitPlanQuery.modeIndex(TransitMode.FERRY))
        assertNull(TransitPlanQuery.modeIndex(TransitMode.WALK))
        assertNull(TransitPlanQuery.modeIndex(TransitMode.GENERIC))
    }

    @Test fun flagsBecomeTheTransitModesTheEndpointKnows() {
        val busy = TransitPlanQuery.flags(bus = true, subway = false, train = true, tram = true)
        assertEquals(setOf(0, 2, 3), busy)
        assertEquals(listOf("BUS", "RAIL", "TRAM"), TransitPlanQuery.modeNamesFor(busy))
        // An empty selection means every mode, which is also how the UI shows four unset chips.
        assertEquals(emptyList(), TransitPlanQuery.modeNamesFor(emptySet()))
        assertEquals(listOf("BUS", "SUBWAY"), TransitPlanQuery.modeNamesFor(setOf(1, 0)))
    }

    @Test fun timeModesMatchLeaveDepartAndArrive() {
        assertEquals(0, TransitPlanQuery.TIME_NOW)
        assertEquals(1, TransitPlanQuery.TIME_DEPART_AT)
        assertEquals(2, TransitPlanQuery.TIME_ARRIVE_BY)
        val at = 1_800_000_000L
        val depart = TransitPlanQuery(TransitPlanQuery.TIME_DEPART_AT, at, setOf(0)).normalized()
        assertEquals(1, depart.timeMode)
        assertEquals(at, depart.timeEpochSec)
        val arrive = TransitPlanQuery(TransitPlanQuery.TIME_ARRIVE_BY, at).normalized()
        assertEquals(2, arrive.timeMode)
        assertEquals(at, arrive.timeEpochSec)
        // Leave now never carries a clock, and a missing clock falls back to leave now.
        assertEquals(null, TransitPlanQuery(TransitPlanQuery.TIME_NOW, at).normalized().timeEpochSec)
        assertEquals(0, TransitPlanQuery(TransitPlanQuery.TIME_DEPART_AT, null).normalized().timeMode)
        assertEquals(0, TransitPlanQuery(TransitPlanQuery.TIME_DEPART_AT, 0L).normalized().timeMode)
        assertEquals(0, TransitPlanQuery(99, at).normalized().timeMode)
    }

    @Test fun routePreferencesAreOnlyTheSupportedThree() {
        assertTrue(TransitPlanQuery.acceptsRoutePreference(0))
        assertTrue(TransitPlanQuery.acceptsRoutePreference(2))
        assertTrue(TransitPlanQuery.acceptsRoutePreference(3))
        assertFalse(TransitPlanQuery.acceptsRoutePreference(1))
        assertFalse(TransitPlanQuery.acceptsRoutePreference(4))
        assertEquals(
            "time=1 epoch=1800000000 modes=BUS,TRAM pref=2",
            TransitPlanQuery(1, 1_800_000_000L, setOf(0, 3), 2).summary(),
        )
        assertEquals("time=0 epoch=0 modes=all pref=0", TransitPlanQuery().summary())
    }
}
