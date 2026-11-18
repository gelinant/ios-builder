package app.vela.ios.place

import app.vela.core.data.FuelGb
import app.vela.core.model.LatLng
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.datetime.Instant

/** The two travel seams PLC-FUEL hands to the route and navigation stores. */
class PlaceTravelHintsTest {
    private val now = 1_791_460_000L
    private val csv = """
        brand,lat,lng,e10,e5,b7s,b7p,updated
        ESSO,51.5075,-0.1278,172.9,,199.9,,1791454066
        TESCO,51.5076,-0.1279,169.9,,189.9,,1791454066
    """.trimIndent()
    private val data = FuelGb.parse(csv)
    private val route = listOf(LatLng(51.5070, -0.1278), LatLng(51.5080, -0.1278))

    @Test fun detourFindsTheCheapestForecourtOnTheLine() {
        val hint = PlaceTravelHints.fuelDetour(route, data, now)
        assertNotNull(hint)
        assertEquals("TESCO", hint.brand)
        assertEquals("169.9p/E10 · 189.9p/B7", hint.price)
        assertTrue(hint.offRouteMeters < 50.0)
    }

    @Test fun detourIgnoresFarStationsAndStaleFiles() {
        val far = FuelGb.parse("brand,lat,lng,e10,updated\nESSO,51.6000,-0.1278,160.0,1791454066\n")
        assertNull(PlaceTravelHints.fuelDetour(route, far, now))
        assertNull(PlaceTravelHints.fuelDetour(route, data, data.newestReport + 3 * 86_400))
        assertNull(PlaceTravelHints.fuelDetour(emptyList(), data, now))
    }

    @Test fun closingWarningUsesTheNavigationWindow() {
        val t = Instant.parse("2026-10-05T16:00:00Z").epochSeconds
        val soon = PlaceTravelHints.closingWarning("Co-op", "Open · Closes 5 PM", 1, t + 1_800, t, "UTC")
        assertNotNull(soon)
        assertEquals(17 * 60, soon.closesAtMinuteOfDay)
        assertNull(PlaceTravelHints.closingWarning("Co-op", "Open · Closes 5 PM", 1, t, t, "UTC"))
    }

    @Test fun closingWarningCrossesMidnight() {
        val t = Instant.parse("2026-10-05T23:30:00Z").epochSeconds
        val w = PlaceTravelHints.closingWarning("Diner", "Open ⋅ Closes 1 AM", 1, t + 2_700, t, "UTC")
        assertNotNull(w)
        assertEquals(60, w.closesAtMinuteOfDay)
        assertTrue(!w.beforeArrival)
    }
}
