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
import app.vela.core.offline.PackDelta
import app.vela.core.offline.PlacesArchiveSearch
import app.vela.core.offline.PmtilesCompact
import app.vela.core.offline.PmtilesPatch
import app.vela.core.offline.PmtilesReader
import app.vela.core.offline.RegionCatalog
import app.vela.core.offline.RegionPacks
import app.vela.core.offline.RegionPolys
import app.vela.core.offline.RoutingRegion
import app.vela.core.platform.Cancellable
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.SqlDb
import app.vela.core.platform.SqlDbs
import app.vela.core.platform.i
import app.vela.core.platform.joinPath
import app.vela.core.platform.queryLong
import app.vela.core.platform.treeSize
import app.vela.core.platform.usableSpace
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
    val installedBytes: Long = 0,
    val updateMb: Int = 0,
    val updatable: Boolean = false,
)

/** One region's actual footprint: the pieces it owns and their sum. Glyphs are shared. */
data class OfflineRegionBytes(
    val id: String,
    val packBytes: Long,
    val placesBytes: Long,
    val basemapBytes: Long,
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
    val regionBytes: List<OfflineRegionBytes> = emptyList(),
    val worldInstalled: Boolean = false,
    val updatingId: String? = null,
    val updatedId: String? = null,
    val updateDeltaPieces: Int = 0,
    val updateFullPieces: Int = 0,
    /** The region an area job targets; non-null from confirmation until the next start. */
    val areaId: String? = null,
    val areaPlaces: Boolean = true,
    val areaCameras: Boolean = true,
    val areaAddresses: Boolean = true,
    /** Rows written by the last area extras; -1 means the fetch failed or was skipped. */
    val areaCameraRows: Int = -1,
    val areaAddressRows: Int = -1,
    val areaDataStage: String = "",
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
    /** Manifest revision this piece installs; 0 when the catalog does not publish one. */
    val rev: Int = 0,
    /** The optional delta from [deltaFromRev] to [rev]. */
    val deltaUrl: String? = null,
    val deltaFromRev: Int = 0,
    /** Where the downloaded delta body lands before it is applied. */
    val deltaPath: String = "",
    /** Expected row counts, verifying a place-pack apply. */
    val counts: Map<String, Long> = emptyMap(),
    /** Manifest download size, used only for the free-space check. */
    val sizeMb: Int = 0,
    /** The world basemap is a floor under the map: failing it never fails the region. */
    val optional: Boolean = false,
    /** True when this plan replaces an installed file instead of skipping a valid one. */
    val replace: Boolean = false,
)

/** The whole region plan, not just its current task, so a new process can finish the sequence. */
@Serializable
internal data class PendingRegionDownload(
    val record: InstalledRegion,
    val assets: List<OfflineAssetPlan>,
    val failed: Boolean = false,
    /** An area picker job: the extras below run after the map pieces are installed. */
    val area: Boolean = false,
    val cameras: Boolean = false,
    val addresses: Boolean = false,
    /** The padded frame the address index covers; zeroes when addresses are off. */
    val addressS: Double = 0.0,
    val addressW: Double = 0.0,
    val addressN: Double = 0.0,
    val addressE: Double = 0.0,
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

/** Installed revisions per store folder, the iOS counterpart of Android's `revs.json`. */
@Serializable
internal data class InstalledRevisions(
    val packs: Map<String, Int> = emptyMap(),
    val places: Map<String, Int> = emptyMap(),
    val maps: Map<String, Int> = emptyMap(),
) {
    fun get(kind: String, id: String): Int = when (kind) {
        OfflineStore.KIND_PACK -> packs[id]
        OfflineStore.KIND_PLACES -> places[id]
        OfflineStore.KIND_BASEMAP -> maps[id]
        else -> null
    } ?: 0

    fun with(kind: String, id: String, rev: Int): InstalledRevisions = when (kind) {
        OfflineStore.KIND_PACK -> copy(packs = packs + (id to rev))
        OfflineStore.KIND_PLACES -> copy(places = places + (id to rev))
        OfflineStore.KIND_BASEMAP -> copy(maps = maps + (id to rev))
        else -> this
    }

    fun without(kind: String, id: String): InstalledRevisions = when (kind) {
        OfflineStore.KIND_PACK -> copy(packs = packs - id)
        OfflineStore.KIND_PLACES -> copy(places = places - id)
        OfflineStore.KIND_BASEMAP -> copy(maps = maps - id)
        else -> this
    }
}

/**
 * The offline facet of MapSession: region catalogs, downloads, updates, installed files and local
 * search. iOS deliberately does not fetch the OBF row: its manifest is only the shared region
 * catalog. Construction is inert. [start] opens installed packs, reads the cached catalog and
 * refreshes it.
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
    private val revisionsPath = joinPath(rootPath, "revs.json")
    val worldPath: String = joinPath(basemapPath, "$WORLD_ID.pmtiles")

    private val _state = MutableStateFlow(OfflineState())
    val state: StateFlow<OfflineState> = _state.asStateFlow()

    private var started = false
    private var refreshJob: Job? = null
    private var downloadJob: Job? = null
    private var extrasJob: Job? = null
    private var routing = emptyList<RoutingRegion>()
    private var packs = emptyList<RoutingRegion>()
    private var places = emptyList<RoutingRegion>()
    private var maps = emptyList<RoutingRegion>()
    private var worldUrl = VelaLinks.worldBasemap()
    private var mapFontsUrl = VelaLinks.mapFontsPack()
    private var fixtureCatalogs = false
    @Volatile private var installed = emptyMap<String, InstalledRegion>()
    private var revisions = InstalledRevisions()
    private var pending: PendingRegionDownload? = null
    private var myLocation: LatLng? = null

    @Volatile private var network = true
    @Volatile private var testOffline = false

    fun start() {
        if (started) return
        started = true
        network = true
        setGoogleDisabled(settings.getBoolean(SettingsStore.GOOGLE_DISABLED_KEY, false), persist = false)
        val preferences = areaPreferences()
        _state.update {
            it.copy(
                areaPlaces = preferences.places,
                areaCameras = preferences.cameras,
                areaAddresses = preferences.addresses,
            )
        }
        scope.launch {
            installed = withContext(ioDispatcher) { readInstalled() }
            revisions = withContext(ioDispatcher) { readRevisions() }
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
            if (pending?.area == true) {
                _state.update { it.copy(areaId = pending?.record?.id) }
            }
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
        if (fixtureCatalogs) return
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

    /**
     * Debug UI fixtures only: remove every installed offline file so a fixture run starts from an
     * empty store even when the simulator kept data from a previous test. Production code never
     * calls it.
     */
    fun resetForFixture() {
        files.deleteRecursively(rootPath)
        installed = emptyMap()
        revisions = InstalledRevisions()
        pending = null
        OfflinePacks.clear()
        _state.value = OfflineState()
    }

    /**
     * Debug UI fixtures only: the four catalogs and the world address, already fetched by the
     * caller, replace the network manifests for this process. Production code never calls it.
     */
    fun useFixtureCatalogs(
        routingJson: String,
        packsJson: String,
        placesJson: String,
        mapsJson: String,
        worldUrl: String? = null,
        glyphUrl: String? = null,
    ) {
        fixtureCatalogs = true
        routing = RegionCatalog.parseManifest(routingJson)
        packs = RegionCatalog.parseManifest(packsJson)
        places = RegionCatalog.parseManifest(placesJson)
        maps = RegionCatalog.parseManifest(mapsJson)
        if (worldUrl != null) this.worldUrl = worldUrl
        if (glyphUrl != null) this.mapFontsUrl = glyphUrl
        rebuildRegions()
        scope.launch { updateStorage() }
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
        val wasOffline = offlineOnly()
        network = available
        _state.update { it.copy(networkAvailable = available && !testOffline) }
        if (wasOffline != offlineOnly()) bumpRevision()
    }

    /** Debug UI scenario: stays offline even if NWPathMonitor publishes another path update. */
    fun setOfflineTestMode(enabled: Boolean) {
        val wasOffline = offlineOnly()
        testOffline = enabled
        _state.update { it.copy(networkAvailable = network && !enabled) }
        if (wasOffline != offlineOnly()) bumpRevision()
    }

    fun setGoogleDisabled(disabled: Boolean) = setGoogleDisabled(disabled, persist = true)

    private fun setGoogleDisabled(disabled: Boolean, persist: Boolean) {
        val wasOffline = offlineOnly()
        NoGoogle.enabled = disabled
        if (persist) settings.edit().putBoolean(SettingsStore.GOOGLE_DISABLED_KEY, disabled).apply()
        _state.update { it.copy(googleDisabled = disabled) }
        if (started && wasOffline != offlineOnly()) bumpRevision()
    }

    override fun offlineOnly(): Boolean = NoGoogle.enabled || !network || testOffline

    private fun bumpRevision() = _state.update { it.copy(revision = it.revision + 1) }

    // Area download preferences. The places key is Android's `offline_places_with_downloads`, so a
    // settings file written by either app stays valid. The other two are iOS-only and default on.

    fun areaPreferences(): OfflineAreaPreferences = OfflineAreaPreferences(
        places = settings.getBoolean(OfflineAreaPreferences.KEY_PLACES, true),
        cameras = settings.getBoolean(OfflineAreaPreferences.KEY_CAMERAS, true),
        addresses = settings.getBoolean(OfflineAreaPreferences.KEY_ADDRESSES, true),
    )

    fun setAreaPlaces(enabled: Boolean) {
        settings.edit().putBoolean(OfflineAreaPreferences.KEY_PLACES, enabled).apply()
        _state.update { it.copy(areaPlaces = enabled) }
    }

    fun setAreaCameras(enabled: Boolean) {
        settings.edit().putBoolean(OfflineAreaPreferences.KEY_CAMERAS, enabled).apply()
        _state.update { it.copy(areaCameras = enabled) }
    }

    fun setAreaAddresses(enabled: Boolean) {
        settings.edit().putBoolean(OfflineAreaPreferences.KEY_ADDRESSES, enabled).apply()
        _state.update { it.copy(areaAddresses = enabled) }
    }

    /** The smallest catalog region that owns the point, the same choice as `currentRegionId`. */
    private fun regionFor(lat: Double, lng: Double): RoutingRegion? =
        routing.filter { it.covers(lat, lng) }.minByOrNull { it.boxArea() }

    /**
     * The picker's estimate for the frame. iOS downloads whole catalog regions, not a square of
     * tiles, so the estimate is the manifest size of the pieces the frame's region really needs,
     * marked as an estimate in the sheet. Already valid files are not counted twice. Construction
     * is read-only; the only work is a header check on the installed pieces.
     */
    suspend fun planArea(south: Double, west: Double, north: Double, east: Double): OfflineAreaPlan {
        val bounds = OfflineArea.framedBounds(south, west, north, east)
        val preferences = areaPreferences()
        val free = withContext(ioDispatcher) { files.mkdirs(rootPath); usableSpace(rootPath) }
        val region = regionFor(bounds.centerLat, bounds.centerLng)
        if (region == null) {
            return OfflineAreaPlan(
                regionId = null, regionName = "", installed = false, estimatedMb = 0,
                neededBytes = 0, freeBytes = free, fits = false, tooLarge = false,
                reasonKey = OfflineAreaGate.NO_REGION,
                south = bounds.south, west = bounds.west, north = bounds.north, east = bounds.east,
                placesIncluded = preferences.places, camerasIncluded = preferences.cameras,
                addressesIncluded = preferences.addresses && OfflineArea.addressBounds(bounds) != null,
            )
        }
        val existing = installed[region.id]
        val assets = withContext(ioDispatcher) { areaAssets(region, preferences, existing) }
        val needed = OfflineStorage.neededBytes(assets)
        val extras = OfflineArea.extras(preferences).isNotEmpty()
        return OfflineAreaPlan(
            regionId = region.id,
            regionName = region.name,
            installed = existing != null,
            estimatedMb = (needed / MEGABYTE).toInt(),
            neededBytes = needed,
            freeBytes = free,
            fits = OfflineStorage.fits(free, needed),
            tooLarge = false,
            reasonKey = OfflineAreaGate.reason(free, needed, existing != null, extras),
            south = bounds.south, west = bounds.west, north = bounds.north, east = bounds.east,
            placesIncluded = preferences.places,
            camerasIncluded = preferences.cameras,
            addressesIncluded = preferences.addresses && OfflineArea.addressBounds(bounds) != null,
        )
    }

    /**
     * Downloads the region that covers the frame with the chosen pieces, then the network extras
     * the downloader really supports: the camera pack for the region and the street-address index
     * for the frame. The plan is durable, so leaving the picker, closing the sheet or killing the
     * process does not lose the download. Offline routing is not part of it; the sheet says so.
     */
    fun downloadArea(south: Double, west: Double, north: Double, east: Double) {
        if (!started || downloadJob?.isActive == true) return
        val preferences = areaPreferences()
        downloadJob = scope.launch {
            try {
                val bounds = OfflineArea.framedBounds(south, west, north, east)
                val region = regionFor(bounds.centerLat, bounds.centerLng)
                if (region == null) {
                    _state.update { it.copy(errorKey = OfflineAreaGate.NO_REGION, areaId = null) }
                    return@launch
                }
                val existing = installed[region.id]
                val addressBounds = if (preferences.addresses) OfflineArea.addressBounds(bounds) else null
                val assets = withContext(ioDispatcher) { areaAssets(region, preferences, existing) }
                val needed = OfflineStorage.neededBytes(assets)
                val free = withContext(ioDispatcher) { files.mkdirs(rootPath); usableSpace(rootPath) }
                if (!OfflineStorage.fits(free, needed)) {
                    core.log.w("VelaArea", "${region.id}: needs $needed bytes, $free free")
                    _state.update { it.copy(errorKey = OfflineAreaGate.NO_SPACE, areaId = region.id) }
                    return@launch
                }
                val plan = PendingRegionDownload(
                    record = areaRecord(region, preferences, existing),
                    assets = assets,
                    area = true,
                    cameras = preferences.cameras,
                    addresses = addressBounds != null,
                    addressS = addressBounds?.south ?: 0.0,
                    addressW = addressBounds?.west ?: 0.0,
                    addressN = addressBounds?.north ?: 0.0,
                    addressE = addressBounds?.east ?: 0.0,
                )
                pending = plan
                withContext(ioDispatcher) { writePending(plan) }
                _state.update {
                    it.copy(
                        areaId = region.id, areaCameraRows = -1, areaAddressRows = -1,
                        areaDataStage = "", errorKey = null,
                    )
                }
                runDownload(plan)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                core.log.w("VelaArea", "could not prepare the area download", e)
                _state.update { it.copy(downloadingId = null, downloadStage = "", errorKey = "download_failed") }
            }
        }
    }

    /** The assets the frame's region needs for [preferences], skipping files already valid. */
    private fun areaAssets(
        region: RoutingRegion,
        preferences: OfflineAreaPreferences,
        existing: InstalledRegion?,
    ): List<OfflineAssetPlan> {
        val candidates = ArrayList<OfflineAssetPlan>()
        val packIds = installedPackIds()
        val pack = if (preferences.places) {
            RegionPacks.packFor(region, packs, packIds)?.takeIf { RegionPacks.autoWith(region, it) }
        } else packs.firstOrNull { it.id == existing?.packId }
        if (pack != null) {
            candidates += OfflineAssetPlan(
                pack.id, KIND_PACK, pack.url, joinPath(packsPath, "${safeId(pack.id)}.db"),
                rev = pack.rev, sizeMb = pack.sizeMb, counts = pack.counts,
                deltaUrl = pack.deltaUrl, deltaFromRev = pack.deltaFromRev,
            )
        }
        if (preferences.places) {
            for (archive in archivesFor(region, places)) {
                candidates += OfflineAssetPlan(
                    archive.id, KIND_PLACES, archive.url,
                    joinPath(placesPath, "${safeId(archive.id)}.pmtiles"),
                    rev = archive.rev, sizeMb = archive.sizeMb,
                    deltaUrl = archive.deltaUrl, deltaFromRev = archive.deltaFromRev,
                )
            }
        }
        if (!glyphsInstalled()) {
            candidates += OfflineAssetPlan("map-fonts", KIND_GLYPHS, mapFontsUrl, glyphsPath)
        }
        for (archive in archivesFor(region, maps)) {
            candidates += OfflineAssetPlan(
                archive.id, KIND_BASEMAP, archive.url,
                joinPath(basemapPath, "${safeId(archive.id)}.pmtiles"),
                rev = archive.rev, sizeMb = archive.sizeMb,
                deltaUrl = archive.deltaUrl, deltaFromRev = archive.deltaFromRev,
            )
        }
        if (!worldInstalled()) {
            candidates += OfflineAssetPlan(
                WORLD_ID, KIND_BASEMAP, worldUrl, worldPath, optional = true, sizeMb = WORLD_ESTIMATED_MB)
        }
        return candidates.filterNot { valid(it.kind, it.targetPath) }
    }

    private fun areaRecord(
        region: RoutingRegion,
        preferences: OfflineAreaPreferences,
        existing: InstalledRegion?,
    ): InstalledRegion {
        val packIds = installedPackIds()
        val pack = if (preferences.places) {
            RegionPacks.packFor(region, packs, packIds)?.takeIf { RegionPacks.autoWith(region, it) }
        } else packs.firstOrNull { it.id == existing?.packId }
        val placeArchives = if (preferences.places) archivesFor(region, places) else emptyList()
        return InstalledRegion(
            id = region.id,
            packId = pack?.id ?: existing?.packId,
            places = (existing?.places.orEmpty() + placeArchives.map(::installedArchive)).distinctBy { it.id },
            maps = (existing?.maps.orEmpty() + archivesFor(region, maps).map(::installedArchive)).distinctBy { it.id },
        )
    }


    /** Downloads one persisted plan. Every asset and the final marker survive process death. */
    fun download(regionId: String) {
        if (!started || downloadJob?.isActive == true || installed.containsKey(regionId)) return
        if (pending?.failed == false && pending != null) return
        downloadJob = scope.launch {
            try {
                val plan = pending?.takeIf { it.record.id == regionId }?.copy(failed = false)
                    ?: withContext(ioDispatcher) { makePlan(regionId) } ?: return@launch
                val free = withContext(ioDispatcher) { files.mkdirs(rootPath); usableSpace(rootPath) }
                if (!OfflineStorage.fits(free, OfflineStorage.neededBytes(plan.assets))) {
                    core.log.w("VelaRegion", "$regionId: needs ${OfflineStorage.neededBytes(plan.assets)} bytes, $free free")
                    _state.update {
                        it.copy(downloadingId = null, downloadStage = "", errorKey = "no_space")
                    }
                    return@launch
                }
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

    /**
     * Updates an installed region piece by piece. A piece whose installed revision matches the
     * published delta's `fromRev` takes the delta; every other piece, and every refused delta, is
     * re-downloaded whole. Installed files stay valid until a replacement or a patch is proven.
     */
    fun update(regionId: String) {
        if (!started || downloadJob?.isActive == true || !installed.containsKey(regionId)) return
        downloadJob = scope.launch {
            try {
                val assets = withContext(ioDispatcher) { makeUpdatePlan(regionId) }
                if (assets.isEmpty()) return@launch
                val free = withContext(ioDispatcher) { files.mkdirs(rootPath); usableSpace(rootPath) }
                if (!OfflineStorage.fits(free, OfflineStorage.neededBytes(assets))) {
                    _state.update { it.copy(updatingId = null, errorKey = "no_space") }
                    return@launch
                }
                runUpdate(regionId, assets)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                core.log.w("VelaRegion", "$regionId: could not prepare update", e)
                _state.update { it.copy(updatingId = null, errorKey = "download_failed") }
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
                pack.id, KIND_PACK, pack.url, joinPath(packsPath, "${safeId(pack.id)}.db"),
                rev = pack.rev, sizeMb = pack.sizeMb,
                counts = pack.counts, deltaUrl = pack.deltaUrl,
                deltaFromRev = pack.deltaFromRev, deltaPath = "",
            )
        }
        for (archive in placeArchives) {
            assets += OfflineAssetPlan(
                archive.id, KIND_PLACES, archive.url,
                joinPath(placesPath, "${safeId(archive.id)}.pmtiles"),
                rev = archive.rev, sizeMb = archive.sizeMb,
                deltaUrl = archive.deltaUrl, deltaFromRev = archive.deltaFromRev,
            )
        }
        if (!glyphsInstalled()) {
            assets += OfflineAssetPlan("map-fonts", KIND_GLYPHS, mapFontsUrl, glyphsPath)
        }
        for (archive in mapArchives) {
            assets += OfflineAssetPlan(
                archive.id, KIND_BASEMAP, archive.url,
                joinPath(basemapPath, "${safeId(archive.id)}.pmtiles"),
                rev = archive.rev, sizeMb = archive.sizeMb,
                deltaUrl = archive.deltaUrl, deltaFromRev = archive.deltaFromRev,
            )
        }
        if (!worldInstalled()) {
            assets += OfflineAssetPlan(
                WORLD_ID, KIND_BASEMAP, worldUrl, worldPath, optional = true, sizeMb = WORLD_ESTIMATED_MB)
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

    /** Every installed piece whose manifest revision moved, with its delta when it is applicable. */
    private fun makeUpdatePlan(regionId: String): List<OfflineAssetPlan> {
        val record = installed[regionId] ?: return emptyList()
        val out = ArrayList<OfflineAssetPlan>()
        record.packId?.let { id ->
            val row = packs.firstOrNull { it.id == id } ?: return@let
            val have = revisions.get(KIND_PACK, id)
            if (row.rev > have) {
                out += OfflineAssetPlan(
                    id, KIND_PACK, row.url, joinPath(packsPath, "${safeId(id)}.db"),
                    rev = row.rev, sizeMb = row.sizeMb, counts = row.counts,
                    deltaUrl = OfflineUpdates.deltaUrl(have, row),
                    deltaFromRev = row.deltaFromRev,
                    deltaPath = joinPath(packsPath, "${safeId(id)}.delta.db"),
                    replace = true,
                )
            }
        }
        for (archive in record.places) {
            val row = places.firstOrNull { it.id == archive.id } ?: continue
            val have = revisions.get(KIND_PLACES, archive.id)
            if (row.rev > have) {
                out += OfflineAssetPlan(
                    archive.id, KIND_PLACES, row.url,
                    joinPath(placesPath, "${safeId(archive.id)}.pmtiles"),
                    rev = row.rev, sizeMb = row.sizeMb,
                    deltaUrl = OfflineUpdates.deltaUrl(have, row),
                    deltaFromRev = row.deltaFromRev,
                    deltaPath = joinPath(placesPath, "${safeId(archive.id)}.vpatch"),
                    replace = true,
                )
            }
        }
        for (archive in record.maps) {
            val row = maps.firstOrNull { it.id == archive.id } ?: continue
            val have = revisions.get(KIND_BASEMAP, archive.id)
            if (row.rev > have) {
                out += OfflineAssetPlan(
                    archive.id, KIND_BASEMAP, row.url,
                    joinPath(basemapPath, "${safeId(archive.id)}.pmtiles"),
                    rev = row.rev, sizeMb = row.sizeMb,
                    deltaUrl = OfflineUpdates.deltaUrl(have, row),
                    deltaFromRev = row.deltaFromRev,
                    deltaPath = joinPath(basemapPath, "${safeId(archive.id)}.vpatch"),
                    replace = true,
                )
            }
        }
        return out
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
                if (asset.optional) {
                    runCatching { installAsset(asset) }.onFailure {
                        core.log.w("VelaRegion", "$regionId: optional ${asset.id} failed: ${it.message}")
                    }
                } else {
                    installAsset(asset)
                }
                _state.update { it.copy(downloadCompletedPieces = index + 1) }
            }
            withContext(ioDispatcher) {
                writeInstalled(plan.record)
                recordRevisions(plan.assets)
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
            if (plan.area) {
                extrasJob = scope.launch { runAreaExtras(plan) }
            } else {
                // Best effort and after the completion, so a slow or dead Overpass mirror never
                // delays or fails a region install. No pack is a valid result and the sheet says so.
                scope.launch { writeCameraPack(regionId) }
            }
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

    private suspend fun runUpdate(regionId: String, assets: List<OfflineAssetPlan>) {
        _state.update {
            it.copy(
                updatingId = regionId, downloadStage = "", downloadProgress = 0,
                downloadCompletedPieces = 0, downloadPieceCount = assets.size,
                updatedId = null, errorKey = null,
                updateDeltaPieces = 0, updateFullPieces = 0,
            )
        }
        try {
            for ((index, asset) in assets.withIndex()) {
                val delta = asset.deltaUrl != null && withContext(ioDispatcher) {
                    val path = asset.deltaPath
                    if (asset.kind == KIND_PACK) downloadDelta(asset)
                    else downloadArchivePatch(asset)
                }
                var applied = false
                if (delta) {
                    applied = withContext(ioDispatcher) {
                        if (asset.kind == KIND_PACK) applyPackDelta(asset) else applyArchiveDelta(asset)
                    }
                }
                if (applied) {
                    withContext(ioDispatcher) { files.delete(asset.deltaPath) }
                    revisions = revisions.with(asset.kind, asset.id, asset.rev)
                    withContext(ioDispatcher) { writeRevisions(revisions) }
                    _state.update { it.copy(updateDeltaPieces = it.updateDeltaPieces + 1) }
                } else {
                    if (asset.deltaUrl != null) {
                        core.log.w("VelaRegion", "${asset.id}: delta refused, downloading rev ${asset.rev} whole")
                        withContext(ioDispatcher) { files.delete(asset.deltaPath) }
                    }
                    installAsset(asset)
                    revisions = revisions.with(asset.kind, asset.id, asset.rev)
                    withContext(ioDispatcher) { writeRevisions(revisions) }
                    _state.update { it.copy(updateFullPieces = it.updateFullPieces + 1) }
                }
                _state.update { it.copy(downloadCompletedPieces = index + 1) }
            }
            withContext(ioDispatcher) { registerPacks() }
            RoadNameTiles.clearCache()
            rebuildRegions()
            updateStorage()
            _state.update {
                it.copy(
                    updatingId = null, downloadStage = "", downloadProgress = 100,
                    updatedId = regionId, revision = it.revision + 1,
                )
            }
            core.log.i("VelaRegion", "$regionId: updated")
        } catch (e: CancellationException) {
            _state.update { it.copy(updatingId = null, downloadStage = "", downloadProgress = 0) }
            throw e
        } catch (e: Throwable) {
            core.log.w("VelaRegion", "$regionId: update failed", e)
            _state.update {
                it.copy(updatingId = null, downloadStage = "", downloadProgress = 0,
                    errorKey = "download_failed")
            }
        }
    }

    private suspend fun downloadDelta(asset: OfflineAssetPlan): Boolean {
        val url = asset.deltaUrl ?: return false
        _state.update { it.copy(downloadStage = KIND_PACK_DELTA, downloadProgress = 0) }
        files.mkdirs(asset.deltaPath.substringBeforeLast('/'))
        return runCatching { downloadTo(asset.id, KIND_PACK_DELTA, url, asset.deltaPath) }.getOrDefault(false)
    }

    private suspend fun downloadArchivePatch(asset: OfflineAssetPlan): Boolean {
        val url = asset.deltaUrl ?: return false
        _state.update { it.copy(downloadStage = KIND_PATCH, downloadProgress = 0) }
        files.mkdirs(asset.deltaPath.substringBeforeLast('/'))
        return runCatching { downloadTo(asset.id, KIND_PATCH, url, asset.deltaPath) }.getOrDefault(false)
    }

    private suspend fun downloadTo(id: String, kind: String, url: String, path: String): Boolean {
        suspendCancellableCoroutine<Unit> { continuation ->
            var call: Cancellable? = null
            var finished = false
            call = downloader.start(
                id = id, kind = kind, url = url, targetPath = path,
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
        return files.size(path) > 16
    }

    /** Applies a place-pack delta in one transaction; false means download the pack whole. */
    private fun applyPackDelta(asset: OfflineAssetPlan): Boolean {
        if (!valid(KIND_PACK, asset.targetPath) || files.size(asset.deltaPath) <= 16) return false
        files.delete(joinPath(packsPath, "${safeId(asset.id)}.db.tmp"))
        OfflinePacks.reload(sql, packPaths().filter { it != asset.targetPath })
        var pack: SqlDb? = null
        var delta: SqlDb? = null
        return try {
            pack = openWritablePack(asset.targetPath)
            delta = sql.openReadOnly(asset.deltaPath)
            when (val outcome = PackDelta.apply(pack, delta, asset.counts)) {
                is PackDelta.Outcome.Applied -> {
                    core.log.i("VelaRegion", "${asset.id}: pack delta applied, ${outcome.rows} rows")
                    true
                }
                is PackDelta.Outcome.Refused -> {
                    core.log.w("VelaRegion", "${asset.id}: pack delta refused, ${outcome.why}")
                    false
                }
            }
        } catch (e: Throwable) {
            core.log.w("VelaRegion", "${asset.id}: pack delta failed", e)
            false
        } finally {
            runCatching { delta?.close() }
            runCatching { pack?.close() }
            registerPacks()
        }
    }

    /** Applies an archive delta in place, proven by its fingerprint; false means download whole. */
    private fun applyArchiveDelta(asset: OfflineAssetPlan): Boolean {
        if (!valid(asset.kind, asset.targetPath) || files.size(asset.deltaPath) <= 16) return false
        val outcome = PmtilesPatch.apply(asset.targetPath, asset.deltaPath, log = core.log)
        return when (outcome) {
            is PmtilesPatch.Outcome.Applied -> {
                core.log.i(
                    "VelaRegion",
                    "${asset.id}: archive patched to rev ${asset.rev}, ${outcome.tiles} tiles, " +
                        "${outcome.deadBytes / 1024} KB dead",
                )
                // A patch appends and leaves superseded tiles behind. Rewriting is local and
                // optional: a refusal still leaves a correct archive.
                val size = files.size(asset.targetPath)
                if (outcome.deadBytes > size / 5) {
                    when (val compact = PmtilesCompact.compact(asset.targetPath)) {
                        is PmtilesCompact.Outcome.Done -> core.log.i(
                            "VelaRegion",
                            "${asset.id}: compacted ${compact.beforeBytes / 1024} KB to " +
                                "${compact.afterBytes / 1024} KB",
                        )
                        is PmtilesCompact.Outcome.Refused -> core.log.w(
                            "VelaRegion", "${asset.id}: not compacted, ${compact.why}")
                    }
                }
                true
            }
            is PmtilesPatch.Outcome.Refused -> {
                core.log.w("VelaRegion", "${asset.id}: archive patch refused, ${outcome.why}")
                false
            }
        }
    }

    private fun openWritablePack(path: String): SqlDb {
        var reader: SqlDb? = null
        val version = try {
            reader = sql.openReadOnly(path)
            maxOf(1, reader.queryLong("PRAGMA user_version").toInt())
        } catch (e: Throwable) {
            1
        } finally {
            runCatching { reader?.close() }
        }
        return sql.open(path, version, {}, { _, _, _ -> })
    }

    fun cancelDownload() {
        // Clear the durable intent before the asynchronous task cancellation, so an immediate
        // process kill cannot turn a user's Cancel into an automatic retry on the next launch.
        pending = null
        files.delete(pendingPath)
        _state.update { it.copy(areaId = null, areaDataStage = "") }
        extrasJob?.cancel()
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
                old.packId?.takeIf { it !in usedPacks }?.let {
                    files.delete(joinPath(packsPath, "${safeId(it)}.db"))
                    revisions = revisions.without(KIND_PACK, it)
                }
                old.places.filter { it.id !in usedPlaces }.forEach {
                    files.delete(joinPath(placesPath, "${safeId(it.id)}.pmtiles"))
                    revisions = revisions.without(KIND_PLACES, it.id)
                }
                old.maps.filter { it.id !in usedMaps }.forEach {
                    files.delete(joinPath(basemapPath, "${safeId(it.id)}.pmtiles"))
                    revisions = revisions.without(KIND_BASEMAP, it.id)
                }
                writeRevisions(revisions)
                files.delete(joinPath(regionsPath, "${safeId(regionId)}.json"))
                files.delete(joinPath(cameraPacksPath, "${safeId(regionId)}.json"))
                registerPacks()
            }
            installed = remaining
            RoadNameTiles.clearCache()
            rebuildRegions()
            updateStorage()
            _state.update { it.copy(completedId = null, updatedId = null, revision = it.revision + 1) }
        }
    }

    /**
     * Deletes one category of an installed region: its place pack, its places archives or its
     * basemap archive. A file another region still uses stays. When no piece is left the region's
     * marker goes too, so it reads as available again rather than half installed.
     */
    fun deleteCategory(regionId: String, category: String) {
        if (downloadJob?.isActive == true) return
        val old = installed[regionId] ?: return
        scope.launch {
            var updated: InstalledRegion? = null
            withContext(ioDispatcher) {
                val remaining = installed - regionId
                when (category) {
                    KIND_PACK -> {
                        old.packId?.let { id ->
                            val used = remaining.values.mapNotNull { it.packId }.toSet()
                            if (id !in used) {
                                files.delete(joinPath(packsPath, "${safeId(id)}.db"))
                                revisions = revisions.without(KIND_PACK, id)
                            }
                        }
                        updated = old.copy(packId = null)
                    }
                    KIND_PLACES -> {
                        val used = remaining.values.flatMap { it.places }.map { it.id }.toSet()
                        old.places.filter { it.id !in used }.forEach {
                            files.delete(joinPath(placesPath, "${safeId(it.id)}.pmtiles"))
                            revisions = revisions.without(KIND_PLACES, it.id)
                        }
                        updated = old.copy(places = emptyList())
                    }
                    KIND_BASEMAP -> {
                        val used = remaining.values.flatMap { it.maps }.map { it.id }.toSet()
                        old.maps.filter { it.id !in used }.forEach {
                            files.delete(joinPath(basemapPath, "${safeId(it.id)}.pmtiles"))
                            revisions = revisions.without(KIND_BASEMAP, it.id)
                        }
                        updated = old.copy(maps = emptyList())
                    }
                    else -> return@withContext
                }
                writeRevisions(revisions)
                registerPacks()
            }
            val record = updated ?: return@launch
            if (record.packId == null && record.places.isEmpty() && record.maps.isEmpty()) {
                withContext(ioDispatcher) { files.delete(joinPath(regionsPath, "${safeId(regionId)}.json")) }
                installed = installed - regionId
            } else {
                withContext(ioDispatcher) { writeInstalled(record) }
                installed = installed + (regionId to record)
            }
            RoadNameTiles.clearCache()
            rebuildRegions()
            updateStorage()
            _state.update { it.copy(revision = it.revision + 1) }
        }
    }

    /** True when a region has a published revision newer than the installed piece. */
    fun canUpdate(regionId: String): Boolean = makeUpdatePlan(regionId).isNotEmpty()

    /** The installed archive whose actual z12 roads reach this point, else the world floor. */
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
        return unreadable ?: worldFallback(offlineOnly())
    }

    /** The world archive, only while there is nothing else: offline and outside every region. */
    private fun worldFallback(offline: Boolean): String? =
        if (offline && worldInstalled()) worldPath else null

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
        if (!asset.replace && withContext(ioDispatcher) { valid(asset.kind, asset.targetPath) }) return
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
        KIND_PACK_DELTA -> files.size(path) > 16 && runCatching {
            sql.openReadOnly(path).close()
            true
        }.getOrDefault(false)
        KIND_PATCH -> files.size(path) > 16 && PmtilesPatch.read(path) != null
        KIND_GLYPHS -> files.size(joinPath(path, "Noto Sans Regular", "0-255.pbf")) > 0
        else -> false
    }

    private fun glyphsInstalled() = files.size(joinPath(glyphsPath, "Noto Sans Regular", "0-255.pbf")) > 0

    private fun worldInstalled() = files.size(worldPath) > 127 && PmtilesReader.header(worldPath) != null

    private fun packPaths(): List<String> = files.list(packsPath).orEmpty()
        .filter { !it.isDirectory && it.name.endsWith(".db") && valid(KIND_PACK, it.path) }
        .map { it.path }

    private fun registerPacks() {
        OfflinePacks.reload(sql, packPaths())
    }

    /**
     * Writes `<region>.json` under `camera-packs` with the speed and plate cameras Overpass
     * returns for the region bbox, capped at [CAMERA_PACK_LIMIT] per kind. It runs after the
     * region is usable, never blocks it, and a failed query writes nothing: an empty file would
     * claim "no cameras here" when the truth is "no answer".
     */
    private suspend fun writeCameraPack(regionId: String): Int {
        val region = routing.firstOrNull { it.id == regionId } ?: return -1
        if (region.e - region.w > CAMERA_PACK_MAX_SPAN || region.n - region.s > CAMERA_PACK_MAX_SPAN) {
            core.log.i("VelaRegion", "$regionId: camera pack skipped, region spans more than $CAMERA_PACK_MAX_SPAN degrees")
            return -1
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
            return -1
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
        return cameras.size
    }

    /**
     * The two network extras of an area download. Cameras use the region box; addresses use the
     * padded frame. They run after the region is usable, never block it, and a failed mirror leaves
     * the previous file or index in place rather than claiming an empty answer. Progress and counts
     * are in the state, so the card keeps reporting them after the sheet is closed.
     */
    private suspend fun runAreaExtras(plan: PendingRegionDownload) {
        val regionId = plan.record.id
        if (plan.cameras) {
            _state.update { it.copy(areaDataStage = KIND_CAMERAS) }
            val count = writeCameraPack(regionId)
            _state.update { it.copy(areaCameraRows = count, areaDataStage = "") }
        }
        if (plan.addresses) {
            _state.update { it.copy(areaDataStage = KIND_ADDRESSES) }
            val bounds = OfflineAreaBounds(plan.addressS, plan.addressW, plan.addressN, plan.addressE)
            val addresses = runCatching { OfflineAreaData.addresses(core.http, bounds) }.getOrNull()
            val streets = runCatching { OfflineAreaData.streets(core.http, bounds) }.getOrNull()
            if (addresses == null && streets == null) {
                core.log.i("VelaArea", "$regionId: no address data, no Overpass answer")
                _state.update { it.copy(areaAddressRows = -1, areaDataStage = "") }
            } else {
                val rows = withContext(ioDispatcher) {
                    if (!addresses.isNullOrEmpty()) addressStore.add(addresses)
                    if (!streets.isNullOrEmpty()) addressStore.addStreets(streets)
                    addressStore.count()
                }
                core.log.i("VelaArea", "$regionId: address index $rows rows")
                _state.update { it.copy(areaAddressRows = rows, areaDataStage = "") }
            }
        }
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

    private fun readRevisions(): InstalledRevisions = runCatching {
        if (!files.exists(revisionsPath)) return InstalledRevisions()
        json.decodeFromString<InstalledRevisions>(files.readText(revisionsPath))
    }.getOrDefault(InstalledRevisions())

    private fun writeRevisions(value: InstalledRevisions) {
        files.mkdirs(rootPath)
        files.writeTextAtomic(revisionsPath, json.encodeToString(InstalledRevisions.serializer(), value))
    }

    /** Records each installed piece's manifest revision, after a full download or an update. */
    private fun recordRevisions(assets: List<OfflineAssetPlan>) {
        var next = revisions
        for (asset in assets) {
            if (asset.rev > 0 && asset.kind in REVISION_KINDS && asset.id != WORLD_ID) {
                next = next.with(asset.kind, asset.id, asset.rev)
            }
        }
        revisions = next
        writeRevisions(next)
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
            val update = updateEstimate(region.id)
            OfflineRegion(
                region.id, region.name, (packMb + archiveMb).coerceAtLeast(1), region.id in installed,
                installedBytes = regionBytes(region.id),
                updateMb = update,
                updatable = update > 0,
            )
        }.sortedBy { it.name.lowercase() }
        _state.update { it.copy(regions = rows) }
        updateCurrentRegion()
    }

    /** Bytes a region update would download: delta sizes where applicable, whole pieces otherwise. */
    private fun updateEstimate(regionId: String): Int {
        if (regionId !in installed) return 0
        return makeUpdatePlan(regionId).sumOf { asset ->
            if (asset.deltaUrl != null) maxOf(1, deltaSize(asset)) else asset.sizeMb
        }
    }

    private fun deltaSize(asset: OfflineAssetPlan): Int {
        val row = when (asset.kind) {
            KIND_PACK -> packs.firstOrNull { it.id == asset.id }
            KIND_PLACES -> places.firstOrNull { it.id == asset.id }
            else -> maps.firstOrNull { it.id == asset.id }
        }
        return row?.deltaSizeMb ?: 1
    }

    private fun regionBytes(regionId: String): Long {
        val record = installed[regionId] ?: return 0
        return installedBytes(record)
    }

    private fun installedBytes(record: InstalledRegion): Long {
        val pack = record.packId?.let { files.size(joinPath(packsPath, "${safeId(it)}.db")) } ?: 0
        val placeBytes = record.places.sumOf { files.size(joinPath(placesPath, "${safeId(it.id)}.pmtiles")) }
        val mapBytes = record.maps.sumOf { files.size(joinPath(basemapPath, "${safeId(it.id)}.pmtiles")) }
        return pack + placeBytes + mapBytes
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
            val placesBytes = placeIds.sumOf { files.size(joinPath(placesPath, "${safeId(it)}.pmtiles")) }
            val mapBytes = mapIds.sumOf { files.size(joinPath(basemapPath, "${safeId(it)}.pmtiles")) } +
                files.size(worldPath)
            StorageSizes(
                packIds.sumOf { files.size(joinPath(packsPath, "${safeId(it)}.db")) },
                placesBytes,
                mapBytes,
                files.treeSize(glyphsPath),
                files.treeSize(rootPath),
                installed.map { (id, record) -> OfflineRegionBytes(
                    id,
                    record.packId?.let { files.size(joinPath(packsPath, "${safeId(it)}.db")) } ?: 0,
                    record.places.sumOf { files.size(joinPath(placesPath, "${safeId(it.id)}.pmtiles")) },
                    record.maps.sumOf { files.size(joinPath(basemapPath, "${safeId(it.id)}.pmtiles")) },
                ) },
                worldInstalled(),
            )
        }
        _state.update {
            it.copy(
                packBytes = sizes.packs, placesBytes = sizes.places, basemapBytes = sizes.maps,
                glyphBytes = sizes.glyphs, totalBytes = sizes.total,
                regionBytes = sizes.regions, worldInstalled = sizes.world,
            )
        }
    }

    private data class StorageSizes(
        val packs: Long,
        val places: Long,
        val maps: Long,
        val glyphs: Long,
        val total: Long,
        val regions: List<OfflineRegionBytes>,
        val world: Boolean,
    )

    private class OfflineAssetException(message: String) : Exception(message)

    internal companion object {
        const val KIND_PACK = "pack"
        const val KIND_PLACES = "places"
        const val KIND_BASEMAP = "basemap"
        const val KIND_GLYPHS = "glyphs"
        const val KIND_PACK_DELTA = "pack-delta"
        const val KIND_PATCH = "patch"
        const val KIND_CAMERAS = "cameras"
        const val KIND_ADDRESSES = "addresses"
        const val WORLD_ID = "world"
        private const val COVERAGE_Z = 12
        private const val MEGABYTE = 1024L * 1024L
        /** At most this many speed and plate cameras in one region pack, per kind. */
        const val CAMERA_PACK_LIMIT = 2000
        /** Larger boxes are not queried in one Overpass call; no pack is written for them. */
        const val CAMERA_PACK_MAX_SPAN = 12.0

        /** Five decimals is about one meter; it keeps the pack file small. */
        fun packCoord(v: Double): Double = (v * 100_000).roundToInt() / 100_000.0

        private const val WORLD_ESTIMATED_MB = 40
        private val REVISION_KINDS = setOf(KIND_PACK, KIND_PLACES, KIND_BASEMAP)

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

        /** The world archive is a fallback only offline; online it must never hide fresh tiles. */
        fun worldFallbackPath(worldPath: String?, offline: Boolean): String? =
            if (offline) worldPath else null

        private fun installedArchive(region: RoutingRegion) = InstalledArchive(region.id, region.s, region.w, region.n, region.e)

        private fun safeId(id: String): String {
            require(id.isNotEmpty() && id.all { it.isLetterOrDigit() || it == '_' || it == '-' }) { "unsafe region id" }
            return id
        }
    }
}
