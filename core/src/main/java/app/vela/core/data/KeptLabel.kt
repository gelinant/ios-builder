package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo
import app.vela.core.util.PlaceNames

/** How far from a kept map label its listing may be: the saved-place rule's own reach. */
const val KEPT_LABEL_MAX_M = 250.0

/**
 * The listing among [listings] of a place kept from the map label [name] at [at], or null. What
 * is taken is written back to the saved place and the lists, so the test is strict: the names
 * agree, it is within [KEPT_LABEL_MAX_M], it is open and has a feature id, and its house number
 * is not another one than [address]'s. A listing named exactly as kept leads, then the nearest.
 * The caller passes listings only (no bare addresses, no transit stops or junctions).
 */
fun keptLabelListing(name: String, at: LatLng, address: String?, listings: List<Place>): Place? {
    val house = PlaceNames.houseNumber(address)
    val near = listings.filter { p ->
        !p.featureId.isNullOrBlank() && !p.permanentlyClosed && p.location.distanceTo(at) <= KEPT_LABEL_MAX_M &&
            PlaceNames.agree(name, p.name, PlaceNames.cityWords(p.address)) &&
            (house == null || PlaceNames.houseNumber(p.address).let { it == null || it == house })
    }
    return near.filter { PlaceNames.same(name, it.name) }.ifEmpty { near }.minByOrNull { it.location.distanceTo(at) }
}
