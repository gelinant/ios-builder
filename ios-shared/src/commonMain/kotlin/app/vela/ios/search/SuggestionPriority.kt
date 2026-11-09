package app.vela.ios.search

import app.vela.core.model.Place

/**
 * Android's search page order (issue #180): the user's own places lead, the network rows follow,
 * and a place the own data already surfaced never appears twice.
 *
 * The own rows arrive already ordered by the caller (recently viewed, then list places, then the
 * saved shortlist) and are matched on the name or the address, as Android does. Pure so the JVM
 * tests can state the order and the field survival without a UI.
 */
internal object SuggestionPriority {
    /** Android's cap on the rows under the user's own data. */
    const val LOCAL_LIMIT = 6

    /** Google's autocomplete cap, applied after the own rows had their slots. */
    const val NETWORK_LIMIT = 8

    fun matches(term: String, place: Place): Boolean {
        val t = term.trim().lowercase()
        if (t.isEmpty()) return false
        return place.name.lowercase().contains(t) ||
            place.address?.lowercase()?.contains(t) == true
    }

    /** The own rows matching [term], first occurrence of a place winning. */
    fun select(local: List<Place>, term: String): List<Place> {
        val seen = HashSet<String>()
        val out = ArrayList<Place>()
        for (place in local) {
            if (out.size >= LOCAL_LIMIT) break
            if (!matches(term, place)) continue
            if (!seen.add(SearchMerge.placeKey(place))) continue
            out += place
        }
        return out
    }

    /**
     * Own rows first, then the network rows minus any place the own row already names. Matching on
     * both keys, as Android does: the own rows are usually backed by a saved place and carry no
     * feature id, so a feature-id-only comparison would miss them.
     */
    fun merge(local: List<Place>, network: List<Place>, term: String): List<Place> =
        mergeOwn(select(local, term), network)

    /** [merge] with the already selected own rows, so the caller also knows their count. */
    fun mergeOwn(own: List<Place>, network: List<Place>): List<Place> {
        val ownNames = own.map { SearchMerge.nameLocKey(it) }.toHashSet()
        val ownFeatures = own.mapNotNull { it.featureId?.takeUnless(String::isBlank) }.toHashSet()
        val rows = network.filterNot { place ->
            val feature = place.featureId?.takeUnless(String::isBlank)
            SearchMerge.nameLocKey(place) in ownNames || (feature != null && feature in ownFeatures)
        }.take(NETWORK_LIMIT)
        return own + rows
    }
}
