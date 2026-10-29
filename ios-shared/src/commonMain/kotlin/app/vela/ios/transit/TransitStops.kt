package app.vela.ios.transit

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** A Transitous stop drawn on the map at high zoom, with the ids its board needs. */
data class TransitStopPin(
    val stopId: String,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val modes: List<String> = emptyList(),
    val parentId: String? = null,
    val siblingIds: List<String> = emptyList(),
)

data class TransitStopsState(
    val stops: List<TransitStopPin> = emptyList(),
    val loading: Boolean = false,
    val zoom: Double = 0.0,
)

/**
 * Transitous stop icons around the viewport (SPEC 8, "Stops and boards"). It runs from z15, asks
 * once per settled view after a short debounce, and drops every pin below that zoom. The board
 * itself is [TransitBoardStore]'s job; a pin only carries the ids needed to open it directly.
 */
class TransitStopStore(
    private val scope: CoroutineScope,
    private val source: suspend (south: Double, west: Double, north: Double, east: Double) -> List<TransitStopPin>,
    private val minZoom: Double = 15.0,
    private val maxStops: Int = 120,
) {
    private val _state = MutableStateFlow(TransitStopsState())
    val state: StateFlow<TransitStopsState> = _state.asStateFlow()

    private var job: Job? = null
    private var generation = 0
    private var last: Box? = null

    fun viewport(south: Double, west: Double, north: Double, east: Double, zoom: Double) {
        if (zoom < minZoom) {
            job?.cancel()
            generation += 1
            last = null
            if (_state.value.stops.isNotEmpty()) _state.value = TransitStopsState(zoom = zoom)
            return
        }
        val box = Box(south, west, north, east, zoom)
        if (box == last && !_state.value.loading) return
        last = box
        job?.cancel()
        val gen = ++generation
        job = scope.launch {
            delay(DEBOUNCE_MS)
            if (gen != generation) return@launch
            _state.value = _state.value.copy(loading = true, zoom = zoom)
            val found = runCatching { source(south, west, north, east) }.getOrDefault(emptyList())
            if (gen != generation) return@launch
            _state.value = TransitStopsState(stops = found.take(maxStops), loading = false, zoom = zoom)
        }
    }

    fun clear() {
        job?.cancel()
        generation += 1
        last = null
        _state.value = TransitStopsState()
    }

    private data class Box(
        val south: Double, val west: Double, val north: Double, val east: Double, val zoom: Double,
    )

    private companion object {
        const val DEBOUNCE_MS = 350L
    }
}
