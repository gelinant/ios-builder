package app.vela.ios.streetview

import app.vela.core.model.StreetViewPano
import app.vela.core.model.StreetViewTime

/**
 * The capture dates the history chip may show. Google's metadata carries the spot's other
 * captures in [StreetViewPano.history], newest first, and the parser already indexes them by
 * pano id. A pano whose metadata lists no history still has its own capture date, so the viewer
 * shows exactly one chip (the capture on screen) and never invents a list. No date at all means
 * no chip.
 *
 * Kept out of Swift so the filtering, de-duplication and ordering have a JVM test.
 */
object StreetViewHistory {
    fun captures(pano: StreetViewPano?): List<StreetViewTime> {
        if (pano == null) return emptyList()
        val listed = pano.history
            .filter { it.panoId.isNotBlank() && it.year in 1000..9999 && it.month in 1..12 }
            .distinctBy { it.panoId }
            .sortedByDescending { it.year * 100 + it.month }
        if (listed.isNotEmpty()) return listed
        val year = pano.captureYear ?: return emptyList()
        val month = pano.captureMonth ?: return emptyList()
        if (year !in 1000..9999 || month !in 1..12) return emptyList()
        return listOf(StreetViewTime(pano.panoId, year, month))
    }

    /** True when the chip opens a real choice: two or more captures at this spot. */
    fun hasChoices(pano: StreetViewPano?): Boolean = captures(pano).size > 1

    /** The capture on screen, or null when neither the id nor the date is known. */
    fun shown(pano: StreetViewPano?): StreetViewTime? {
        pano ?: return null
        val year = pano.captureYear ?: return null
        val month = pano.captureMonth ?: return null
        if (year !in 1000..9999 || month !in 1..12) return null
        return StreetViewTime(pano.panoId, year, month)
    }
}
