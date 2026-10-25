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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SearchState(
    val query: String = "",
    val searching: Boolean = false,
    val results: List<Place> = emptyList(),
    val error: SearchError? = null,
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
    private val source: MapDataSource,
    private val scope: CoroutineScope,
) {
    private val _state = MutableStateFlow(SearchState())
    val state: StateFlow<SearchState> = _state.asStateFlow()

    private var started = false
    private var viewport: DoubleArray? = null
    private var myLocation: LatLng? = null
    private var searchJob: Job? = null
    private var generation = 0

    fun start() {
        started = true
    }

    fun setQuery(q: String) {
        _state.update { it.copy(query = q) }
    }

    /** Runs the current query. One search at a time: a new one cancels the one in flight. */
    fun submit() {
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
        _state.update { it.copy(searching = true, error = null) }
        searchJob = scope.launch {
            try {
                val result = source.search(q, near, span, rankFrom = rankFrom)
                if (gen != generation) return@launch
                _state.update {
                    it.copy(
                        searching = false,
                        results = result.places,
                        error = if (result.places.isEmpty()) SearchError.NoResults else null,
                    )
                }
            } catch (e: CancellationException) {
                // A replaced search must not write its error over the new one.
                throw e
            } catch (e: CalibrationNeededException) {
                if (gen == generation) fail(SearchError.NeedsRecalibration(e.message))
            } catch (e: Exception) {
                if (gen == generation) fail(SearchError.Failed(e.message))
            }
        }
    }

    fun clear() {
        searchJob?.cancel()
        searchJob = null
        generation++
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

    private fun fail(error: SearchError) {
        _state.update { it.copy(searching = false, results = emptyList(), error = error) }
    }

    private fun rankBias(near: LatLng?): LatLng? {
        val me = plausibleBias(myLocation) ?: return null
        return me.takeIf { near == null || it.distanceTo(near) < RANK_FROM_MAX_M }
    }

    companion object {
        private const val RANK_FROM_MAX_M = 50_000.0

        /** Null for a point within half a degree of 0,0: an unset location, not a place. */
        fun plausibleBias(l: LatLng?): LatLng? =
            l?.takeUnless { abs(it.lat) < 0.5 && abs(it.lng) < 0.5 }
    }
}
