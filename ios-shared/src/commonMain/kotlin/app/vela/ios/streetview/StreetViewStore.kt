package app.vela.ios.streetview

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.StreetViewCache
import app.vela.core.data.google.StreetViewParser
import app.vela.core.model.LatLng
import app.vela.core.model.StreetViewPano
import app.vela.core.model.StreetViewTime
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.Log
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.platform.i
import app.vela.core.util.ioDispatcher
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
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
    /**
     * True while the pano on screen is an older capture picked from the history list. The pano
     * keeps the base spot's walk graph and history; only its id, heading and pyramid are the
     * historical capture's.
     */
    val historical: Boolean = false,
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
 * `svtiles/<pano>-<zoom>-<x>-<y>.jpg` through [StreetViewCache], whose byte and count budget
 * (`MAX_TILE_BYTES`, `MAX_TILE_FILES`) is shared with the rest of the Street View cache. Pano
 * metadata also goes through [StreetViewCache] under `<filesDir>/svcache`, so a capture switch
 * or a reopen after the app was killed does not need Google again. A tile request that is no
 * longer around the viewport is cancelled by [cancelTiles].
 */
class StreetViewStore(
    private val source: () -> MapDataSource,
    private val scope: CoroutineScope,
    private val http: VelaHttp? = null,
    private val tileHeaders: (() -> List<HttpHeader>)? = null,
    private val files: PlatformFiles? = null,
    private val log: Log? = null,
    /** Disk work; overridable so a JVM test drives it from its own scheduler. */
    private val io: CoroutineDispatcher = ioDispatcher,
) {
    private val _state = MutableStateFlow(StreetViewState())
    val state: StateFlow<StreetViewState> = _state

    private var panoJob: Job? = null
    /** The current capture at this spot, before any history switch; walk updates it. */
    private var basePano: StreetViewPano? = null
    private val tilesMutex = Mutex()
    private val inflight = mutableMapOf<String, Deferred<ByteArray?>>()
    private var writesSincePrune = 0
    private val metaCache: StreetViewCache? = files?.let(::StreetViewCache)
    private val metaDir: String? = files?.let { "${it.filesDir}/svcache" }

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
        basePano = null
        _state.value = StreetViewState(loading = true)
        if (NoGoogle.enabled) {
            _state.value = StreetViewState(error = "no_imagery")
            return
        }
        val face = faceBearingDeg.takeIf { it.isFinite() }?.let(::normalizeDeg)
        panoJob = scope.launch {
            val location = LatLng(latitude, longitude)
            val street = StreetViewParser.streetOf(address)
            // A pano already seen is answered from the metadata cache, so reopening it (or
            // opening a place in a downloaded region) does not ask Google again. Only the
            // nearest-location lookup has no cache key.
            var pano = panoId?.takeIf { it.isNotBlank() }?.let { cachedMeta(it) }
            if (pano == null) {
                pano = panoId?.takeIf { it.isNotBlank() }?.let { quiet { source().streetViewByPano(it) } }
            }
            if (pano == null) pano = quiet { source().streetView(location, street) }
            if (pano == null) {
                log?.i(TAG, "open: no imagery")
                _state.value = StreetViewState(error = "no_imagery")
                return@launch
            }
            rememberMeta(pano)
            basePano = pano
            val shown = if (face != null) pano.copy(initialFacingDeg = face) else pano
            log?.i(
                TAG,
                "open: pano=${shown.panoId} heading=${shown.headingDeg.toInt()} " +
                    "neighbors=${shown.neighbors.size} levels=${shown.levelDims.size} " +
                    "history=${shown.history.size}",
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
            rememberMeta(next)
            basePano = next
            log?.i(
                TAG,
                "walk: pano=${shown.panoId} neighbors=${shown.neighbors.size} " +
                    "history=${shown.history.size}",
            )
            _state.value = StreetViewState(pano = shown)
        }
    }

    /**
     * Switches to another capture of the same spot, as Android's date chip does. The spot's walk
     * graph and its full history stay the base pano's, so the date list and the walk arrows come
     * back when the newest capture is picked again. The old capture brings its own metadata, which
     * matters twice: its pyramid can be a pre-2016 416 * 2^z one, and its capture heading can
     * differ by up to 180 degrees, which would rotate the view if the base heading were kept.
     *
     * [faceBearingDeg] is the compass direction currently on screen; the new capture opens on that
     * same bearing, so switching time does not spin the view. One metadata fetch at most, and only
     * on a cache miss; tiles then come from the ordinary tile cache or network.
     */
    fun timeTravel(time: StreetViewTime, faceBearingDeg: Double) {
        if (NoGoogle.enabled) return
        val base = basePano ?: _state.value.pano ?: return
        if (time.year !in 1000..9999 || time.month !in 1..12) return
        val current = _state.value
        val face = faceBearingDeg.takeIf { it.isFinite() }?.let(::normalizeDeg)
        if (time.panoId == base.panoId) {
            // Back to the capture that defines the spot: nothing to load, just relabel and keep
            // the current view direction.
            panoJob?.cancel()
            cancelAllTiles()
            val shown = base.copy(initialFacingDeg = face ?: current.pano?.initialFacingDeg)
            log?.i(TAG, "timeTravel: back to ${shown.panoId}")
            _state.value = StreetViewState(pano = shown)
            return
        }
        panoJob?.cancel()
        cancelAllTiles()
        _state.value = current.copy(loading = true, error = null, historical = true)
        panoJob = scope.launch {
            val cached = cachedMeta(time.panoId)
            val live = if (cached == null) quiet { source().streetViewByPano(time.panoId) } else null
            val hist = cached ?: live
            if (live != null) rememberMeta(live)
            // No metadata is not a dead end: the base pyramid is the best remaining guess, and
            // the capture still has its own id for the tiles. Never invent a heading.
            val shown = if (hist != null) {
                hist.copy(
                    history = base.history,
                    addressLabel = hist.addressLabel ?: base.addressLabel,
                    copyright = hist.copyright ?: base.copyright,
                    initialFacingDeg = face ?: hist.initialFacingDeg ?: hist.headingDeg,
                )
            } else {
                base.copy(
                    panoId = time.panoId,
                    captureYear = time.year,
                    captureMonth = time.month,
                    initialFacingDeg = face ?: base.initialFacingDeg ?: base.headingDeg,
                )
            }
            log?.i(
                TAG,
                "timeTravel: pano=${shown.panoId} ${time.year}-${time.month} " +
                    "heading=${shown.headingDeg.toInt()} metadata=${hist != null}",
            )
            _state.value = StreetViewState(pano = shown, historical = true)
        }
    }

    /** The viewer closed: stop the metadata lookup and every tile that is still in flight. */
    fun close() {
        panoJob?.cancel()
        panoJob = null
        basePano = null
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

    private suspend fun cachedTile(key: String): ByteArray? {
        val cache = metaCache ?: return null
        val dir = cacheDir() ?: return null
        return withContext(io) { cache.loadTile(dir, key) }
    }

    private suspend fun storeTile(key: String, bytes: ByteArray) {
        val cache = metaCache ?: return
        val dir = cacheDir() ?: return
        withContext(io) {
            cache.saveTile(dir, key, bytes)
            if (++writesSincePrune >= PRUNE_EVERY_WRITES) {
                writesSincePrune = 0
                cache.pruneTiles(dir)
            }
        }
    }

    /** A pano's metadata from the shared Street View cache, if this viewer has one on disk. */
    private suspend fun cachedMeta(panoId: String): StreetViewPano? {
        val cache = metaCache ?: return null
        val dir = metaDir ?: return null
        return withContext(io) { cache.loadMeta(dir, panoId) }
    }

    /** Keeps a resolved pano's metadata for history switches and offline reopens. */
    private suspend fun rememberMeta(pano: StreetViewPano) {
        val cache = metaCache ?: return
        val dir = metaDir ?: return
        withContext(io) { cache.saveMeta(dir, pano) }
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
        const val PRUNE_EVERY_WRITES = 32
    }
}
