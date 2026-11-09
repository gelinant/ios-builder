package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo

/**
 * The other Google listings at an open place's address, Android's "Also at this location"
 * (`MapViewModel.othersAt`). It reads the search reply already in hand, so opening a place and
 * its branch list costs no second Google request. Google often omits the siblings; an empty list
 * means nothing is drawn.
 */
object PlaceBranches {
    /** Listings kept at one address, as Android caps the section. */
    const val MAX = 6

    /** Two listings need the same street line and stand within this radius. */
    const val SAME_ADDRESS_M = 60.0

    /** Without an address on either side, only the same footprint counts. */
    const val SAME_FOOTPRINT_M = 15.0

    private val SUITE = Regex("""\s+(ste|suite|unit|apt|apartment|bldg|building|fl|floor|#).*$""")
    private val NON_ALPHANUMERIC = Regex("[^a-z0-9 ]")
    private val SPACES = Regex("\\s+")

    /**
     * The street line of [address], suite-insensitive: "239 G St, Suite 2" and "239 G St" share
     * a key, while a shop across the street does not. Null when the address has no street line.
     */
    fun streetKey(address: String?): String? {
        val line = address?.substringBefore(",")?.lowercase()?.trim()?.takeIf { it.isNotEmpty() }
            ?: return null
        val key = line
            .replace(SUITE, "")
            .replace(NON_ALPHANUMERIC, " ")
            .replace(SPACES, " ")
            .trim()
        return key.ifEmpty { null }
    }

    /**
     * [candidates] that sit at [selected]'s address: the same street line within
     * [SAME_ADDRESS_M], or the same footprint within [SAME_FOOTPRINT_M] when an address is
     * missing. The selected place itself is dropped by feature id, else by name. Caps at [MAX]
     * and keeps the candidates' order.
     */
    fun companions(selected: Place, candidates: List<Place>): List<Place> {
        val key = streetKey(selected.address)
        return candidates.filter { candidate ->
            val notSelf =
                if (candidate.featureId != null && selected.featureId != null) {
                    candidate.featureId != selected.featureId
                } else {
                    candidate.name != selected.name
                }
            if (!notSelf) return@filter false
            val candidateKey = streetKey(candidate.address)
            val distance = candidate.location.distanceTo(selected.location)
            if (key != null && candidateKey != null) {
                candidateKey == key && distance < SAME_ADDRESS_M
            } else {
                distance < SAME_FOOTPRINT_M
            }
        }.take(MAX)
    }

    /**
     * A fixed group for the simulator scenario: one shop and three neighbors at the same Davis
     * address. It never reaches Google; the UI test only opens it through the debug launch
     * argument, and the production path reads the search reply instead.
     */
    fun fixture(): List<Place> = listOf(
        Place(
            id = "fixture:market-hall",
            name = "Market Hall",
            location = LatLng(38.5449, -121.7405),
            category = "Cafe",
            address = "123 G St, Davis, CA 95616",
            rating = 4.5,
            reviewCount = 210,
            openNow = true,
            featureId = "0x809ad6:0x1",
        ),
        Place(
            id = "fixture:market-hall-bakery",
            name = "Market Hall Bakery",
            location = LatLng(38.54491, -121.74051),
            category = "Bakery",
            address = "123 G St, Davis, CA 95616",
            rating = 4.7,
            reviewCount = 88,
            openNow = true,
            featureId = "0x809ad6:0x2",
        ),
        Place(
            id = "fixture:market-hall-kitchen",
            name = "Market Hall Kitchen",
            location = LatLng(38.54492, -121.74052),
            category = "Restaurant",
            address = "123 G St, Davis, CA 95616",
            rating = 4.3,
            reviewCount = 145,
            openNow = false,
            featureId = "0x809ad6:0x3",
        ),
        Place(
            id = "fixture:market-hall-wine",
            name = "Market Hall Wine",
            location = LatLng(38.54493, -121.74053),
            category = "Wine bar",
            address = "123 G St, Davis, CA 95616",
            rating = 4.6,
            reviewCount = 54,
            openNow = true,
            featureId = "0x809ad6:0x4",
        ),
    )
}
