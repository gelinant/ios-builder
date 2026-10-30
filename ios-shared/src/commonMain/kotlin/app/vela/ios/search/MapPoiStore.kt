package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.OfflineRank
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo
import app.vela.ios.privacy.GoogleUses
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the tap lookup decided: the same listing, a listing whose name merely agrees, or nothing. */
internal enum class MatchQuality { EXACT, NEAR }

/** The Google listing a tap resolved to, with how sure the name and point make it. */
internal data class MapPoiMatch(val place: Place, val quality: MatchQuality) {
    val label: String get() = when (quality) {
        MatchQuality.EXACT -> "exact"
        MatchQuality.NEAR -> "near"
    }
}

/**
 * A basemap label being resolved, or a dropped pin that stays on the open map data alone.
 *
 * [match] is the reported decision: `none` while idle or resolving, `exact` or `near` when a
 * Google listing opens, `fallback` when the label's own OpenStreetMap data is shown instead.
 * [selected] is only set for the fallback (and a dropped pin); a Google match opens through
 * [MapPoiStore]'s `onOpen` callback and leaves it null, so the place sheet takes over.
 */
data class MapPoiState(
    val selected: Place? = null,
    val resolving: Boolean = false,
    val googleUnavailable: Boolean = false,
    val droppedPin: Boolean = false,
    val match: String = "none",
    /** "Search Google for this place" found no listing with an agreeing name. */
    val googleSearchFoundNothing: Boolean = false,
    /** Google may be asked about this place: not NoGoogle and not switched off in settings. */
    val googleSearchable: Boolean = false,
)

/**
 * Opens the Google listing for a named Liberty POI with one focused search. A miss, or a reply
 * whose name and point do not agree with the tapped label, keeps the label's own OpenStreetMap
 * data instead of adopting a nearby stranger. Also owns long-press reverse geocoding.
 * The constructor is inert; every intent runs on the session's main scope after [start].
 */
class MapPoiStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
    private val onOpen: (Place) -> Unit,
) {
    private val _state = MutableStateFlow(MapPoiState())
    val state: StateFlow<MapPoiState> = _state.asStateFlow()

    private var started = false
    private var job: Job? = null
    private var generation = 0

    fun start() {
        started = true
    }

    /**
     * Resolves a tapped basemap label. [from] is the user's last fix when the app has one; it only
     * fills the fallback sheet's distance, and the lookup itself uses the tapped point.
     */
    fun tap(name: String, lat: Double, lng: Double, kind: String?, from: LatLng? = null) {
        if (!started || name.isBlank() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        val at = LatLng(lat, lng)
        val searchable = GoogleUses.lookupTappedPlaces && !NoGoogle.enabled
        val placeholder = placeholder(name, at, kind, from)
        beginTap(placeholder, searchable)
        if (!searchable) {
            // NoGoogle, or "Look up tapped places on Google" off: the tap keeps Vela's own row and
            // no request leaves the phone (SET-PRIVACY).
            _state.value = fallbackState(placeholder, searchable)
            return
        }
        val query = searchQuery(name, kind)
        val gen = generation
        job = scope.launch {
            val results = try {
                source().searchOnce(query, at)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                emptyList()
            }
            if (gen != generation) return@launch
            finishTap(placeholder, at, name, kind, results, searchable)
        }
    }

    /** The "Search Google for this place" button: runs the label's name and point explicitly. */
    fun searchGoogle() {
        val current = _state.value
        val p = current.selected ?: return
        if (!started || !current.googleSearchable) return
        job?.cancel()
        val gen = ++generation
        val at = p.location
        val kind = p.category
        _state.update { it.copy(resolving = true, googleSearchFoundNothing = false) }
        job = scope.launch {
            val results = try {
                source().searchOnce(searchQuery(p.name, kind), at)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                emptyList()
            }
            if (gen != generation) return@launch
            val found = bestMatch(p.name, at, kind, results)
            if (found == null) {
                _state.update {
                    it.copy(resolving = false, googleSearchFoundNothing = true,
                        googleUnavailable = true, match = "fallback")
                }
            } else {
                _state.value = MapPoiState(match = found.label, googleSearchable = true)
                onOpen(found.place)
            }
        }
    }

    /**
     * UI scenario only: resolves a fixed answer set through the same decision as [tap], so the
     * sheet is tested without a network request. Production launches never call it.
     */
    fun tapFixture(scenario: String) {
        if (!started) return
        val at = LatLng(37.7955, -122.3937)
        val me = LatLng(37.7950, -122.3937)
        when (scenario) {
            "exact" -> resolveFixed(
                name = "Ferry Building", at = at, kind = "marketplace", from = me,
                answers = listOf(
                    Place(
                        id = "fixture:exact", name = "Ferry Building", location = at,
                        category = "Marketplace", address = "1 Ferry Building, San Francisco"),
                ),
            )
            "fallback" -> resolveFixed(
                name = "Vela Test Cafe", at = at, kind = "cafe", from = me,
                answers = listOf(
                    Place(
                        id = "fixture:far", name = "Somewhere Else",
                        location = LatLng(37.8055, -122.4137), category = "Restaurant"),
                ),
            )
        }
    }

    private fun resolveFixed(
        name: String,
        at: LatLng,
        kind: String?,
        from: LatLng?,
        answers: List<Place>,
    ) {
        val placeholder = placeholder(name, at, kind, from)
        beginTap(placeholder, searchable = true)
        finishTap(placeholder, at, name, kind, answers, searchable = true)
    }

    /** Drops a pin immediately, then lets the common Nominatim path supply its address. */
    fun longPress(lat: Double, lng: Double) {
        if (!started || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        job?.cancel()
        val gen = ++generation
        val at = LatLng(lat, lng)
        val pin = Place(id = "pin:$lat,$lng", name = "Dropped pin", location = at)
        _state.value = MapPoiState(selected = pin, resolving = true, droppedPin = true)
        job = scope.launch {
            val geocoded = try {
                source().reverseGeocode(at)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            if (gen != generation) return@launch
            val selected = geocoded?.copy(id = pin.id, location = at) ?: pin
            _state.value = MapPoiState(selected = selected, droppedPin = true)
        }
    }

    fun close() {
        job?.cancel()
        job = null
        generation++
        _state.value = MapPoiState()
    }

    private fun beginTap(placeholder: Place, searchable: Boolean) {
        job?.cancel()
        generation++
        _state.value = MapPoiState(
            selected = placeholder,
            resolving = searchable,
            googleSearchable = searchable,
        )
    }

    private fun finishTap(
        placeholder: Place,
        at: LatLng,
        name: String,
        kind: String?,
        results: List<Place>,
        searchable: Boolean,
    ) {
        val found = bestMatch(name, at, kind, results)
        if (found == null) {
            _state.value = fallbackState(placeholder, searchable)
        } else {
            // The Google sheet opens through the place store; keep only the decision for the
            // debug line, so the map POI card does not sit under it.
            _state.value = MapPoiState(match = found.label, googleSearchable = searchable)
            onOpen(found.place)
        }
    }

    private fun placeholder(name: String, at: LatLng, kind: String?, from: LatLng?) =
        Place(
            id = "poi:${at.lat},${at.lng}",
            name = name,
            location = at,
            category = kind,
            distanceMeters = from?.distanceTo(at),
        )

    private fun fallbackState(placeholder: Place, searchable: Boolean) = MapPoiState(
        selected = placeholder,
        googleUnavailable = true,
        match = "fallback",
        googleSearchable = searchable,
    )

    private fun searchQuery(name: String, kind: String?): String {
        val hint = transitHint(kind)
        return if (hint != null && !name.lowercase().contains(hint)) "$name $hint" else name
    }

    companion object {
        /** The farthest a reply may sit from the tap and still be called the same business. */
        internal const val BUSINESS_TAP_CAP_M = 1_500.0
        internal const val TRANSIT_TAP_CAP_M = 250.0
        internal const val SETTLEMENT_TAP_CAP_M = 30_000.0

        private val SETTLEMENT_KINDS = setOf("city", "town", "village", "hamlet", "suburb", "locality")
        private val JUNCTION_CATEGORIES = setOf("intersection", "junction", "crossroads", "road", "highway")
        private val GENERIC_WORDS = setOf(
            "the", "and", "of", "at", "in", "on", "a", "an", "for", "by", "with", "to",
            "store", "shop", "station", "center", "centre", "services", "service", "company",
            "branch", "restaurant", "cafe", "coffee", "market", "grocery", "hotel", "building",
            "downtown", "plaza", "mall", "food", "express", "marketplace", "official",
        )
        private val NON_TRANSIT_WORDS = listOf(
            "gas", "fuel", "petrol", "fire", "police", "hospital", "parking", "restaurant",
            "cafe", "coffee", "shop", "store", "hotel", "charging", "service station",
        )

        /**
         * Android's safe part of `onPoiTap`: the tapped name must agree with the reply's, and the
         * reply must sit under the kind's distance cap. The same name wins over a nearer one;
         * otherwise the looser word agreement decides. Nothing agreeing means no Google sheet at
         * all, never a different business that merely shares the corner.
         */
        internal fun bestMatch(name: String, at: LatLng, kind: String?, results: List<Place>): MapPoiMatch? {
            if (name.isBlank()) return null
            val live = results.filterNot { it.permanentlyClosed }.ifEmpty { results }
            val hint = transitHint(kind)
            if (hint != null) {
                return live.filter {
                    isTransit(it.category) && it.location.distanceTo(at) <= TRANSIT_TAP_CAP_M &&
                        nameAgrees(name, it.name)
                }.minByOrNull { it.location.distanceTo(at) }
                    ?.let { MapPoiMatch(it, quality(name, it.name)) }
            }
            val answerable = live.filter {
                it.name.isNotBlank() && !isTransit(it.category) &&
                    !JUNCTION_CATEGORIES.any { category -> category == it.category?.lowercase() }
            }
            val cap = if (kind?.lowercase() in SETTLEMENT_KINDS) SETTLEMENT_TAP_CAP_M else BUSINESS_TAP_CAP_M
            val agreeing = answerable.filter {
                it.location.distanceTo(at) <= cap && nameAgrees(name, it.name)
            }
            if (agreeing.isEmpty()) return null
            val sameName = agreeing.filter { normalized(name) == normalized(it.name) }
            val pick = (sameName.ifEmpty { agreeing }).minByOrNull { it.location.distanceTo(at) } ?: return null
            return MapPoiMatch(pick, quality(name, pick.name))
        }

        private fun quality(tapped: String, reply: String): MatchQuality =
            if (normalized(tapped) == normalized(reply)) MatchQuality.EXACT else MatchQuality.NEAR

        internal fun nameAgrees(a: String, b: String): Boolean {
            val na = normalized(a)
            val nb = normalized(b)
            if (na.isEmpty() || nb.isEmpty()) return false
            if (na == nb) return true
            val da = identityWords(na)
            val db = identityWords(nb)
            if (da.isEmpty() || db.isEmpty()) return false
            if (da == db) return true
            val nested = if (da.size < db.size) da to db else db to da
            return nested.first.size == 1 && nested.first.single().length >= 4 && nested.second.containsAll(nested.first)
        }

        /** Accents folded, case ignored, punctuation and bracketed asides dropped (SAME_PLACE). */
        internal fun normalized(value: String): String =
            OfflineRank.fold(
                value.replace("&", " and ").replace("+", " and ")
                    .replace(Regex("\\([^)]*\\)|\\[[^]]*]"), " "),
            )
                .replace(Regex("[^\\p{L}\\p{N} ]"), " ")
                .replace(Regex("\\s+"), " ")
                .trim()
                .removePrefix("the ")

        private fun identityWords(normalized: String): Set<String> =
            normalized.split(' ').filter { it.length >= 2 && it !in GENERIC_WORDS }.toSet()

        private fun transitHint(kind: String?): String? {
            val k = kind?.lowercase()?.takeUnless { raw -> NON_TRANSIT_WORDS.any { it in raw } } ?: return null
            return when {
                "bus" in k -> "bus stop"
                "tram" in k || "light_rail" in k -> "tram stop"
                "subway" in k || "metro" in k -> "station"
                "railway" in k || "train" in k || "rail" in k -> "station"
                "ferry" in k -> "ferry terminal"
                "station" in k || "halt" in k || "platform" in k || "stop" in k || "transit" in k -> "transit stop"
                else -> null
            }
        }

        private fun isTransit(category: String?): Boolean {
            val c = category?.lowercase() ?: return false
            return listOf("transit", "bus stop", "tram stop", "train station", "subway", "railway", "ferry terminal").any { it in c }
        }
    }
}
