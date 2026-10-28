package app.vela.ios.offline

import app.vela.core.config.VelaLinks
import app.vela.core.data.NoGoogle
import app.vela.core.data.OfflineAddressStore
import app.vela.core.data.OfflinePacks
import app.vela.core.data.OfflinePoiStore
import app.vela.core.data.OverpassAlprCameras
import app.vela.core.data.OverpassSpeedCameras
import app.vela.core.data.naming.RoadNameTiles
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.offline.PlacesArchiveSearch
import app.vela.core.offline.PmtilesReader
import app.vela.core.offline.RegionCatalog
import app.vela.core.offline.RegionPacks
import app.vela.core.offline.RegionPolys
import app.vela.core.offline.RoutingRegion
import app.vela.core.platform.Cancellable
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.i
import app.vela.core.platform.joinPath
import app.vela.core.platform.treeSize
import app.vela.core.platform.w
import app.vela.core.util.ioDispatcher
import app.vela.ios.search.OfflineSearch
import app.vela.ios.settings.SettingsStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.concurrent.Volatile
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/** One row of the region sheet. Sizes are estimates until the region is installed. */
data class OfflineRegion(
    val id: String,
    val name: String,
    val sizeMb: Int,
    val installed: Boolean,
)

/** Numeric state and string keys only; Swift owns every label and formatted size. */
data class OfflineState(
    val loading: Boolean = false,
    val regions: List<OfflineRegion> = emptyList(),
    val currentRegionId: String? = null,
    val downloadingId: String? = null,
    val downloadStage: String = "",
    val downloadProgress: Int = 0,
    val downloadCompletedPieces: Int = 0,
    val downloadPieceCount: Int = 0,
    val completedId: String? = null,
    val errorKey: String? = null,
    val networkAvailable: Boolean = true,
    val googleDisabled: Boolean = false,
    val totalBytes: Long = 0,
    val packBytes: Long = 0,
    val placesBytes: Long = 0,
    val basemapBytes: Long = 0,
    val glyphBytes: Long = 0,
    val revision: Int = 0,
)

/**
 * The Swift URLSession downloader. [targetPath] is a file for packs and PMTiles, and the glyph
 * directory for `map-fonts`. Every completion is on the main queue. A null error means installed;
 * the implementation checks status, length and format before its atomic rename.
 */
interface OfflineDownloadClient {
    fun start(
        id: String,
        kind: String,
        url: String,
        targetPath: String,
        onProgress: (receivedBytes: Long, totalBytes: Long) -> Unit,
        onComplete: (error: String?) -> Unit,
    ): Cancellable
}

@Serializable
internal data class InstalledArchive(
    val id: String,
    val s: Double,
    val w: Double,
    val n: Double,
    val e: Double,
) {
    val area: Double get() = (n - s) * (e - w)
    fun contains(p: LatLng) = p.lat in s..n && p.lng in w..e
}

@Serializable
internal data class InstalledRegion(
    val id: String,
    val packId: String? = null,
    val places: List<InstalledArchive> = emptyList(),
    val maps: List<InstalledArchive> = emptyList(),
)

@Serializable
internal data class OfflineAssetPlan(
    val id: String,
    val kind: String,
    val url: String,
    val targetPath: String,
)

/** The whole region plan, not just its current task, so a new process can finish the sequence. */
@Serializable
internal data class PendingRegionDownload(
    val record: InstalledRegion,
    val assets: List<OfflineAssetPlan>,
    val failed: Boolean = false,
)

/** One camera in a region pack. [kind] is `speed` or `alpr`. */
@Serializable
internal data class RegionCamera(val lat: Double, val lng: Double, val kind: String)

/**
 * The camera pack written into the offline folder when a region finishes downloading. It is
 * keyed by the region bbox and dated at the moment Overpass answered; Swift reads the same file
 * and refuses to draw it once it is older than a year. Speed cameras live only here: the
 * repository ships no baked speed-camera dataset (the bundled iOS pack is plate cameras only).
 */
@Serializable
internal data class RegionCameraPack(
    val id: String,
    val name: String,
    val kind: String = "both",
    val generatedAtMs: Long,
    val s: Double,
    val w: Double,
    val n: Double,
    val e: Double,
    val cameras: List<RegionCamera> = emptyList(),
)

/**
 * The offline facet of MapSession: region catalogs, downloads, installed files and local search.
 * iOS deliberately does not fetch the OBF row: its manifest is only the shared region catalog.
 * Construction is inert. [start] opens installed packs, reads the cached catalog and refreshes it.
 */
class OfflineStore(
    private val core: CoreGraph,
    private val sql: SqlDbs,
    private val scope: CoroutineScope,
    private val downloader: OfflineDownloadClient,
) : OfflineSearch {
    private val files = core.files
    private val catalog = RegionCatalog(core.http, files)
    private val poiStore = OfflinePoiStore(sql)
    private val addressStore = OfflineAddressStore(sql)
    private val settings = core.keyValues.open("vela_settings")
    private val json = Json { ignoreUnknownKeys = true }

    val rootPath: String = joinPath(files.noBackupDir, "offline")
    val glyphsPath: String = joinPath(rootPath, "glyphs")
    val spritesPath: String = joinPath(rootPath, "sprites")
    val cameraPacksPath: String = joinPath(rootPath, "camera-packs")
    private val packsPath = joinPath(rootPath, "poipacks")
    private val placesPath = joinPath(rootPath, "places")
    private val basemapPath = joinPath(rootPath, "basemap")
    private val regionsPath = joinPath(rootPath, "regions")
    private val pendingPath = joinPath(rootPath, "region-download.json")

    private val _state = MutableStateFlow(OfflineState())
    val state: StateFlow<OfflineState> = _state.asStateFlow()

    private var started = false
    private var refreshJob: Job? = null
    private var downloadJob: Job? = null
    private var routing = emptyList<RoutingRegion>()
    private var packs = emptyList<RoutingRegion>()
    private var places = emptyList<RoutingRegion>()
    private var maps = emptyList<RoutingRegion>()
    @Volatile private var installed = emptyMap<String, InstalledRegion>()
    private var pending: PendingRegionDownload? = null
    private var myLocation: LatLng? = null

    @Volatile private var network = true
    @Volatile private var testOffline = false

    fun start() {
        if (started) return
        started = true
        network = true
        setGoogleDisabled(settings.getBoolean(SettingsStore.GOOGLE_DISABLED_KEY, false), persist = false)
        scope.launch {
            installed = withContext(ioDispatcher) { readInstalled() }
            withContext(ioDispatcher) { registerPacks() }
            installRoadNameSource()
            rebuildRegions()
            updateStorage()
            val restored = withContext(ioDispatcher) { readPending() }
            pending = restored?.takeUnless { it.record.id in installed }
            if (restored != null && pending == null) {
                withContext(ioDispatcher) { files.delete(pendingPath) }
            }
            val restoredCompleted = pending?.let { plan ->
                withContext(ioDispatcher) { plan.assets.count { valid(it.kind, it.targetPath) } }
            } ?: 0
            when {
                pending?.failed == true -> _state.update {
                    it.copy(
                        errorKey = "download_failed",
                        downloadCompletedPieces = restoredCompleted,
                        downloadPieceCount = pending?.assets?.size ?: 0,
                    )
                }
                pending != null -> {
                    val plan = pending!!
                    downloadJob = scope.launch { runDownload(plan) }
                }
            }
            refresh()
        }
    }

    /** Fetches the four manifests. RegionCatalog keeps each last good reply on disk. */
    fun refresh() {
        if (!started || refreshJob?.isActive == true) return
        refreshJob = scope.launch {
            _state.update { it.copy(loading = true) }
            routing = catalog.manifest(VelaLinks.obfManifest())
            packs = catalog.manifest(VelaLinks.poiPackManifest())
            places = catalog.manifest(VelaLinks.placesManifest())
            maps = catalog.manifest(VelaLinks.basemapManifest())
            rebuildRegions()
            _state.update { it.copy(loading = false) }
        }
    }

    fun loadRegionPolygons(text: String) {
        RegionPolys.ensureLoaded { text }
        updateCurrentRegion()
    }

    fun onLocation(lat: Double, lng: Double) {
        myLocation = LatLng(lat, lng)
        updateCurrentRegion()
    }

    fun setNetworkAvailable(available: Boolean) {
        network = available
        _state.update { it.copy(networkAvailable = available && !testOffline) }
    }

    /** Debug UI scenario: stays offline even if NWPathMonitor publishes another path update. */
    fun setOfflineTestMode(enabled: Boolean) {
        testOffline = enabled
        _state.update { it.copy(networkAvailable = network && !enabled) }
    }

    fun setGoogleDisabled(disabled: Boolean) = setGoogleDisabled(disabled, persist = true)

    private fun setGoogleDisabled(disabled: Boolean, persist: Boolean) {
        NoGoogle.enabled = disabled
        if (persist) settings.edit().putBoolean(SettingsStore.GOOGLE_DISABLED_KEY, disabled).apply()
        _state.update { it.copy(googleDisabled = disabled) }
    }

    override fun offlineOnly(): Boolean = NoGoogle.enabled || !network || testOffline

    /** Downloads one persisted plan. Every asset and the final marker survive process death. */
    fun download(regionId: String) {
        if (!started || downloadJob?.isActive == true || installed.containsKey(regionId)) return
        if (pending?.failed == false && pending != null) return
        downloadJob = scope.launch {
            try {
                val plan = pending?.takeIf { it.record.id == regionId }?.copy(failed = false)
                    ?: withContext(ioDispatcher) { makePlan(regionId) } ?: return@launch
                pending = plan
                withContext(ioDispatcher) { writePending(plan) }
                runDownload(plan)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                core.log.w("VelaRegion", "$regionId: could not prepare download", e)
                _state.update {
                    it.copy(downloadingId = null, downloadStage = "", errorKey = "download_failed")
                }
            }
        }
    }

    private fun makePlan(regionId: String): PendingRegionDownload? {
        val region = routing.firstOrNull { it.id == regionId } ?: return null
        val installedPackIds = installedPackIds()
        val pack = RegionPacks.packFor(region, packs, installedPackIds)
            ?.takeIf { RegionPacks.autoWith(region, it) }
        val placeArchives = archivesFor(region, places)
        val mapArchives = archivesFor(region, maps)
        check(mapArchives.isNotEmpty()) { "no basemap" }
        val assets = ArrayList<OfflineAssetPlan>()
        if (pack != null) {
            assets += OfflineAssetPlan(
                pack.id, KIND_PACK, pack.url, joinPath(packsPath, "${safeId(pack.id)}.db"))
        }
        for (archive in placeArchives) {
            assets += OfflineAssetPlan(
                archive.id, KIND_PLACES, archive.url, joinPath(placesPath, "${safeId(archive.id)}.pmtiles"))
        }
        if (!glyphsInstalled()) {
            assets += OfflineAssetPlan("map-fonts", KIND_GLYPHS, VelaLinks.mapFontsPack(), glyphsPath)
        }
        for (archive in mapArchives) {
            assets += OfflineAssetPlan(
                archive.id, KIND_BASEMAP, archive.url, joinPath(basemapPath, "${safeId(archive.id)}.pmtiles"))
        }
        return PendingRegionDownload(
            record = InstalledRegion(
                id = region.id,
                packId = pack?.id,
                places = placeArchives.map(::installedArchive),
                maps = mapArchives.map(::installedArchive),
            ),
            assets = assets,
        )
    }

    private suspend fun runDownload(plan: PendingRegionDownload) {
        val regionId = plan.record.id
        _state.update {
            it.copy(
                downloadingId = regionId, downloadStage = "", downloadProgress = 0,
                downloadCompletedPieces = 0, downloadPieceCount = plan.assets.size,
                completedId = null, errorKey = null,
            )
        }
        try {
            for ((index, asset) in plan.assets.withIndex()) {
                installAsset(asset)
                _state.update { it.copy(downloadCompletedPieces = index + 1) }
            }
            withContext(ioDispatcher) {
                writeInstalled(plan.record)
                registerPacks()
                files.delete(pendingPath)
            }
            installed = installed + (regionId to plan.record)
            pending = null
            rebuildRegions()
            updateStorage()
            RoadNameTiles.clearCache()
            _state.update {
                it.copy(
                    downloadingId = null, downloadStage = "", downloadProgress = 100,
                    completedId = regionId, revision = it.revision + 1,
                )
            }
            core.log.i("VelaRegion", "$regionId: installed")
            // Best effort and after the completion, so a slow or dead Overpass mirror never delays
            // or fails a region install. No pack is a valid result and the sheet says so.
            scope.launch { writeCameraPack(regionId) }
        } catch (e: CancellationException) {
            withContext(NonCancellable + ioDispatcher) { files.delete(pendingPath) }
            pending = null
            _state.update {
                it.copy(
                    downloadingId = null, downloadStage = "", downloadProgress = 0,
                    downloadCompletedPieces = 0, downloadPieceCount = 0,
                )
            }
            throw e
        } catch (e: Throwable) {
            val failed = plan.copy(failed = true)
            pending = failed
            runCatching { withContext(ioDispatcher) { writePending(failed) } }
            core.log.w("VelaRegion", "$regionId: download failed", e)
            _state.update {
                it.copy(
                    downloadingId = null, downloadStage = "", downloadProgress = 0,
                    errorKey = "download_failed",
                )
            }
        }
    }

    fun cancelDownload() {
        // Clear the durable intent before the asynchronous task cancellation, so an immediate
        // process kill cannot turn a user's Cancel into an automatic retry on the next launch.
        pending = null
        files.delete(pendingPath)
        downloadJob?.cancel()
    }

    fun delete(regionId: String) {
        if (downloadJob?.isActive == true) return
        val old = installed[regionId] ?: return
        val remaining = installed - regionId
        scope.launch {
            withContext(ioDispatcher) {
                val usedPacks = remaining.values.mapNotNull { it.packId }.toSet()
                val usedPlaces = remaining.values.flatMap { it.places }.map { it.id }.toSet()
                val usedMaps = remaining.values.flatMap { it.maps }.map { it.id }.toSet()
                old.packId?.takeIf { it !in usedPacks }?.let { files.delete(joinPath(packsPath, "${safeId(it)}.db")) }
                old.places.filter { it.id !in usedPlaces }.forEach {
                    files.delete(joinPath(placesPath, "${safeId(it.id)}.pmtiles"))
                }
                old.maps.filter { it.id !in usedMaps }.forEach {
                    files.delete(joinPath(basemapPath, "${safeId(it.id)}.pmtiles"))
                }
                files.delete(joinPath(regionsPath, "${safeId(regionId)}.json"))
                files.delete(joinPath(cameraPacksPath, "${safeId(regionId)}.json"))
                registerPacks()
            }
            installed = remaining
            RoadNameTiles.clearCache()
            rebuildRegions()
            updateStorage()
            _state.update { it.copy(completedId = null, revision = it.revision + 1) }
        }
    }

    /** The installed archive whose actual z12 roads reach this point, else null. */
    fun localBasemapPath(lat: Double, lng: Double): String? {
        val p = LatLng(lat, lng)
        val candidates = installed.values.flatMap { it.maps }.distinctBy { it.id }
            .filter { it.contains(p) }.sortedBy { it.area }
        var unreadable: String? = null
        for (archive in candidates) {
            val path = joinPath(basemapPath, "${safeId(archive.id)}.pmtiles")
            if (!files.exists(path)) continue
            val (x, y) = PmtilesReader.tileOf(lat, lng, COVERAGE_Z)
            when (PmtilesReader.hasRoads(path, COVERAGE_Z, x, y)) {
                true -> return path
                null -> if (unreadable == null) unreadable = path
                false -> Unit
            }
        }
        return unreadable
    }

    /** Place packs, places archives and typed-address geocoding, ranked together off the main thread. */
    override suspend fun search(query: String, near: LatLng?): List<Place> = withContext(ioDispatcher) {
        val extra = near?.let { point ->
            val paths = installed.values.flatMap { it.places }.distinctBy { it.id }
                .filter { it.contains(point) }.sortedBy { it.area }
                .map { joinPath(placesPath, "${safeId(it.id)}.pmtiles") }
                .filter { files.exists(it) }
            PlacesArchiveSearch.search(paths, point, query) { path ->
                PmtilesReader.Archive.file(path, files.size(path), files.lastModifiedMillis(path))
            }
        }.orEmpty()
        val pois = runCatching { poiStore.search(query, near, extra = extra) }.getOrDefault(emptyList())
        val addresses = if (OfflineAddressStore.looksLikeAddress(query)) {
            runCatching { addressStore.geocode(query, near) }.getOrDefault(emptyList())
        } else emptyList()
        (if (addresses.isNotEmpty()) addresses + pois else pois + addresses).distinctBy { it.id }
    }

    /** Local archives answer first, exactly as Android's RoadNameTileSource, then OpenFreeMap. */
    private fun installRoadNameSource() {
        val online = RoadNameTiles.fetch
        RoadNameTiles.fetch = { z, x, y ->
            withContext(ioDispatcher) {
                val paths = installed.values.flatMap { it.maps }.distinctBy { it.id }
                    .map { joinPath(basemapPath, "${safeId(it.id)}.pmtiles") }
                    .filter { files.exists(it) }
                roadTile(paths, z, x, y) { online?.invoke(z, x, y) }
            }
        }
        RoadNameTiles.clearCache()
    }

    private suspend fun installAsset(asset: OfflineAssetPlan) {
        if (withContext(ioDispatcher) { valid(asset.kind, asset.targetPath) }) return
        _state.update { it.copy(downloadStage = asset.kind, downloadProgress = 0) }
        withContext(ioDispatcher) {
            if (asset.kind == KIND_GLYPHS) files.mkdirs(rootPath)
            else files.mkdirs(asset.targetPath.substringBeforeLast('/'))
        }
        suspendCancellableCoroutine<Unit> { continuation ->
            var call: Cancellable? = null
            var finished = false
            call = downloader.start(
                id = asset.id,
                kind = asset.kind,
                url = asset.url,
                targetPath = asset.targetPath,
                onProgress = { received, total ->
                    val pct = if (total > 0) (received * 100 / total).toInt().coerceIn(0, 99) else 0
                    _state.update { it.copy(downloadProgress = pct) }
                },
                onComplete = { error ->
                    if (!finished) {
                        finished = true
                        if (error == null) continuation.resume(Unit)
                        else continuation.resumeWith(Result.failure(OfflineAssetException(error)))
                    }
                },
            )
            continuation.invokeOnCancellation {
                finished = true
                call.cancel()
            }
        }
        check(withContext(ioDispatcher) { valid(asset.kind, asset.targetPath) }) { "invalid ${asset.kind}" }
        _state.update { it.copy(downloadProgress = 100) }
    }

    /** The final trap after Swift's status, byte-count, magic and ZIP CRC checks. */
    private fun valid(kind: String, path: String): Boolean = when (kind) {
        KIND_PACK -> files.size(path) > 16 && runCatching {
            sql.openReadOnly(path).close()
            true
        }.getOrDefault(false)
        KIND_PLACES, KIND_BASEMAP -> files.size(path) > 127 && PmtilesReader.header(path) != null
        KIND_GLYPHS -> files.size(joinPath(path, "Noto Sans Regular", "0-255.pbf")) > 0
        else -> false
    }

    private fun glyphsInstalled() = files.size(joinPath(glyphsPath, "Noto Sans Regular", "0-255.pbf")) > 0

    private fun registerPacks() {
        val paths = files.list(packsPath).orEmpty()
            .filter { !it.isDirectory && it.name.endsWith(".db") && valid(KIND_PACK, it.path) }
            .map { it.path }
        OfflinePacks.reload(sql, paths)
    }

    /**
     * Writes `<region>.json` under `camera-packs` with the speed and plate cameras Overpass
     * returns for the region bbox, capped at [CAMERA_PACK_LIMIT] per kind. It runs after the
     * region is usable, never blocks it, and a failed query writes nothing: an empty file would
     * claim "no cameras here" when the truth is "no answer".
     */
    private suspend fun writeCameraPack(regionId: String) {
        val region = routing.firstOrNull { it.id == regionId } ?: return
        if (region.e - region.w > CAMERA_PACK_MAX_SPAN || region.n - region.s > CAMERA_PACK_MAX_SPAN) {
            core.log.i("VelaRegion", "$regionId: camera pack skipped, region spans more than $CAMERA_PACK_MAX_SPAN degrees")
            return
        }
        val speed = runCatching {
            OverpassSpeedCameras.fetchInBox(
                core.http, region.s, region.w, region.n, region.e, limit = CAMERA_PACK_LIMIT)
        }.getOrNull()
        val alpr = runCatching {
            OverpassAlprCameras.fetchInBox(
                core.http, region.s, region.w, region.n, region.e, limit = CAMERA_PACK_LIMIT)
        }.getOrNull()
        if (speed == null && alpr == null) {
            core.log.i("VelaRegion", "$regionId: camera pack not written, no Overpass answer")
            return
        }
        val cameras = buildList {
            speed.orEmpty().forEach { add(RegionCamera(packCoord(it.loc.lat), packCoord(it.loc.lng), "speed")) }
            alpr.orEmpty().forEach { add(RegionCamera(packCoord(it.loc.lat), packCoord(it.loc.lng), "alpr")) }
        }.distinct()
        val now = core.clock.nowMillis()
        val pack = RegionCameraPack(
            id = region.id, name = "region-${region.id}-$now",
            generatedAtMs = now,
            s = region.s, w = region.w, n = region.n, e = region.e, cameras = cameras,
        )
        withContext(ioDispatcher) {
            files.mkdirs(cameraPacksPath)
            files.writeTextAtomic(
                joinPath(cameraPacksPath, "${safeId(region.id)}.json"),
                json.encodeToString(RegionCameraPack.serializer(), pack),
            )
        }
        core.log.i("VelaRegion", "$regionId: camera pack ${cameras.size} written")
    }

    private fun readInstalled(): Map<String, InstalledRegion> = files.list(regionsPath).orEmpty()
        .filter { !it.isDirectory && it.name.endsWith(".json") }
        .mapNotNull { entry ->
            runCatching { json.decodeFromString<InstalledRegion>(files.readText(entry.path)) }.getOrNull()
        }.associateBy { it.id }

    private fun writeInstalled(record: InstalledRegion) {
        files.mkdirs(regionsPath)
        files.writeTextAtomic(
            joinPath(regionsPath, "${safeId(record.id)}.json"),
            json.encodeToString(InstalledRegion.serializer(), record),
        )
    }

    private fun readPending(): PendingRegionDownload? = runCatching {
        if (!files.exists(pendingPath)) return null
        json.decodeFromString<PendingRegionDownload>(files.readText(pendingPath))
    }.getOrNull()

    private fun writePending(plan: PendingRegionDownload) {
        files.mkdirs(rootPath)
        files.writeTextAtomic(
            pendingPath, json.encodeToString(PendingRegionDownload.serializer(), plan))
    }

    private fun installedPackIds(): Set<String> = files.list(packsPath).orEmpty()
        .filter { !it.isDirectory && it.name.endsWith(".db") && valid(KIND_PACK, it.path) }
        .map { it.name.removeSuffix(".db") }.toSet()

    private fun rebuildRegions() {
        val rows = routing.map { region ->
            val pack = RegionPacks.packFor(region, packs)
            val packMb = pack?.let { if (it.installedMb > 0) it.installedMb else (it.sizeMb * 2.35).roundToInt() } ?: 0
            val archiveMb = (archivesFor(region, places) + archivesFor(region, maps)).sumOf { it.sizeMb }
            OfflineRegion(region.id, region.name, (packMb + archiveMb).coerceAtLeast(1), region.id in installed)
        }.sortedBy { it.name.lowercase() }
        _state.update { it.copy(regions = rows) }
        updateCurrentRegion()
    }

    private fun updateCurrentRegion() {
        val at = myLocation
        val current = at?.let { p -> routing.filter { it.covers(p.lat, p.lng) }.minByOrNull { it.boxArea() }?.id }
        _state.update { it.copy(currentRegionId = current) }
    }

    private suspend fun updateStorage() {
        val sizes = withContext(ioDispatcher) {
            val packIds = installed.values.mapNotNull { it.packId }.toSet()
            val placeIds = installed.values.flatMap { it.places }.map { it.id }.toSet()
            val mapIds = installed.values.flatMap { it.maps }.map { it.id }.toSet()
            StorageSizes(
                packIds.sumOf { files.size(joinPath(packsPath, "${safeId(it)}.db")) },
                placeIds.sumOf { files.size(joinPath(placesPath, "${safeId(it)}.pmtiles")) },
                mapIds.sumOf { files.size(joinPath(basemapPath, "${safeId(it)}.pmtiles")) },
                files.treeSize(glyphsPath),
                files.treeSize(rootPath),
            )
        }
        _state.update {
            it.copy(
                packBytes = sizes.packs, placesBytes = sizes.places, basemapBytes = sizes.maps,
                glyphBytes = sizes.glyphs, totalBytes = sizes.total,
            )
        }
    }

    private data class StorageSizes(
        val packs: Long,
        val places: Long,
        val maps: Long,
        val glyphs: Long,
        val total: Long,
    )

    private class OfflineAssetException(message: String) : Exception(message)

    internal companion object {
        const val KIND_PACK = "pack"
        const val KIND_PLACES = "places"
        const val KIND_BASEMAP = "basemap"
        const val KIND_GLYPHS = "glyphs"
        private const val COVERAGE_Z = 12
        /** At most this many speed and plate cameras in one region pack, per kind. */
        const val CAMERA_PACK_LIMIT = 2000
        /** Larger boxes are not queried in one Overpass call; no pack is written for them. */
        const val CAMERA_PACK_MAX_SPAN = 12.0

        /** Five decimals is about one metre; it keeps the pack file small. */
        fun packCoord(v: Double): Double = (v * 100_000).roundToInt() / 100_000.0

        internal suspend fun roadTile(
            paths: List<String>,
            z: Int,
            x: Int,
            y: Int,
            read: (String, Int, Int, Int) -> ByteArray? = PmtilesReader::tileBytes,
            online: suspend () -> ByteArray?,
        ): ByteArray? {
            for (path in paths) read(path, z, x, y)?.let { return it }
            return online()
        }

        /** The same own-id, contained-pieces, covering-parent choice as Android's archivesFor. */
        fun archivesFor(region: RoutingRegion, archives: List<RoutingRegion>): List<RoutingRegion> {
            archives.firstOrNull { it.id == region.id }?.let { return listOf(it) }
            val inside = archives.filter {
                region.covers((it.s + it.n) / 2, (it.w + it.e) / 2)
            }
            return inside.ifEmpty {
                listOfNotNull(
                    archives.filter { it.covers((region.s + region.n) / 2, (region.w + region.e) / 2) }
                        .minByOrNull { it.boxArea() },
                )
            }
        }

        private fun installedArchive(region: RoutingRegion) = InstalledArchive(region.id, region.s, region.w, region.n, region.e)

        private fun safeId(id: String): String {
            require(id.isNotEmpty() && id.all { it.isLetterOrDigit() || it == '_' || it == '-' }) { "unsafe region id" }
            return id
        }
    }
}
