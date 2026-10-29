package app.vela.ios.search

import app.vela.core.data.OfflineAddressStore
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo

/** A merged list plus how many duplicate rows the merge collapsed into the one already shown. */
internal data class MergeOutcome(val places: List<Place>, val dropped: Int)

/** Pure Android-compatible address ranking and stable online/offline place merging. */
internal object SearchMerge {
    private const val SAME_PLACE_M = 60.0
    private const val SAME_ADDRESS_M = 120.0
    private val NON_WORD = Regex("""[^\p{L}\p{N}]+""")

    /**
     * Merges one Google answer, its address geocoder rows and installed rows. Google keeps its
     * order except that rows carrying a typed address lead, ranked by street score then distance.
     * Online listings win duplicates, while missing display fields are filled from installed data.
     */
    fun merge(
        online: List<Place>,
        local: List<Place>,
        query: String?,
        near: LatLng?,
        photon: List<Place>,
    ): List<Place> = mergeCounted(online, local, query, near, photon).places

    /** [merge], also reporting the duplicates it dropped so the result header can count them. */
    internal fun mergeCounted(
        online: List<Place>,
        local: List<Place>,
        query: String?,
        near: LatLng?,
        photon: List<Place>,
    ): MergeOutcome {
        if (query == null || AddressQuery.parse(query) == null) {
            return deduplicate(online.map { Candidate(it, online = true) } + local.map { Candidate(it, online = false) })
        }

        // Android's address geocoder contributes only rows that actually carry the typed house
        // number and street. Other Photon matches must not become an unrelated result section.
        val geocoded = photon.filter { carries(query, it) }
        val networkMerge = deduplicate(
            (geocoded + online).map { Candidate(it, online = true) },
        )
        val network = networkMerge.places
        val localAddresses = local.filter(::isAddressRow)
        val localPlaces = local.filterNot(::isAddressRow)
        // Android drops a local house already covered by a network row. Give that network row the
        // local street line or locality first, including when the online row is a named business.
        val enrichedNetwork = network.map { place ->
            val donor = localAddresses.firstOrNull { address ->
                !OfflineAddressStore.isApproximate(address) && carries(query, place) &&
                    place.location.distanceTo(address.location) < SAME_ADDRESS_M
            }
            if (donor == null) place else enrich(place, donor)
        }
        val keptAddresses = localAddresses.filter { address ->
            if (OfflineAddressStore.isApproximate(address)) {
                network.none { carries(query, it) }
            } else {
                network.none {
                    carries(query, it) && it.location.distanceTo(address.location) < SAME_ADDRESS_M
                }
            }
        }
        val rankedNetwork = addressFirst(query, enrichedNetwork, near)
        val merged = deduplicate(
            keptAddresses.map { Candidate(it, online = false) } +
                rankedNetwork.map { Candidate(it, online = true) } +
                localPlaces.map { Candidate(it, online = false) },
        )
        return MergeOutcome(merged.places, networkMerge.dropped + merged.dropped)
    }

    /** "More results": the next pages appended without repeating a place already on screen. */
    internal fun append(existing: List<Place>, extra: List<Place>): List<Place> =
        appendCounted(existing, extra).places

    /** [append], also reporting how many of [extra] were already on screen. */
    internal fun appendCounted(existing: List<Place>, extra: List<Place>): MergeOutcome =
        deduplicate(existing.map { Candidate(it, online = true) } + extra.map { Candidate(it, online = true) })

    /** Android's addressFirst, with the query explicit rather than held in hidden view-model state. */
    private fun addressFirst(query: String, places: List<Place>, near: LatLng?): List<Place> {
        val (hits, rest) = places.partition { carries(query, it) }
        if (hits.size < 2) return hits + rest
        return hits.sortedWith(
            compareByDescending<Place> { AddressQuery.score(query, it.name, it.address) }
                .thenBy { if (near == null) 0.0 else it.location.distanceTo(near) },
        ) + rest
    }

    private fun carries(query: String, place: Place): Boolean =
        AddressQuery.matches(query, place.name, place.address)

    private fun isAddressRow(place: Place): Boolean =
        place.category.equals("Address", ignoreCase = true) || OfflineAddressStore.isApproximate(place)

    private data class Candidate(val place: Place, val online: Boolean)

    /** Collapses duplicates inside every source as well as across sources, preserving list order. */
    private fun deduplicate(candidates: List<Candidate>): MergeOutcome {
        val out = ArrayList<Candidate>(candidates.size)
        for (candidate in candidates) {
            val index = out.indexOfFirst { samePlace(it.place, candidate.place) }
            if (index < 0) {
                out += candidate
                continue
            }
            val previous = out[index]
            val winner = if (!previous.online && candidate.online) candidate.place else previous.place
            val fallback = if (winner === candidate.place) previous.place else candidate.place
            out[index] = Candidate(enrich(winner, fallback), online = previous.online || candidate.online)
        }
        return MergeOutcome(out.map { it.place }, candidates.size - out.size)
    }

    /** The preferred row keeps its identity and ranking; installed data only fills missing fields. */
    private fun enrich(winner: Place, fallback: Place): Place = winner.copy(
        name = winner.name.ifBlank { fallback.name },
        category = winner.category?.takeUnless { it.isBlank() } ?: fallback.category,
        address = winner.address?.takeUnless { it.isBlank() } ?: fallback.address,
    )

    /** Stable id, then Google feature id, then normalized name at the same physical place. */
    internal fun samePlace(a: Place, b: Place): Boolean {
        val aId = a.id.trim()
        val bId = b.id.trim()
        if (aId.isNotEmpty() && bId.isNotEmpty() && aId == bId) return true
        val aFeature = a.featureId?.trim().orEmpty()
        val bFeature = b.featureId?.trim().orEmpty()
        if (aFeature.isNotEmpty() && bFeature.isNotEmpty() && aFeature == bFeature) return true
        val aName = normalizedName(a.name)
        val bName = normalizedName(b.name)
        return aName.isNotEmpty() && aName == bName && a.location.distanceTo(b.location) < SAME_PLACE_M
    }

    /** Feature-id-independent key from Android, with punctuation and whitespace folded as well. */
    internal fun nameLocKey(place: Place): String =
        "${normalizedName(place.name)}|${(place.location.lat * 2e4).toInt()},${(place.location.lng * 2e4).toInt()}"

    internal fun placeKey(place: Place): String = place.featureId?.takeUnless { it.isBlank() } ?: nameLocKey(place)

    private fun normalizedName(value: String): String = value.lowercase().replace(NON_WORD, " ").trim()
}
