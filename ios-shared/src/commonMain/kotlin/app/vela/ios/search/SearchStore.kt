package app.vela.ios.search

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.distanceTo
import app.vela.core.platform.Cancellable
import kotlin.math.abs
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** The offline facet's search hook, installed by MapSession without coupling this store to files. */
interface OfflineSearch {
    fun offlineOnly(): Boolean
    suspend fun search(query: String, near: LatLng?): List<Place>
}

data class SearchState(
    val query: String = "",
    val searching: Boolean = false,
    val results: List<Place> = emptyList(),
    val suggestions: List<Place> = emptyList(),
    val querySuggestions: List<String> = emptyList(),
    val error: SearchError? = null,
    val usedOffline: Boolean = false,
    /** Number of accepted submissions, including one that replaces a search in flight. */
    val submissions: Int = 0,
)

sealed interface SearchError {
    /** `mapvm_no_results`. */
    data object NoResults : SearchError

    /** `mapvm_search_needs_recalibration`. */
    data class NeedsRecalibration(val where: String?) : SearchError

    /** `mapvm_search_failed_reason`. */
    data class Failed(val reason: String?) : SearchError
}

/**
 * The search facet of the map (docs/ios/PRESENTATION-MAP.md 4.2): the online Google branch of
 * Android's `runSearch`. The bias is the viewport center, else the user's location, each only
 * when plausible; the window is the viewport height; results are ranked from the user when they
 * are within 50 km of the bias.
 *
 * The constructor does nothing; [start] arms the store (PRESENTATION-MAP.md 5, trap 1). Every
 * intent is meant for the [scope]'s thread (the main thread on iOS).
 */
class SearchStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
) {
    constructor(source: MapDataSource, scope: CoroutineScope) : this({ source }, scope)

    private val _state = MutableStateFlow(SearchState())
    val state: StateFlow<SearchState> = _state.asStateFlow()

    private var started = false
    private var viewport: DoubleArray? = null
    private var myLocation: LatLng? = null
    private var searchJob: Job? = null
    private var suggestJob: Job? = null
    private var generation = 0
    private var suggestGeneration = 0
    internal var offline: OfflineSearch? = null

    fun start() {
        started = true
    }

    /** Android's typing pause: one autocomplete request after 320 ms, never one per character. */
    fun setQuery(q: String) {
        _state.update { it.copy(query = q) }
        suggestJob?.cancel()
        val gen = ++suggestGeneration
        val term = q.trim()
        if (!started || term.length < 2) {
            _state.update { it.copy(suggestions = emptyList(), querySuggestions = emptyList()) }
            return
        }
        suggestJob = scope.launch {
            delay(SUGGEST_DEBOUNCE_MS)
            val vp = viewport
            val center = vp?.let { LatLng((it[0] + it[2]) / 2, (it[1] + it[3]) / 2) }
            val near = plausibleBias(center) ?: plausibleBias(myLocation)
            val span = vp?.let { LatLng(it[0], it[1]).distanceTo(LatLng(it[2], it[1])) }
            val result = try {
                source().suggest(term, near, span)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                null
            }
            if (gen != suggestGeneration || _state.value.query.trim() != term) return@launch
            _state.update {
                it.copy(
                    suggestions = result?.places?.take(MAX_SUGGESTIONS).orEmpty(),
                    querySuggestions = result?.queries?.take(MAX_QUERY_SUGGESTIONS).orEmpty(),
                )
            }
        }
    }

    /** A query row or category runs directly, without starting another autocomplete request. */
    fun search(query: String) {
        _state.update { it.copy(query = query) }
        submit()
    }

    /** The place row at [index], or null after the suggestions changed. */
    fun suggestion(index: Int): Place? = _state.value.suggestions.getOrNull(index)

    /** A selection owns the screen now: cancel autocomplete and drop its rows. */
    fun dismissSuggestions() {
        suggestJob?.cancel()
        suggestJob = null
        suggestGeneration++
        _state.update { it.copy(suggestions = emptyList(), querySuggestions = emptyList()) }
    }

    /** Runs the current query. One search at a time: a new one cancels the one in flight. */
    fun submit() {
        dismissSuggestions()
        if (!started) return
        val q = _state.value.query.trim()
        if (q.isEmpty()) return
        searchJob?.cancel()
        val gen = ++generation
        val vp = viewport
        val center = vp?.let { LatLng((it[0] + it[2]) / 2, (it[1] + it[3]) / 2) }
        val near = plausibleBias(center) ?: plausibleBias(myLocation)
        val span = vp?.let { LatLng(it[0], it[1]).distanceTo(LatLng(it[2], it[1])) }
        val rankFrom = rankBias(near)
        _state.update { it.copy(searching = true, error = null, submissions = it.submissions + 1) }
        searchJob = scope.launch {
            val local = offline
            if (local?.offlineOnly() == true) {
                val places = localResults(local, q, near)
                if (gen != generation) return@launch
                _state.update {
                    it.copy(
                        searching = false, results = places, usedOffline = true,
                        error = if (places.isEmpty()) SearchError.NoResults else null,
                    )
                }
                return@launch
            }
            try {
                val result = source().search(q, near, span, rankFrom = rankFrom)
                val localPlaces = local?.let { localResults(it, q, near) }.orEmpty()
                val merged = mergeResults(result.places, localPlaces)
                if (gen != generation) return@launch
                _state.update {
                    it.copy(
                        searching = false,
                        results = merged,
                        usedOffline = false,
                        error = if (merged.isEmpty()) SearchError.NoResults else null,
                    )
                }
            } catch (e: CancellationException) {
                // A replaced search must not write its error over the new one.
                throw e
            } catch (e: CalibrationNeededException) {
                if (gen == generation) fail(SearchError.NeedsRecalibration(e.message))
            } catch (e: Exception) {
                val places = local?.let { localResults(it, q, near) }.orEmpty()
                if (gen == generation) {
                    if (places.isNotEmpty()) {
                        _state.update { it.copy(searching = false, results = places, usedOffline = true, error = null) }
                    } else fail(SearchError.Failed(e.message))
                }
            }
        }
    }

    fun clear() {
        searchJob?.cancel()
        suggestJob?.cancel()
        searchJob = null
        suggestJob = null
        generation++
        suggestGeneration++
        _state.value = SearchState()
    }

    /** The visible map: `[south, west, north, east]` and the zoom, as Android's `onViewport`. */
    fun onViewport(south: Double, west: Double, north: Double, east: Double, zoom: Double) {
        viewport = doubleArrayOf(south, west, north, east, zoom)
    }

    fun onLocation(lat: Double, lng: Double) {
        myLocation = LatLng(lat, lng)
    }

    /**
     * Calls [onChange] with the current state, then with each change, on the store's thread, until
     * the returned handle is cancelled. For Swift code that cannot iterate [state] through SKIE.
     */
    fun watch(onChange: (SearchState) -> Unit): Cancellable {
        val job = scope.launch { state.collect { onChange(it) } }
        return Cancellable { job.cancel() }
    }

    private suspend fun localResults(local: OfflineSearch, query: String, near: LatLng?): List<Place> =
        try {
            local.search(query, near)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }

    private fun fail(error: SearchError) {
        _state.update { it.copy(searching = false, results = emptyList(), error = error, usedOffline = false) }
    }

    private fun rankBias(near: LatLng?): LatLng? {
        val me = plausibleBias(myLocation) ?: return null
        return me.takeIf { near == null || it.distanceTo(near) < RANK_FROM_MAX_M }
    }

    companion object {
        private const val RANK_FROM_MAX_M = 50_000.0
        internal const val SUGGEST_DEBOUNCE_MS = 320L
        private const val MAX_SUGGESTIONS = 8
        private const val MAX_QUERY_SUGGESTIONS = 3

        /** Null for a point within half a degree of 0,0: an unset location, not a place. */
        fun plausibleBias(l: LatLng?): LatLng? =
            l?.takeUnless { abs(it.lat) < 0.5 && abs(it.lng) < 0.5 }

        /** Online rows lead except typed addresses; duplicate OSM/Overture rows within a block collapse. */
        internal fun mergeResults(online: List<Place>, local: List<Place>): List<Place> {
            val candidates = if (local.any { it.category == "Address" }) local + online else online + local
            val out = ArrayList<Place>(candidates.size)
            for (p in candidates) {
                if (out.any {
                        it.id == p.id ||
                            (it.name.equals(p.name, ignoreCase = true) && it.location.distanceTo(p.location) < 60.0)
                    }
                ) continue
                out += p
            }
            return out
        }
    }
}
