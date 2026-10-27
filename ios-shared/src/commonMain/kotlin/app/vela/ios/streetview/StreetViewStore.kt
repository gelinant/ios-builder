package app.vela.ios.streetview

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.google.StreetViewParser
import app.vela.core.model.LatLng
import app.vela.core.model.StreetViewPano
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.Log
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.platform.i
import app.vela.core.util.ioDispatcher
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** What the iOS viewer shows: a pano, a load in flight, or the reason there is none. */
data class StreetViewState(
    val pano: StreetViewPano? = null,
    val loading: Boolean = false,
    /** "no_imagery" when Google has no pano there (or the lookup failed), null otherwise. */
    val error: String? = null,
)

/**
 * The iOS Street View session: resolves a panorama through the common `StreetViewParser`, walks to
 * a neighbor by pano id, and serves tiles through the shared HTTP client with Safari's image
 * headers.
 *
 * Pano selection is Android's: a place's own thumbnail pano is tried by id first (epoch exact),
 * then the nearest-pano lookup at the place carries the address's street so the common source can
 * prefer the frontage pano over a back-alley one. The result keeps Google's capture heading
 * ([StreetViewPano.headingDeg]); the viewer asks for a facing direction separately through
 * `initialFacingDeg`.
 *
 * Tiles are cached in memory only while a request is in flight; decoded images live in the
 * Swift side's bounded cache. On disk, JPEGs go under the platform cache directory as
 * `svtiles/<pano>-<zoom>-<x>-<y>.jpg`, bounded by [MAX_TILE_BYTES] and [MAX_TILE_FILES]. A tile
 * request that is no longer around the viewport is cancelled by [cancelTiles].
 */
class StreetViewStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
    private val http: VelaHttp? = null,
    private val tileHeaders: (() -> List<HttpHeader>)? = null,
    private val files: PlatformFiles? = null,
    private val log: Log? = null,
) {
    private val _state = MutableStateFlow(StreetViewState())
    val state: StateFlow<StreetViewState> = _state

    private var panoJob: Job? = null
    private val tilesMutex = Mutex()
    private val inflight = mutableMapOf<String, Deferred<ByteArray?>>()
    private var writesSincePrune = 0

    /**
     * Opens the panorama for a place. [panoId] is the place thumbnail's pano, tried by id first;
     * [faceBearingDeg] is the compass direction the viewer should face (Google's yaw for the
     * place, or the bearing from the pano to the place). [address] gives the street the common
     * source prefers when it has to fall back to the nearest lookup.
     */
    fun open(
        latitude: Double,
        longitude: Double,
        address: String?,
        panoId: String?,
        faceBearingDeg: Double,
    ) {
        if (panoId.isNullOrBlank() && (latitude !in -90.0..90.0 || longitude !in -180.0..180.0)) return
        panoJob?.cancel()
        cancelAllTiles()
        _state.value = StreetViewState(loading = true)
        if (NoGoogle.enabled) {
            _state.value = StreetViewState(error = "no_imagery")
            return
        }
        val face = faceBearingDeg.takeIf { it.isFinite() }?.let(::normalizeDeg)
        panoJob = scope.launch {
            val location = LatLng(latitude, longitude)
            val street = StreetViewParser.streetOf(address)
            var pano = panoId?.takeIf { it.isNotBlank() }?.let { quiet { source().streetViewByPano(it) } }
            if (pano == null) pano = quiet { source().streetView(location, street) }
            if (pano == null) {
                log?.i(TAG, "open: no imagery")
                _state.value = StreetViewState(error = "no_imagery")
                return@launch
            }
            val shown = if (face != null) pano.copy(initialFacingDeg = face) else pano
            log?.i(
                TAG,
                "open: pano=${shown.panoId} heading=${shown.headingDeg.toInt()} " +
                    "neighbors=${shown.neighbors.size} levels=${shown.levelDims.size}",
            )
            _state.value = StreetViewState(pano = shown)
        }
    }

    /**
     * One walk step, by pano id. A nearest-location lookup would land on a different-year capture
     * at the same spot, so the neighbor's own id is the only argument (SPEC 10.7).
     */
    fun walk(panoId: String, faceBearingDeg: Double) {
        if (panoId.isBlank() || NoGoogle.enabled) return
        val current = _state.value
        val startPano = current.pano ?: return
        panoJob?.cancel()
        cancelAllTiles()
        _state.value = current.copy(loading = true, error = null)
        val face = faceBearingDeg.takeIf { it.isFinite() }?.let(::normalizeDeg)
        panoJob = scope.launch {
            val next = quiet { source().streetViewByPano(panoId) }
            if (next == null) {
                log?.i(TAG, "walk: no imagery for $panoId")
                _state.value = _state.value.copy(loading = false, error = "no_imagery")
                return@launch
            }
            // Keep facing the street the user was walking down; Google's own heading only frames
            // the texture and must never be overwritten (SPEC 10.7).
            val shown = next.copy(
                initialFacingDeg = face ?: startPano.initialFacingDeg ?: next.headingDeg,
            )
            log?.i(TAG, "walk: pano=${shown.panoId} neighbors=${shown.neighbors.size}")
            _state.value = StreetViewState(pano = shown)
        }
    }

    /** The viewer closed: stop the metadata lookup and every tile that is still in flight. */
    fun close() {
        panoJob?.cancel()
        panoJob = null
        _state.value = StreetViewState()
        cancelAllTiles()
    }

    /**
     * One tile as JPEG bytes, through the disk cache then the network. Returns null on failure or
     * when the request was cancelled by [cancelTiles].
     */
    suspend fun tile(panoId: String, zoom: Int, x: Int, y: Int): ByteArray? {
        if (NoGoogle.enabled || panoId.isBlank()) return null
        val key = StreetViewTiles.cacheKey(panoId, zoom, x, y)
        cachedTile(key)?.let { return it }
        val deferred = tilesMutex.withLock {
            inflight[key] ?: scope.async {
                fetchTile(panoId, zoom, x, y, key)
            }.also { job ->
                inflight[key] = job
                job.invokeOnCompletion {
                    scope.launch { tilesMutex.withLock { if (inflight[key] === job) inflight.remove(key) } }
                }
            }
        }
        return try {
            deferred.await()
        } catch (_: CancellationException) {
            null
        }
    }

    /** Cancels the tile requests that are no longer in [keep]'s viewport (and those of old panos). */
    fun cancelTiles(panoId: String, keep: List<StreetViewTileRef>) {
        val keepKeys = keep.mapTo(HashSet()) {
            StreetViewTiles.cacheKey(panoId, it.zoom, it.x, it.y)
        }
        scope.launch {
            tilesMutex.withLock {
                val stale = inflight.keys.filter { it !in keepKeys }
                stale.forEach { inflight.remove(it)?.cancel() }
            }
        }
    }

    /** Stops every in-flight tile, on close and before a new pano. */
    fun cancelAllTiles() {
        scope.launch {
            tilesMutex.withLock {
                inflight.values.forEach { it.cancel() }
                inflight.clear()
            }
        }
    }

    private suspend fun fetchTile(panoId: String, zoom: Int, x: Int, y: Int, key: String): ByteArray? {
        val bytes = try {
            fetchBytes(panoId, zoom, x, y)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
        if (bytes != null && bytes.isNotEmpty()) storeTile(key, bytes)
        return bytes
    }

    private suspend fun fetchBytes(panoId: String, zoom: Int, x: Int, y: Int): ByteArray? {
        val client = http
        if (client != null) {
            val headers = tileHeaders?.invoke() ?: emptyList()
            val response = client.call(
                HttpRequest(StreetViewTiles.url(panoId, x, y, zoom), headers = headers),
            )
            return if (response.isSuccessful) response.body.takeIf { it.isNotEmpty() } else null
        }
        return source().streetViewTile(panoId, x, y, zoom)
    }

    // --- Disk cache ---------------------------------------------------------------------------

    private fun cacheDir(): String? = files?.let { "${it.cacheDir}/svtiles" }

    private fun tilePath(key: String): String? = cacheDir()?.let { "$it/$key.jpg" }

    private suspend fun cachedTile(key: String): ByteArray? {
        val path = tilePath(key) ?: return null
        val store = files ?: return null
        return withContext(ioDispatcher) {
            runCatching { store.readBytes(path).takeIf { it.isNotEmpty() } }.getOrNull()
        }
    }

    private suspend fun storeTile(key: String, bytes: ByteArray) {
        val files = files ?: return
        val dir = cacheDir() ?: return
        val path = tilePath(key) ?: return
        withContext(ioDispatcher) {
            runCatching {
                files.mkdirs(dir)
                files.writeBytes(path, bytes)
            }
            if (++writesSincePrune >= PRUNE_EVERY_WRITES) {
                writesSincePrune = 0
                prune(files, dir)
            }
        }
    }

    /** Drops the oldest files once the cache passes its size or count budget. */
    private fun prune(files: PlatformFiles, dir: String) {
        val entries = files.list(dir) ?: return
        var count = entries.size
        var total = entries.sumOf { it.size }
        val maxFiles = MAX_TILE_FILES.toLong()
        val targetFiles = MAX_TILE_FILES * 3L / 4
        val targetBytes = MAX_TILE_BYTES * 3L / 4
        if (count <= maxFiles && total <= MAX_TILE_BYTES) return
        for (entry in entries.sortedBy { it.lastModifiedMillis }) {
            if (count <= targetFiles && total <= targetBytes) break
            if (files.delete(entry.path)) {
                count -= 1
                total -= entry.size
            }
        }
    }

    private suspend fun <T> quiet(block: suspend () -> T): T? = try {
        block()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }

    private fun normalizeDeg(d: Double): Double {
        val v = d % 360.0
        return if (v < 0) v + 360.0 else v
    }

    private companion object {
        const val TAG = "StreetView"
        const val MAX_TILE_BYTES = 24L * 1024 * 1024
        const val MAX_TILE_FILES = 512
        const val PRUNE_EVERY_WRITES = 32
    }
}
