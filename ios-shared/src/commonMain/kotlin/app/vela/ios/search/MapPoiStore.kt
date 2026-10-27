package app.vela.ios.search

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
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
import kotlinx.coroutines.launch

/** A basemap label being resolved, or a dropped pin that stays on the open map data alone. */
data class MapPoiState(
    val selected: Place? = null,
    val resolving: Boolean = false,
    val googleUnavailable: Boolean = false,
    val droppedPin: Boolean = false,
)

/**
 * Opens the Google listing for a named Liberty POI with one focused search. A miss keeps the OSM
 * name and point instead of adopting a nearby stranger. Also owns long-press reverse geocoding.
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

    fun tap(name: String, lat: Double, lng: Double, kind: String?) {
        if (!started || name.isBlank() || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        job?.cancel()
        val gen = ++generation
        val at = LatLng(lat, lng)
        val placeholder = Place(id = "osm:${name.hashCode()}", name = name, location = at, category = kind)
        val hint = transitHint(kind)
        // With "Look up tapped places on Google" off, the tap keeps Vela's own row: same card as a
        // miss, and no request leaves the phone (SET-PRIVACY).
        if (!GoogleUses.lookupTappedPlaces) {
            _state.value = MapPoiState(selected = placeholder, googleUnavailable = true)
            return
        }
        _state.value = MapPoiState(selected = placeholder, resolving = !NoGoogle.enabled)
        if (NoGoogle.enabled) {
            _state.value = MapPoiState(selected = placeholder, googleUnavailable = true)
            return
        }
        val query = if (hint != null && !name.lowercase().contains(hint)) "$name $hint" else name
        job = scope.launch {
            val match = try {
                bestMatch(name, at, kind, source().searchOnce(query, at))
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            if (gen != generation) return@launch
            if (match == null) {
                _state.value = MapPoiState(selected = placeholder, googleUnavailable = true)
            } else {
                _state.value = MapPoiState()
                onOpen(match)
            }
        }
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

    companion object {
        private const val SAME_LOT_M = 120.0
        private const val NO_NAME_MATCH_M = 60.0
        private const val BUSINESS_TAP_CAP_M = 1_500.0
        private const val TRANSIT_TAP_CAP_M = 250.0
        private const val SETTLEMENT_TAP_CAP_M = 30_000.0

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

        /** Port of the safe part of Android's onPoiTap ranking: name agreement before proximity. */
        internal fun bestMatch(name: String, at: LatLng, kind: String?, results: List<Place>): Place? {
            val live = results.filterNot { it.permanentlyClosed }
            val hint = transitHint(kind)
            if (hint != null) {
                return live.filter { isTransit(it.category) && it.location.distanceTo(at) <= TRANSIT_TAP_CAP_M }
                    .minByOrNull { it.location.distanceTo(at) }
            }
            val answerable = live.ifEmpty { results }.filter {
                it.name.isNotBlank() && !isTransit(it.category) &&
                    !JUNCTION_CATEGORIES.any { category -> category == it.category?.lowercase() }
            }
            val cap = if (kind?.lowercase() in SETTLEMENT_KINDS) SETTLEMENT_TAP_CAP_M else BUSINESS_TAP_CAP_M
            val named = answerable.filter { it.location.distanceTo(at) <= cap && nameAgrees(name, it.name) }
            val exactOnLot = named.filter { normalized(name) == normalized(it.name) && it.location.distanceTo(at) <= SAME_LOT_M }
            val namedPick = (exactOnLot.ifEmpty { named }).minByOrNull { it.location.distanceTo(at) }
            if (namedPick != null) return namedPick
            val tappedGroup = kindGroup(kind)
            if (tappedGroup == null) return null
            return answerable.filter {
                it.location.distanceTo(at) <= NO_NAME_MATCH_M && kindGroup(it.category) == tappedGroup
            }.minByOrNull { it.location.distanceTo(at) }
        }

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

        private fun normalized(value: String): String = value.lowercase()
            .replace("&", " and ")
            .replace("+", " and ")
            .replace(Regex("\\([^)]*\\)|\\[[^]]*]"), " ")
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

        private fun kindGroup(kind: String?): String? {
            val k = kind?.lowercase() ?: return null
            return when {
                listOf("gas", "fuel", "petrol", "service station").any { it in k } -> "fuel"
                "parking" in k -> "parking"
                listOf("supermarket", "grocery", "greengrocer").any { it in k } -> "grocery"
                listOf("cafe", "coffee").any { it in k } -> "coffee"
                "restaurant" in k -> "restaurant"
                listOf("hotel", "motel", "hostel", "lodging").any { it in k } -> "lodging"
                isTransit(k) -> "transit"
                else -> null
            }
        }
    }
}
