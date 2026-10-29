package app.vela.ios.map

import app.vela.core.data.FuelGb
import app.vela.core.data.FuelGbStations
import app.vela.core.data.FuelGbStore
import app.vela.core.data.NdwBridgeOpenings
import app.vela.core.data.OverpassAlprCameras
import app.vela.core.data.OverpassSpeedCameras
import app.vela.core.data.OverpassTrafficSignals
import app.vela.core.data.PaintedRoads
import app.vela.core.model.LatLng
import app.vela.core.model.bearingTo
import app.vela.core.model.destinationPoint
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.joinPath
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.cos

/** One drawable point, in the flat shape Swift reads from the framework.
 *
 *  [direction] is the OSM facing in degrees clockwise from north when the source knows it,
 *  null otherwise. The two camera layers use it for their direction wedge; a null bearing
 *  draws a bare dot rather than a guessed cone. Other overlays leave it null.
 */
data class MapPoint(val lat: Double, val lng: Double, val direction: Double? = null)

/** One OSM road control, with its [kind] name (`SIGNAL`, `STOP`, `RAIL_CROSSING`, `SPEED_HUMP`). */
data class MapControlPoint(val lat: Double, val lng: Double, val kind: String)

/** One movable bridge. [openNow] means the feed says it is open and has no end time yet. */
data class MapBridgePoint(
    val lat: Double,
    val lng: Double,
    val openNow: Boolean,
    val startMs: Long,
    val endMs: Long,
)

/** One UK forecourt. Prices are pence per litre, -1 when that fuel is not sold there. */
data class MapFuelPoint(
    val lat: Double,
    val lng: Double,
    val brand: String,
    val e10Pence: Double,
    val e5Pence: Double,
    val b7sPence: Double,
    val b7pPence: Double,
)

/** One painted-road mark. [points] are already offset from the way's centerline by [offsetM].
 *  [icon] and [rotDeg] are set on ARROW only; the renderer turns that point into a symbol. */
data class PaintedMarkPoint(
    val kind: String,
    val points: List<MapPoint>,
    val widthM: Double,
    val icon: String = "",
    val rotDeg: Double = 0.0,
)

/**
 * The painted-mark selection rules shared by the JVM tests and the iOS renderer.
 *
 * Two sources can produce markings: the optional `painted-roads` PMTiles pack, or the map itself.
 * The pack is a separate download and is absent on most installations, so the map always has a
 * usable answer: the live OSM marks of the view, and, when even those cannot be fetched, the
 * one-way arrows already in the OpenFreeMap vector tiles.
 */
object PaintedMarks {
    /** Android draws from 16.5; below that a marking is thinner than a screen point. */
    const val MIN_ZOOM = 16.5
    const val PACK = "pack"
    const val TILES = "tiles"

    /** The sheet's switch and the map's zoom gate, in one place. */
    fun visible(zoom: Double, on: Boolean): Boolean = on && zoom + 0.001 >= MIN_ZOOM

    /** Which source the sheet names: the installed pack, otherwise the map's own OSM data. */
    fun source(packInstalled: Boolean): String = if (packInstalled) PACK else TILES

    /** The vector tiles' `road_one_way_arrow` layers stand in only when the pack is absent and
     *  the live marks produced nothing. They are never added on top of painted arrows. */
    fun fallbackArrows(packInstalled: Boolean, markCount: Int, on: Boolean, zoom: Double): Boolean =
        visible(zoom, on) && !packInstalled && markCount == 0
}

/** The state the layer sheet and the map renderer read. */
data class LayersState(
    val paintedRoads: Boolean = false,
    val speedCameras: Boolean = false,
    val alprCameras: Boolean = false,
    val trafficControls: Boolean = false,
    val fuelPrices: Boolean = false,
    val bridgeOpenings: Boolean = false,
    /** Google's traffic raster. Network only; Swift skips it inside a downloaded region. */
    val trafficOn: Boolean = false,
    /** Esri satellite imagery with Google's deep-zoom fallback. Same offline rule as [trafficOn]. */
    val satelliteOn: Boolean = false,
    /** POI icon and label size multiplier, Android's `map_poi_icon_scale`: 0.7, 1.0 or 1.25. */
    val poiIconScale: Float = 1f,
    /** Where the businesses on the browse map come from: [PoiSources.TILES], [PoiSources.VELA]
     *  or [PoiSources.BOTH]. Android stores the same key with `open`, `google` and `both`. */
    val poiSource: String = PoiSources.BOTH,
    /** Which camera family draws: [CameraSources.LIVE] query, [CameraSources.PACK] file, or
     *  [CameraSources.AUTO] (live online, pack over a downloaded region). */
    val cameraSource: String = CameraSources.AUTO,
    val showPlaces: Boolean = true,
    val showFood: Boolean = true,
    val showFuel: Boolean = true,
    val showTransit: Boolean = true,
    val showParking: Boolean = true,
    val showOther: Boolean = true,
    /** `normal` or `compact`: compact hides lower-priority POI groups until closer zooms. */
    val poiDensity: String = "normal",
    /** True when the category flags exclude at least one OSM class. */
    val poiFiltered: Boolean = false,
    /** The OSM `class` values the basemap POI layers may draw. Empty when unfiltered. */
    val visiblePoiClasses: List<String> = emptyList(),
    /** The sheet groups the bundled Vela pack may draw. Empty when every category is on. */
    val visiblePoiGroups: List<String> = emptyList(),
    val layerStatus: List<MapLayerStatus> = emptyList(),
    val paintedMarks: List<PaintedMarkPoint> = emptyList(),
    val speedCameraPoints: List<MapPoint> = emptyList(),
    val alprCameraPoints: List<MapPoint> = emptyList(),
    val controlPoints: List<MapControlPoint> = emptyList(),
    val fuelPoints: List<MapFuelPoint> = emptyList(),
    val bridgePoints: List<MapBridgePoint> = emptyList(),
    val zoom: Double = 0.0,
)

/** One layer's progress, read as text and numbers by Swift; no formatted user text is built here. */
data class MapLayerStatus(
    val kind: String,
    val phase: String,
    val count: Int,
    val minZoom: Double,
    val detail: String = "",
)

/** The six overlays this build can draw from common data. */
enum class MapLayerKind(val key: String) {
    PAINTED_ROADS("painted"),
    SPEED_CAMERAS("speed"),
    ALPR_CAMERAS("alpr"),
    TRAFFIC_CONTROLS("controls"),
    FUEL_PRICES("fuel"),
    BRIDGE_OPENINGS("bridges"),
}

/** Supplies UK Fuel Finder stations; separated so the layer's gating is testable without a file. */
interface FuelPriceSource {
    /** The stations, or null while they cannot be loaded. */
    suspend fun load(): FuelGbStations?
}

private class StoreFuelPriceSource(
    private val files: PlatformFiles,
    private val http: VelaHttp,
    private val now: () -> Long,
) : FuelPriceSource {
    private val store = FuelGbStore(
        files = files,
        dir = { joinPath(files.noBackupDir, "fuelgb") },
        http = http,
        nowMs = now,
    )

    override suspend fun load(): FuelGbStations? {
        store.ensure()
        return store.current?.takeIf { it.size > 0 }
    }
}

/**
 * The map's optional overlays (I-1b, extended by I-1c). Everything loads only after the user
 * enables it, only at the zoom the layer is legible at, and only when the view leaves the inner
 * half of the box a successful fetch already covers. A failed fetch is never cached as "nothing
 * here": the next viewport retries. Construction is inert; [start] reads the stored switches.
 *
 * The traffic and satellite rasters add no Kotlin fetch here: they are MapLibre raster sources that
 * Swift inserts into the style from [RasterTiles], and Swift skips both inside a downloaded region.
 * Their switches are stored and exposed like the six data overlays so the sheet and the map agree.
 */
class LayersStore(
    stores: KeyValueStores,
    private val http: VelaHttp,
    private val scope: CoroutineScope,
    files: PlatformFiles,
    private val now: () -> Long = { 0L },
    private val fuelSource: FuelPriceSource? = null,
    private val background: CoroutineDispatcher = Dispatchers.Default,
) {
    private val settings: KeyValueStore = stores.open("vela_settings")

    private val _state = MutableStateFlow(LayersState())
    val state: StateFlow<LayersState> = _state.asStateFlow()

    private val fuel: FuelPriceSource by lazy {
        fuelSource ?: StoreFuelPriceSource(files, http, now)
    }

    private var started = false
    private var viewport: Viewport? = null
    private val jobs = mutableMapOf<String, Job>()
    private val generations = mutableMapOf<String, Int>()
    private val boxes = mutableMapOf<String, Box>()
    private var fuelLoadedAt = Long.MIN_VALUE
    private var bridgeLoadedAt = Long.MIN_VALUE

    fun start() {
        if (started) return
        started = true
        val poi = poiState()
        _state.value = LayersState(
            paintedRoads = settings.getBoolean(KEY_PAINTED, false),
            speedCameras = settings.getBoolean(KEY_SPEED, false),
            alprCameras = settings.getBoolean(KEY_ALPR, false),
            trafficControls = settings.getBoolean(KEY_CONTROLS, false),
            fuelPrices = settings.getBoolean(KEY_FUEL, false),
            bridgeOpenings = settings.getBoolean(KEY_BRIDGES, false),
            trafficOn = settings.getBoolean(KEY_TRAFFIC, false),
            satelliteOn = settings.getBoolean(KEY_SATELLITE, false),
            poiIconScale = poiIconScale(settings.getFloat(KEY_ICON_SCALE, 1f)),
            poiSource = PoiSources.normalize(settings.getString(KEY_POI_SOURCE, PoiSources.BOTH)),
            cameraSource = CameraSources.normalize(
                settings.getString(KEY_CAMERA_SOURCE, CameraSources.AUTO)),
            showPlaces = poi.showPlaces,
            showFood = poi.food,
            showFuel = poi.fuel,
            showTransit = poi.transit,
            showParking = poi.parking,
            showOther = poi.other,
            poiDensity = poi.density,
            poiFiltered = poi.classes != null,
            visiblePoiClasses = poi.classes.orEmpty(),
            visiblePoiGroups = poi.groups,
            layerStatus = MapLayerKind.entries.map { status(it, "off", 0) },
        )
    }

    fun stop() {
        jobs.values.forEach { it.cancel() }
        jobs.clear()
    }

    /** String entry for Swift, which names the switch rather than a Kotlin enum case. */
    fun setSwitch(key: String, on: Boolean) {
        when (key) {
            "traffic" -> setTraffic(on)
            "satellite" -> setSatellite(on)
            else -> MapLayerKind.entries.firstOrNull { it.key == key }?.let { setEnabled(it, on) }
        }
    }

    /** Google's live-traffic raster. No Kotlin request: Swift adds or removes the MapLibre layer. */
    fun setTraffic(on: Boolean) {
        if (!started) return
        settings.edit().putBoolean(KEY_TRAFFIC, on).apply()
        _state.value = _state.value.copy(trafficOn = on)
    }

    /** Esri imagery with Google's deep fallback. Network only, like [setTraffic]. */
    fun setSatellite(on: Boolean) {
        if (!started) return
        settings.edit().putBoolean(KEY_SATELLITE, on).apply()
        _state.value = _state.value.copy(satelliteOn = on)
    }

    /** `0.7`, `1.0` or `1.25`, Android's three icon sizes; anything outside 0.5..2 is clamped. */
    fun setPoiIconScale(scale: Float) {
        if (!started) return
        val value = poiIconScale(scale)
        settings.edit().putFloat(KEY_ICON_SCALE, value).apply()
        _state.value = _state.value.copy(poiIconScale = value)
    }

    /** Android's `map_places_source`: `vela`, `tiles` or `both`. Android's older `open` and
     *  `google` values are accepted on read, so a settings file from either app keeps working. */
    fun setPoiSource(source: String) {
        if (!started) return
        val value = PoiSources.normalize(source)
        settings.edit().putString(KEY_POI_SOURCE, value).apply()
        _state.value = _state.value.copy(poiSource = value)
    }

    /**
     * `auto`, `live` or `pack`. In `pack` mode the two camera kinds never query Overpass: the
     * points come from a file in the app bundle or in the offline folder, read by Swift. Switching
     * to `live` or `auto` clears the pack answer and asks again, so the sheet never mixes them.
     */
    fun setCameraSource(source: String) {
        if (!started) return
        val value = CameraSources.normalize(source)
        settings.edit().putString(KEY_CAMERA_SOURCE, value).apply()
        _state.value = _state.value.copy(cameraSource = value)
        for (kind in CAMERA_KINDS) {
            if (!enabled(kind)) continue
            cancel(kind)
            clear(kind)
            if (value == CameraSources.PACK) {
                updateStatus(kind, "pack", 0)
            } else {
                val at = viewport
                if (at == null) updateStatus(kind, "idle", 0) else request(kind, at, force = true)
            }
        }
    }

    fun setEnabled(kind: MapLayerKind, on: Boolean) {
        if (!started) return
        when (kind) {
            MapLayerKind.PAINTED_ROADS -> settings.edit().putBoolean(KEY_PAINTED, on).apply()
            MapLayerKind.SPEED_CAMERAS -> settings.edit().putBoolean(KEY_SPEED, on).apply()
            MapLayerKind.ALPR_CAMERAS -> settings.edit().putBoolean(KEY_ALPR, on).apply()
            MapLayerKind.TRAFFIC_CONTROLS -> settings.edit().putBoolean(KEY_CONTROLS, on).apply()
            MapLayerKind.FUEL_PRICES -> settings.edit().putBoolean(KEY_FUEL, on).apply()
            MapLayerKind.BRIDGE_OPENINGS -> settings.edit().putBoolean(KEY_BRIDGES, on).apply()
        }
        _state.value = when (kind) {
            MapLayerKind.PAINTED_ROADS -> _state.value.copy(paintedRoads = on)
            MapLayerKind.SPEED_CAMERAS -> _state.value.copy(speedCameras = on)
            MapLayerKind.ALPR_CAMERAS -> _state.value.copy(alprCameras = on)
            MapLayerKind.TRAFFIC_CONTROLS -> _state.value.copy(trafficControls = on)
            MapLayerKind.FUEL_PRICES -> _state.value.copy(fuelPrices = on)
            MapLayerKind.BRIDGE_OPENINGS -> _state.value.copy(bridgeOpenings = on)
        }
        val current = viewport
        if (!on) {
            cancel(kind)
            clear(kind)
            updateStatus(kind, "off", 0)
        } else if (current == null) {
            updateStatus(kind, "idle", 0)
        } else {
            request(kind, current, force = true)
        }
    }

    /** Called on camera idle only, never per frame. */
    fun onViewport(south: Double, west: Double, north: Double, east: Double, zoom: Double) {
        if (!started) return
        if (south !in -90.0..90.0 || north !in -90.0..90.0 || west !in -180.0..180.0 ||
            east !in -180.0..180.0 || north <= south || east <= west) return
        val next = Viewport(south, west, north, east, zoom)
        viewport = next
        _state.value = _state.value.copy(zoom = zoom)
        for (kind in enabledKinds()) request(kind, next, force = false)
    }

    fun setShowPlaces(on: Boolean) {
        if (!started) return
        settings.edit().putBoolean(KEY_POIS, on).apply()
        _state.value = _state.value.copy(showPlaces = on)
    }

    fun setPoiCategory(category: String, on: Boolean) {
        if (!started) return
        val key = when (category) {
            "food" -> KEY_FOOD
            "fuel" -> KEY_FUEL_POIS
            "transit" -> KEY_TRANSIT
            "parking" -> KEY_PARKING
            else -> KEY_CIVIC
        }
        settings.edit().putBoolean(key, on).apply()
        val s = _state.value
        val next = when (category) {
            "food" -> s.copy(showFood = on)
            "fuel" -> s.copy(showFuel = on)
            "transit" -> s.copy(showTransit = on)
            "parking" -> s.copy(showParking = on)
            else -> s.copy(showOther = on)
        }
        applyPoi(next)
    }

    /** `normal` or `compact`; anything else falls back to normal. */
    fun setPoiDensity(density: String) {
        if (!started) return
        val value = if (density == "compact") "compact" else "normal"
        settings.edit().putString(KEY_DENSITY, value).apply()
        applyPoi(_state.value.copy(poiDensity = value))
    }

    private fun applyPoi(state: LayersState) {
        val classes = PoiClasses.visible(
            state.showFood, state.showFuel, state.showTransit, state.showParking, state.showOther,
        )
        _state.value = state.copy(
            poiFiltered = classes != null,
            visiblePoiClasses = classes.orEmpty(),
            visiblePoiGroups = PoiGroups.visible(
                state.showFood, state.showFuel, state.showTransit, state.showParking, state.showOther,
            ),
        )
    }

    private fun poiState(): PoiPrefs = PoiPrefs(
        showPlaces = settings.getBoolean(KEY_POIS, true),
        food = settings.getBoolean(KEY_FOOD, true),
        fuel = settings.getBoolean(KEY_FUEL_POIS, true),
        transit = settings.getBoolean(KEY_TRANSIT, true),
        parking = settings.getBoolean(KEY_PARKING, true),
        other = settings.getBoolean(KEY_CIVIC, true),
        density = if (settings.getString(KEY_DENSITY, "normal") == "compact") "compact" else "normal",
        classes = PoiClasses.visible(
            settings.getBoolean(KEY_FOOD, true),
            settings.getBoolean(KEY_FUEL_POIS, true),
            settings.getBoolean(KEY_TRANSIT, true),
            settings.getBoolean(KEY_PARKING, true),
            settings.getBoolean(KEY_CIVIC, true),
        ),
        groups = PoiGroups.visible(
            settings.getBoolean(KEY_FOOD, true),
            settings.getBoolean(KEY_FUEL_POIS, true),
            settings.getBoolean(KEY_TRANSIT, true),
            settings.getBoolean(KEY_PARKING, true),
            settings.getBoolean(KEY_CIVIC, true),
        ),
    )

    private fun request(kind: MapLayerKind, at: Viewport, force: Boolean) {
        if (!enabled(kind)) return
        if (kind in CAMERA_KINDS && _state.value.cameraSource == CameraSources.PACK) {
            // The pack is a file; there is no request to make and no empty answer to cache.
            cancel(kind)
            clear(kind)
            updateStatus(kind, "pack", 0)
            return
        }
        val minZoom = minZoom(kind)
        if (at.zoom + 0.001 < minZoom) {
            // Too far out to be legible: no request, no invented empty result. Keep any cached
            // marks so the layer reappears at once when the user zooms back in.
            cancel(kind)
            updateStatus(kind, "zoom", count(kind))
            return
        }
        val coverage = boxes[kind.key]
        if (!force && coverage != null && coverage.containsInner(at.centerLat, at.centerLng)) return
        val generation = (generations[kind.key] ?: 0) + 1
        generations[kind.key] = generation
        jobs[kind.key]?.cancel()
        updateStatus(kind, "loading", count(kind))
        jobs[kind.key] = scope.launch {
            val result = when (kind) {
                MapLayerKind.PAINTED_ROADS -> loadPainted(at)
                MapLayerKind.SPEED_CAMERAS -> loadCameras(at, alpr = false)
                MapLayerKind.ALPR_CAMERAS -> loadCameras(at, alpr = true)
                MapLayerKind.TRAFFIC_CONTROLS -> loadControls(at)
                MapLayerKind.FUEL_PRICES -> loadFuel(at)
                MapLayerKind.BRIDGE_OPENINGS -> loadBridges(at)
            }
            if (generation != generations[kind.key]) return@launch
            if (result == null) {
                updateStatus(kind, "error", count(kind))
                return@launch
            }
            boxes[kind.key] = at.padded()
            if (result == "unavailable") {
                clear(kind)
                updateStatus(kind, "unavailable", 0)
            } else {
                updateStatus(kind, "ready", count(kind))
            }
        }
    }

    /** Null means the fetch failed; [UNAVAILABLE] means this data does not cover the view. */
    private suspend fun loadPainted(at: Viewport): String? {
        val box = at.padded()
        val got = try {
            PaintedRoads.fetch(http, box.south, box.west, box.north, box.east)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } ?: return null
        val marks = withContext(background) {
            PaintedRoads.build(got.first, got.second).mapNotNull { mark ->
                val points = offsetPoints(mark.points.map { MapPoint(it.lat, it.lng) }, mark.offsetM)
                if (points.isEmpty()) null
                else PaintedMarkPoint(mark.kind.name, points, mark.widthM, mark.icon, mark.rotDeg)
            }
        }
        _state.value = _state.value.copy(paintedMarks = marks)
        return "ok"
    }

    private suspend fun loadCameras(at: Viewport, alpr: Boolean): String? {
        val box = at.padded()
        val cameras = try {
            if (alpr) {
                OverpassAlprCameras.fetchInBox(http, box.south, box.west, box.north, box.east)
                    ?.map { MapPoint(it.loc.lat, it.loc.lng, it.direction.toDoubleOrNull()) }
            } else {
                // Fixed speed cameras carry no facing tag: the dot stays bare, as on Android.
                OverpassSpeedCameras.fetchInBox(http, box.south, box.west, box.north, box.east)
                    ?.map { MapPoint(it.loc.lat, it.loc.lng) }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } ?: return null
        val kept = capNearestPoints(declutter(cameras, CAMERA_MERGE_M), at, CAMERA_CAP)
        _state.value = if (alpr) {
            _state.value.copy(alprCameraPoints = kept)
        } else {
            _state.value.copy(speedCameraPoints = kept)
        }
        return "ok"
    }

    private suspend fun loadControls(at: Viewport): String? {
        val box = at.padded()
        val controls = try {
            OverpassTrafficSignals.fetchControlsInBox(
                http, box.south, box.west, box.north, box.east,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } ?: return null
        // One glyph per intersection: OSM maps a control node per approach, like Android's
        // 30 m grouping, so a four-way stop does not draw four symbols on top of each other.
        val merged = controls
            .map { MapControlPoint(it.loc.lat, it.loc.lng, it.kind.name) }
            .distinctBy { Triple(it.kind, round6(it.lat), round6(it.lng)) }
        val kept = capNearestControls(declutterByKind(merged, CONTROL_MERGE_M), at, CONTROL_CAP)
        _state.value = _state.value.copy(controlPoints = kept)
        return "ok"
    }

    private suspend fun loadFuel(at: Viewport): String? {
        val center = LatLng(at.centerLat, at.centerLng)
        if (!FuelGb.inUk(center)) {
            _state.value = _state.value.copy(fuelPoints = emptyList())
            return UNAVAILABLE
        }
        if (fuelLoadedAt != Long.MIN_VALUE && now() - fuelLoadedAt in 0 until FUEL_RECHECK_MS) {
            // The file is static for hours and [FuelGbStore] owns its own refresh window.
            val existing = _state.value.fuelPoints
            if (existing.isNotEmpty()) return "ok"
        }
        val stations = try {
            fuel.load()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } ?: return null
        fuelLoadedAt = now()
        val box = at.padded()
        val points = ArrayList<MapFuelPoint>()
        for (i in 0 until stations.size) {
            val lat = stations.lat[i]
            val lng = stations.lng[i]
            if (lat !in box.south..box.north || lng !in box.west..box.east) continue
            points += MapFuelPoint(
                lat = lat,
                lng = lng,
                brand = stations.brand[i],
                e10Pence = pence(stations.e10[i]),
                e5Pence = pence(stations.e5[i]),
                b7sPence = pence(stations.b7s[i]),
                b7pPence = pence(stations.b7p[i]),
            )
            if (points.size >= FUEL_CAP) break
        }
        _state.value = _state.value.copy(fuelPoints = points)
        return "ok"
    }

    private suspend fun loadBridges(at: Viewport): String? {
        val center = LatLng(at.centerLat, at.centerLng)
        if (!NdwBridgeOpenings.inNetherlands(center)) {
            _state.value = _state.value.copy(bridgePoints = emptyList())
            return UNAVAILABLE
        }
        if (bridgeLoadedAt != Long.MIN_VALUE && now() - bridgeLoadedAt in 0 until BRIDGE_RECHECK_MS) {
            val existing = _state.value.bridgePoints
            if (existing.isNotEmpty()) return "ok"
        }
        val openings = try {
            NdwBridgeOpenings.fetch(http)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        } ?: return null
        bridgeLoadedAt = now()
        val box = at.padded()
        val points = openings
            .filter { it.loc.lat in box.south..box.north && it.loc.lng in box.west..box.east }
            .take(BRIDGE_CAP)
            .map {
                MapBridgePoint(
                    lat = it.loc.lat, lng = it.loc.lng, openNow = it.openNow,
                    startMs = it.startMs, endMs = it.endMs ?: 0L,
                )
            }
        _state.value = _state.value.copy(bridgePoints = points)
        return "ok"
    }

    private fun enabled(kind: MapLayerKind): Boolean = when (kind) {
        MapLayerKind.PAINTED_ROADS -> _state.value.paintedRoads
        MapLayerKind.SPEED_CAMERAS -> _state.value.speedCameras
        MapLayerKind.ALPR_CAMERAS -> _state.value.alprCameras
        MapLayerKind.TRAFFIC_CONTROLS -> _state.value.trafficControls
        MapLayerKind.FUEL_PRICES -> _state.value.fuelPrices
        MapLayerKind.BRIDGE_OPENINGS -> _state.value.bridgeOpenings
    }

    private fun enabledKinds(): List<MapLayerKind> = MapLayerKind.entries.filter(::enabled)

    private fun minZoom(kind: MapLayerKind): Double = when (kind) {
        MapLayerKind.PAINTED_ROADS -> PAINTED_MIN_ZOOM
        MapLayerKind.TRAFFIC_CONTROLS -> CONTROL_MIN_ZOOM
        MapLayerKind.SPEED_CAMERAS, MapLayerKind.ALPR_CAMERAS -> CAMERA_MIN_ZOOM
        MapLayerKind.FUEL_PRICES, MapLayerKind.BRIDGE_OPENINGS -> 0.0
    }

    private fun count(kind: MapLayerKind): Int = when (kind) {
        MapLayerKind.PAINTED_ROADS -> _state.value.paintedMarks.size
        MapLayerKind.SPEED_CAMERAS -> _state.value.speedCameraPoints.size
        MapLayerKind.ALPR_CAMERAS -> _state.value.alprCameraPoints.size
        MapLayerKind.TRAFFIC_CONTROLS -> _state.value.controlPoints.size
        MapLayerKind.FUEL_PRICES -> _state.value.fuelPoints.size
        MapLayerKind.BRIDGE_OPENINGS -> _state.value.bridgePoints.size
    }

    private fun clear(kind: MapLayerKind) {
        _state.value = when (kind) {
            MapLayerKind.PAINTED_ROADS -> _state.value.copy(paintedMarks = emptyList())
            MapLayerKind.SPEED_CAMERAS -> _state.value.copy(speedCameraPoints = emptyList())
            MapLayerKind.ALPR_CAMERAS -> _state.value.copy(alprCameraPoints = emptyList())
            MapLayerKind.TRAFFIC_CONTROLS -> _state.value.copy(controlPoints = emptyList())
            MapLayerKind.FUEL_PRICES -> _state.value.copy(fuelPoints = emptyList())
            MapLayerKind.BRIDGE_OPENINGS -> _state.value.copy(bridgePoints = emptyList())
        }
        boxes.remove(kind.key)
    }

    private fun cancel(kind: MapLayerKind) {
        jobs.remove(kind.key)?.cancel()
        generations[kind.key] = (generations[kind.key] ?: 0) + 1
    }

    private fun updateStatus(kind: MapLayerKind, phase: String, count: Int) {
        val next = status(kind, phase, count)
        _state.value = _state.value.copy(
            layerStatus = _state.value.layerStatus.filterNot { it.kind == kind.key } + next,
        )
    }

    private fun status(kind: MapLayerKind, phase: String, count: Int): MapLayerStatus =
        MapLayerStatus(kind.key, phase, count, minZoom(kind))

    private data class Viewport(
        val south: Double,
        val west: Double,
        val north: Double,
        val east: Double,
        val zoom: Double,
    ) {
        val centerLat: Double get() = (south + north) / 2
        val centerLng: Double get() = (west + east) / 2

        /** The same 50 % padding on each side as Android's area-cached layers. */
        fun padded(): Box {
            val padLat = (north - south) * 0.5
            val padLng = (east - west) * 0.5
            return Box(south - padLat, west - padLng, north + padLat, east + padLng)
        }
    }

    private data class Box(
        val south: Double,
        val west: Double,
        val north: Double,
        val east: Double,
    ) {
        /** True while the camera center sits in the inner half of the covered box. */
        fun containsInner(lat: Double, lng: Double): Boolean {
            val insLat = (north - south) * 0.25
            val insLng = (east - west) * 0.25
            return lat in (south + insLat)..(north - insLat) &&
                lng in (west + insLng)..(east - insLng)
        }
    }

    private data class PoiPrefs(
        val showPlaces: Boolean,
        val food: Boolean,
        val fuel: Boolean,
        val transit: Boolean,
        val parking: Boolean,
        val other: Boolean,
        val density: String,
        val classes: List<String>?,
        val groups: List<String>,
    )

    companion object {
        const val KEY_PAINTED = "painted_roads_on"
        const val KEY_SPEED = "speed_cameras_on"
        const val KEY_ALPR = "flock_cameras_on"
        const val KEY_CONTROLS = "traffic_controls_on"
        const val KEY_FUEL = "fuel_prices_on"
        const val KEY_BRIDGES = "bridge_layer_on"
        /** Android's Traffic.KEY. */
        const val KEY_TRAFFIC = "traffic_on"
        /** Android's SatelliteLayer.KEY. */
        const val KEY_SATELLITE = "satellite_on"
        /** Android's `map_poi_icon_scale` (MapPoiPrefs.KEY_SCALE); Android has no `poi_icons` key. */
        const val KEY_ICON_SCALE = "map_poi_icon_scale"
        /** Android's `map_places_source` (MapPoiPrefs.KEY_PLACES_SOURCE). */
        const val KEY_POI_SOURCE = "map_places_source"
        /** New on iOS: which family draws the two camera layers. */
        const val KEY_CAMERA_SOURCE = "camera_source"
        const val KEY_POIS = "map_show_pois"
        const val KEY_TRANSIT = "map_show_transit_stops"
        const val KEY_CIVIC = "map_show_civic_pois"
        const val KEY_FOOD = "map_show_food_pois"
        const val KEY_FUEL_POIS = "map_show_fuel_pois"
        const val KEY_PARKING = "map_show_parking_pois"
        const val KEY_DENSITY = "map_poi_density"

        const val PAINTED_MIN_ZOOM = PaintedMarks.MIN_ZOOM
        const val CONTROL_MIN_ZOOM = 16.0
        const val CAMERA_MIN_ZOOM = 11.0
        val CAMERA_KINDS = listOf(MapLayerKind.SPEED_CAMERAS, MapLayerKind.ALPR_CAMERAS)
        const val CAMERA_MERGE_M = 20.0
        const val CONTROL_MERGE_M = 30.0
        const val CAMERA_CAP = 600
        const val CONTROL_CAP = 400
        const val FUEL_CAP = 300
        const val BRIDGE_CAP = 300
        const val FUEL_RECHECK_MS = 3L * 60 * 60 * 1000
        const val BRIDGE_RECHECK_MS = 5L * 60 * 1000

        private const val UNAVAILABLE = "unavailable"

        /** Android's chips: 0.7 small, 1.0 default, 1.25 large; a pushed value is bounded. */
        internal fun poiIconScale(raw: Float): Float =
            if (raw.isNaN()) 1f else raw.coerceIn(0.5f, 2f)

        private fun round6(v: Double): Long = (v * 1_000_000.0).toLong()

        private fun pence(raw: Int): Double = if (raw < 0) -1.0 else raw / 100.0

        /** Drops points closer than [radiusM] to one already kept, preserving input order. A
         *  duplicate that carries the facing keeps it when the kept point had none: OSM maps one
         *  node per head, and dropping the tagged head would remove the only direction wedge. */
        internal fun declutter(points: List<MapPoint>, radiusM: Double): List<MapPoint> {
            val kept = ArrayList<MapPoint>(points.size)
            for (p in points) {
                val near = kept.indexOfFirst { distanceM(it, p) <= radiusM }
                if (near < 0) {
                    kept += p
                } else if (kept[near].direction == null && p.direction != null) {
                    kept[near] = kept[near].copy(direction = p.direction)
                }
            }
            return kept
        }

        internal fun declutterByKind(points: List<MapControlPoint>, radiusM: Double): List<MapControlPoint> {
            val kept = ArrayList<MapControlPoint>(points.size)
            for (p in points) {
                val at = MapPoint(p.lat, p.lng)
                if (kept.none { it.kind == p.kind && distanceM(MapPoint(it.lat, it.lng), at) <= radiusM }) {
                    kept += p
                }
            }
            return kept
        }

        /** Keeps at most [cap] items, nearest to the view center first, in their original order. */
        private fun capNearestPoints(items: List<MapPoint>, at: Viewport, cap: Int): List<MapPoint> {
            if (items.size <= cap) return items
            val center = MapPoint(at.centerLat, at.centerLng)
            val keep = items.sortedBy { distanceM(center, it) }.take(cap).toSet()
            return items.filter { it in keep }
        }

        private fun capNearestControls(
            items: List<MapControlPoint>,
            at: Viewport,
            cap: Int,
        ): List<MapControlPoint> {
            if (items.size <= cap) return items
            val center = MapPoint(at.centerLat, at.centerLng)
            val keep = items
                .sortedBy { distanceM(center, MapPoint(it.lat, it.lng)) }
                .take(cap)
                .toSet()
            return items.filter { it in keep }
        }

        private const val EARTH_M_PER_DEG = 111_320.0

        internal fun distanceM(a: MapPoint, b: MapPoint): Double {
            val dLat = (a.lat - b.lat) * EARTH_M_PER_DEG
            val dLng = (a.lng - b.lng) * EARTH_M_PER_DEG * cos(((a.lat + b.lat) / 2).toRadians())
            return kotlin.math.sqrt(dLat * dLat + dLng * dLng)
        }

        private fun Double.toRadians(): Double = this * kotlin.math.PI / 180.0

        /** Offsets a line's vertices by [offsetM] to the right of its direction, at real scale. */
        internal fun offsetPoints(points: List<MapPoint>, offsetM: Double): List<MapPoint> {
            if (points.size < 2) return points
            if (abs(offsetM) < 1e-6) return points
            return points.mapIndexed { index, p ->
                val before = points[(index - 1).coerceAtLeast(0)]
                val after = points[(index + 1).coerceAtMost(points.lastIndex)]
                val heading = bearing(before, after)
                val destination = LatLng(p.lat, p.lng).destinationPoint(abs(offsetM), heading + if (offsetM > 0) 90.0 else -90.0)
                MapPoint(destination.lat, destination.lng)
            }
        }

        private fun bearing(a: MapPoint, b: MapPoint): Double =
            LatLng(a.lat, a.lng).bearingTo(LatLng(b.lat, b.lng))

    }
}

/**
 * Where the businesses on the browse map come from. Android's three values are `open` (the Vela
 * places layer), `google` (its ambient fan-out) and `both`. iOS draws the same pack for `vela` and
 * the OpenFreeMap vector tiles for `tiles`; the key and the `both` value are shared, and the older
 * Android spellings are migrated on read.
 */
object PoiSources {
    const val TILES = "tiles"
    const val VELA = "vela"
    const val BOTH = "both"

    fun normalize(raw: String?): String = when (raw?.trim()?.lowercase()) {
        VELA, "open" -> VELA
        TILES, "google" -> TILES
        else -> BOTH
    }

    fun showsTiles(source: String): Boolean = normalize(source) != VELA

    fun showsVela(source: String): Boolean = normalize(source) != TILES
}

/**
 * Where the two camera layers draw from. `auto` follows the style: the live Overpass query while
 * the map is online, the pack over a downloaded region. `live` and `pack` are explicit and never
 * fall back to each other. Swift reads the same value from [LayersState.cameraSource].
 */
object CameraSources {
    const val AUTO = "auto"
    const val LIVE = "live"
    const val PACK = "pack"

    fun normalize(raw: String?): String = when (raw?.trim()?.lowercase()) {
        LIVE -> LIVE
        PACK -> PACK
        else -> AUTO
    }
}

/** The five sheet groups, used to filter the bundled Vela pack by its `group` property. */
internal object PoiGroups {
    val ALL = listOf("food", "fuel", "transit", "parking", "other")

    /** The groups to keep; empty when every category is on and no filter is needed. */
    fun visible(
        food: Boolean, fuel: Boolean, transit: Boolean, parking: Boolean, other: Boolean,
    ): List<String> {
        if (food && fuel && transit && parking && other) return emptyList()
        return listOfNotNull(
            "food".takeIf { food },
            "fuel".takeIf { fuel },
            "transit".takeIf { transit },
            "parking".takeIf { parking },
            "other".takeIf { other },
        )
    }
}

/** The OSM POI `class` values each sheet category owns. */
internal object PoiClasses {
    val FOOD = setOf(
        "restaurant", "fast_food", "cafe", "bar", "pub", "biergarten",
        "food_and_drink", "ice_cream", "drinking_water",
    )
    val FUEL = setOf("fuel", "charging_station", "gas")
    val TRANSIT = setOf(
        "bus", "rail", "railway", "tram", "airport", "ferry_terminal",
        "subway", "station", "halt", "bus_station",
    )
    val PARKING = setOf("parking", "parking_garage", "parking_lot", "bicycle_parking")
    val OTHER = setOf(
        "art_gallery", "attraction", "camera", "castle", "cinema", "college",
        "commercial", "dentist", "doctors", "garden", "golf", "hospital",
        "hotel", "information", "library", "lodging", "marker", "monument",
        "museum", "park", "pharmacy", "place_of_worship", "police", "post",
        "school", "shop", "stadium", "supermarket", "theatre", "town_hall",
        "viewpoint", "zoo",
    )

    /** The classes to keep, or null when every category is on and no filter is needed. */
    fun visible(
        food: Boolean, fuel: Boolean, transit: Boolean, parking: Boolean, other: Boolean,
    ): List<String>? {
        if (food && fuel && transit && parking && other) return null
        val out = LinkedHashSet<String>()
        if (food) out += FOOD
        if (fuel) out += FUEL
        if (transit) out += TRANSIT
        if (parking) out += PARKING
        if (other) out += OTHER
        return out.toList()
    }
}
