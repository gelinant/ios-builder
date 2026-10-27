package app.vela.ios.streetview

import app.vela.core.model.StreetViewPano
import app.vela.core.model.StreetViewTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The date list the history chip may show: Google's own list, never a fabricated one. */
class StreetViewHistoryTest {
    private fun pano(
        year: Int? = 2025,
        month: Int? = 5,
        history: List<StreetViewTime> = emptyList(),
    ) = StreetViewPano(
        panoId = "panoAAAAAAAAAAAAAAAAAA", lat = 38.5449, lng = -121.7405,
        captureYear = year, captureMonth = month, history = history,
    )

    @Test
    fun `the listed captures are deduplicated and newest first`() {
        val pano = pano(
            history = listOf(
                StreetViewTime("old0000000000000000000A", 2012, 7),
                StreetViewTime("new0000000000000000000A", 2025, 5),
                StreetViewTime("new0000000000000000000A", 2025, 5),
                StreetViewTime("bad0000000000000000000A", 2024, 13),
                StreetViewTime("nodate000000000000000AA", 2024, 0),
            ),
        )
        val dates = StreetViewHistory.captures(pano)
        assertEquals(listOf(2025 to 5, 2012 to 7), dates.map { it.year to it.month })
        assertTrue(StreetViewHistory.hasChoices(pano))
    }

    @Test
    fun `no listed history shows exactly the capture on screen`() {
        val dates = StreetViewHistory.captures(pano(year = 2026, month = 10))
        assertEquals(1, dates.size)
        assertEquals(2026, dates.single().year)
        assertEquals(10, dates.single().month)
        assertEquals("panoAAAAAAAAAAAAAAAAAA", dates.single().panoId)
        assertFalse(StreetViewHistory.hasChoices(pano(year = 2026, month = 10)))
    }

    @Test
    fun `metadata with no date shows nothing`() {
        assertTrue(StreetViewHistory.captures(pano(year = null, month = null)).isEmpty())
        assertTrue(StreetViewHistory.captures(pano(year = 2025, month = null)).isEmpty())
        assertTrue(StreetViewHistory.captures(pano(year = 2025, month = 14)).isEmpty())
        assertTrue(StreetViewHistory.captures(null).isEmpty())
    }

    @Test
    fun `the shown date comes only from the displayed capture`() {
        val shown = StreetViewHistory.shown(pano(year = 2012, month = 7))
        assertEquals(2012, shown?.year)
        assertEquals(7, shown?.month)
        assertEquals(null, StreetViewHistory.shown(pano(year = null, month = null)))
    }
}
