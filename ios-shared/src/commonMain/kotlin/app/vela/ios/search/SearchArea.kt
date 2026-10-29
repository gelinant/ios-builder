package app.vela.ios.search

import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo

/**
 * "Search this area" (Android's `MapViewModel.searchThisArea` and `AreaNarrow`): the button is
 * offered once the view has really moved, the search runs from the center the user panned to, and
 * the answer is kept to that view with a small margin. When nothing falls inside, the whole answer
 * stands, because an empty list would claim there is nothing there.
 */
internal object SearchArea {
    /**
     * Android arms the button from `onCameraIdle`, which only fires after a user gesture, so a
     * programmatic framing never offers it. iOS reports every camera change through one viewport
     * callback and the search facade has no gesture flag. The port uses Android's own pan step,
     * 22 % of the view (`docs/dpad.md`, `MapDpadController`), as the movement threshold: a smaller
     * change is a framing or a wobble, not a pan.
     */
    const val PAN_FRACTION = 0.22

    /** Android's `AreaNarrow` margin, 10 % of each side. */
    const val PAD = 0.10

    /** Whether [to] is far enough from [from] to be a pan rather than a framing. */
    fun moved(from: DoubleArray?, to: DoubleArray?): Boolean {
        if (from == null || to == null || from.size < 4 || to.size < 4) return false
        val threshold = minSpanMeters(from) * PAN_FRACTION
        if (threshold <= 0.0) return false
        return center(from).distanceTo(center(to)) >= threshold
    }

    /** [places] inside [box] (`south, west, north, east`) plus the margin, else all of them. */
    fun narrow(places: List<Place>, box: DoubleArray?): List<Place> {
        if (box == null || box.size < 4) return places
        val dLat = (box[2] - box[0]) * PAD
        val dLng = (box[3] - box[1]) * PAD
        if (dLat <= 0.0 || dLng <= 0.0) return places
        val inside = places.filter {
            it.location.lat in (box[0] - dLat)..(box[2] + dLat) &&
                it.location.lng in (box[1] - dLng)..(box[3] + dLng)
        }
        return inside.ifEmpty { places }
    }

    internal fun center(box: DoubleArray): LatLng =
        LatLng((box[0] + box[2]) / 2, (box[1] + box[3]) / 2)

    private fun minSpanMeters(box: DoubleArray): Double {
        val lat = LatLng(box[0], box[1]).distanceTo(LatLng(box[2], box[1]))
        val lng = LatLng(box[0], box[1]).distanceTo(LatLng(box[0], box[3]))
        return minOf(lat, lng)
    }
}
