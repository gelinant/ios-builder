package app.vela.ios.map

import app.vela.core.platform.Cancellable
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.PlatformFiles
import app.vela.core.platform.VelaHttp
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest

/** The layer switches and their fetch gates, without a map or a network. */
@OptIn(ExperimentalCoroutinesApi::class)
class LayersStoreTest {
    private val sf = doubleArrayOf(37.770, -122.430, 37.780, -122.410)

    @Test fun switchesPersistAndNoFetchHappensBeforeEnabling() = runTest {
        val stores = MemStores()
        val http = FakeHttp { req -> ok(cameras(req), req) }
        val first = store(stores, http)
        first.start()
        first.onViewport(sf[0], sf[1], sf[2], sf[3], 17.0)
        advanceUntilIdle()
        assertEquals(0, http.requests.size, "every layer is off by default")

        first.setEnabled(MapLayerKind.SPEED_CAMERAS, true)
        advanceUntilIdle()
        assertEquals(1, http.requests.size)
        assertEquals("ready", status(first, MapLayerKind.SPEED_CAMERAS).phase)
        assertEquals(2, status(first, MapLayerKind.SPEED_CAMERAS).count)

        val second = store(stores, FakeHttp { req -> ok(cameras(req), req) })
        second.start()
        assertTrue(second.state.value.speedCameras, "the switch survives a new process")
    }

    @Test fun trafficSatelliteAndIconSizePersistUnderTheAndroidKeys() = runTest {
        val stores = MemStores()
        val first = store(stores, FakeHttp { req -> ok(cameras(req), req) })
        first.start()
        assertEquals(false, first.state.value.trafficOn)
        assertEquals(false, first.state.value.satelliteOn)
        assertEquals(1f, first.state.value.poiIconScale)

        first.setSwitch("traffic", true)
        first.setSwitch("satellite", true)
        first.setPoiIconScale(1.25f)
        assertEquals(0, first.state.value.layerStatus.sumOf { if (it.phase == "loading") 1 else 0 })

        val second = store(stores, FakeHttp { req -> ok(cameras(req), req) })
        second.start()
        assertTrue(second.state.value.trafficOn)
        assertTrue(second.state.value.satelliteOn)
        assertEquals(1.25f, second.state.value.poiIconScale)

        second.setPoiIconScale(9f)
        assertEquals(2f, second.state.value.poiIconScale, "a pushed value is bounded")
    }

    @Test fun trafficAndSatelliteKeysMatchAndroid() {
        assertEquals("traffic_on", LayersStore.KEY_TRAFFIC)
        assertEquals("satellite_on", LayersStore.KEY_SATELLITE)
        assertEquals("map_poi_icon_scale", LayersStore.KEY_ICON_SCALE)
    }

    @Test fun lowZoomIsGatedWithoutARequest() = runTest {
        val http = FakeHttp { req -> ok(cameras(req), req) }
        val store = store(MemStores(), http)
        store.start()
        store.setEnabled(MapLayerKind.SPEED_CAMERAS, true)
        store.onViewport(sf[0], sf[1], sf[2], sf[3], 10.0)
        advanceUntilIdle()
        assertEquals(0, http.requests.size)
        assertEquals("zoom", status(store, MapLayerKind.SPEED_CAMERAS).phase)
    }

    @Test fun aPaddedBoxIsReusedUntilItsInnerHalfIsLeft() = runTest {
        val http = FakeHttp { req -> ok(cameras(req), req) }
        val store = store(MemStores(), http)
        store.start()
        store.setEnabled(MapLayerKind.SPEED_CAMERAS, true)
        store.onViewport(sf[0], sf[1], sf[2], sf[3], 17.0)
        advanceUntilIdle()
        assertEquals(1, http.requests.size)

        store.onViewport(sf[0] + 0.001, sf[1] + 0.001, sf[2] + 0.001, sf[3] + 0.001, 17.0)
        advanceUntilIdle()
        assertEquals(1, http.requests.size, "a small pan inside the cached box is free")

        store.onViewport(sf[0] + 0.4, sf[1] + 0.4, sf[2] + 0.4, sf[3] + 0.4, 17.0)
        advanceUntilIdle()
        assertEquals(2, http.requests.size)
    }

    @Test fun aFailedFetchIsNotCachedAndTheNextViewportRetries() = runTest {
        var fail = true
        val http = FakeHttp { req ->
            if (fail) HttpResponse(503, emptyList(), ByteArray(0), req.url) else ok(cameras(req), req)
        }
        val store = store(MemStores(), http)
        store.start()
        store.setEnabled(MapLayerKind.SPEED_CAMERAS, true)
        store.onViewport(sf[0], sf[1], sf[2], sf[3], 17.0)
        advanceUntilIdle()
        assertEquals("error", status(store, MapLayerKind.SPEED_CAMERAS).phase)

        fail = false
        store.onViewport(sf[0] + 0.4, sf[1] + 0.4, sf[2] + 0.4, sf[3] + 0.4, 17.0)
        advanceUntilIdle()
        assertEquals("ready", status(store, MapLayerKind.SPEED_CAMERAS).phase)
        assertEquals(2, status(store, MapLayerKind.SPEED_CAMERAS).count)
    }

    @Test fun paintedRoadsFetchOnlyAtCloseZoomAndBuildMarks() = runTest {
        val http = FakeHttp { req -> ok(painted(req), req) }
        val store = store(MemStores(), http)
        store.start()
        store.setEnabled(MapLayerKind.PAINTED_ROADS, true)
        store.onViewport(sf[0], sf[1], sf[2], sf[3], 15.0)
        advanceUntilIdle()
        assertEquals(0, http.requests.size)

        store.onViewport(sf[0], sf[1], sf[2], sf[3], 17.0)
        advanceUntilIdle()
        assertEquals(1, http.requests.size)
        assertEquals("ready", status(store, MapLayerKind.PAINTED_ROADS).phase)
        assertTrue(store.state.value.paintedMarks.isNotEmpty())
    }

    @Test fun controlsCollapsePerKindAndKeepTheirKind() = runTest {
        val http = FakeHttp { req -> ok(controls(req), req) }
        val store = store(MemStores(), http)
        store.start()
        store.setEnabled(MapLayerKind.TRAFFIC_CONTROLS, true)
        store.onViewport(sf[0], sf[1], sf[2], sf[3], 17.0)
        advanceUntilIdle()
        val kinds = store.state.value.controlPoints.map { it.kind }.toSet()
        assertEquals(setOf("SIGNAL", "STOP"), kinds)
        assertEquals(2, store.state.value.controlPoints.size, "four approaches collapse to one signal")
    }

    @Test fun fuelAndBridgesAreUnavailableOutsideTheirCountriesWithoutARequest() = runTest {
        val http = FakeHttp { req -> ok("""{"elements":[]}""", req) }
        val store = store(MemStores(), http)
        store.start()
        store.setEnabled(MapLayerKind.FUEL_PRICES, true)
        store.setEnabled(MapLayerKind.BRIDGE_OPENINGS, true)
        store.onViewport(sf[0], sf[1], sf[2], sf[3], 12.0)
        advanceUntilIdle()
        assertEquals(0, http.requests.size)
        assertEquals("unavailable", status(store, MapLayerKind.FUEL_PRICES).phase)
        assertEquals("unavailable", status(store, MapLayerKind.BRIDGE_OPENINGS).phase)
    }

    @Test fun poiCategoriesAndDensityPersist() = runTest {
        val stores = MemStores()
        val store = store(stores, FakeHttp { req -> ok("""{"elements":[]}""", req) })
        store.start()
        assertFalse(store.state.value.poiFiltered)
        store.setPoiCategory("food", false)
        assertTrue(store.state.value.poiFiltered)
        assertFalse(store.state.value.visiblePoiClasses.contains("restaurant"))
        assertTrue(store.state.value.visiblePoiClasses.contains("fuel"))
        store.setPoiDensity("compact")

        val second = store(stores, FakeHttp { req -> ok("""{"elements":[]}""", req) })
        second.start()
        assertEquals("compact", second.state.value.poiDensity)
        assertTrue(second.state.value.poiFiltered)
    }

    @Test fun poiClassListsCoverTheFourSheetCategories() {
        val all = PoiClasses.visible(true, true, true, true, true)
        assertNull(all, "no filter when every category is on")
        val foodOnly = PoiClasses.visible(true, false, false, false, false).orEmpty()
        assertTrue("restaurant" in foodOnly)
        assertFalse("fuel" in foodOnly)
        assertFalse("parking" in foodOnly)
        val transit = PoiClasses.visible(false, false, true, false, false).orEmpty()
        assertTrue("rail" in transit)
        assertFalse("restaurant" in transit)
    }

    @Test fun poiSourcePersistsUnderTheAndroidKeyAndMigratesAndroidValues() = runTest {
        assertEquals("map_places_source", LayersStore.KEY_POI_SOURCE)
        val stores = MemStores()
        val first = store(stores, FakeHttp { req -> ok("""{"elements":[]}""", req) })
        first.start()
        assertEquals(PoiSources.BOTH, first.state.value.poiSource, "both keeps the map drawn everywhere")

        first.setPoiSource(PoiSources.VELA)
        assertEquals(PoiSources.VELA, first.state.value.poiSource)
        val second = store(stores, FakeHttp { req -> ok("""{"elements":[]}""", req) })
        second.start()
        assertEquals(PoiSources.VELA, second.state.value.poiSource, "the choice survives a new process")

        second.setPoiSource("open")
        assertEquals(PoiSources.VELA, second.state.value.poiSource, "Android's open means Vela")
        second.setPoiSource("google")
        assertEquals(PoiSources.TILES, second.state.value.poiSource, "Android's google means tiles")
        second.setPoiSource("nonsense")
        assertEquals(PoiSources.BOTH, second.state.value.poiSource)
    }

    @Test fun poiSourceDecidesWhichLayersCanDraw() {
        assertTrue(PoiSources.showsTiles(PoiSources.TILES))
        assertFalse(PoiSources.showsVela(PoiSources.TILES))
        assertFalse(PoiSources.showsTiles(PoiSources.VELA))
        assertTrue(PoiSources.showsVela(PoiSources.VELA))
        assertTrue(PoiSources.showsTiles(PoiSources.BOTH))
        assertTrue(PoiSources.showsVela(PoiSources.BOTH))
    }

    @Test fun iconScaleAppliesToEveryPoiSource() = runTest {
        val store = store(MemStores(), FakeHttp { req -> ok("""{"elements":[]}""", req) })
        store.start()
        for (source in listOf(PoiSources.TILES, PoiSources.VELA, PoiSources.BOTH)) {
            store.setPoiSource(source)
            for (scale in listOf(0.7f, 1f, 1.25f)) {
                store.setPoiIconScale(scale)
                assertEquals(scale, store.state.value.poiIconScale, "source $source, size $scale")
            }
        }
        store.setPoiIconScale(0.1f)
        assertEquals(0.5f, store.state.value.poiIconScale, "a pushed value is bounded")
        store.setPoiIconScale(Float.NaN)
        assertEquals(1f, store.state.value.poiIconScale)
    }

    @Test fun poiGroupsFollowTheCategories() = runTest {
        val store = store(MemStores(), FakeHttp { req -> ok("""{"elements":[]}""", req) })
        store.start()
        assertTrue(store.state.value.visiblePoiGroups.isEmpty(), "no filter when every category is on")
        store.setPoiCategory("transit", false)
        assertFalse("transit" in store.state.value.visiblePoiGroups)
        assertTrue("food" in store.state.value.visiblePoiGroups)
        store.setPoiCategory("food", false)
        store.setPoiCategory("fuel", false)
        store.setPoiCategory("parking", false)
        store.setPoiCategory("other", false)
        assertTrue(store.state.value.poiFiltered, "a filter is still active")
        assertTrue(store.state.value.visiblePoiGroups.isEmpty(), "every group off leaves no group")
    }

    @Test fun paintedOffsetsMoveTheLineSideways() {
        val line = listOf(MapPoint(0.0, 0.0), MapPoint(0.0, 0.001))
        val shifted = LayersStore.offsetPoints(line, 3.0)
        assertEquals(0.0, shifted.first().lng, 1e-9)
        assertNotEquals(0.0, shifted.first().lat)
        assertTrue(shifted.first().lat < 0.0, "positive offset is right of an eastbound line")
    }

    private fun TestScope.store(stores: MemStores, http: VelaHttp): LayersStore =
        LayersStore(
            stores = stores,
            http = http,
            scope = CoroutineScope(StandardTestDispatcher(testScheduler)),
            files = MemoryFiles(),
            now = { 0L },
            background = StandardTestDispatcher(testScheduler),
        )

    private fun status(store: LayersStore, kind: MapLayerKind): MapLayerStatus =
        store.state.value.layerStatus.first { it.kind == kind.key }

    private fun cameras(req: HttpRequest): String {
        val second = if ("surveillance" in req.url) "37.7770" else "37.7772"
        return """{"elements":[{"lat":37.7750,"lon":-122.4200},{"lat":$second,"lon":-122.4199}]}"""
    }

    private fun controls(req: HttpRequest): String = """
        {"elements":[
          {"lat":37.7750,"lon":-122.4200,"tags":{"highway":"traffic_signals"}},
          {"lat":37.77501,"lon":-122.42001,"tags":{"highway":"traffic_signals"}},
          {"lat":37.77502,"lon":-122.42002,"tags":{"highway":"traffic_signals"}},
          {"lat":37.77503,"lon":-122.42003,"tags":{"highway":"traffic_signals"}},
          {"lat":37.7790,"lon":-122.4150,"tags":{"highway":"stop"}}
        ]}
    """.trimIndent()

    private fun painted(req: HttpRequest): String = """
        {"elements":[
          {"type":"way","tags":{"highway":"secondary","lanes":"4","oneway":"no","surface":"asphalt"},
           "geometry":[{"lat":37.7748,"lon":-122.4210},{"lat":37.7750,"lon":-122.4190}]},
          {"type":"node","lat":37.7750,"lon":-122.4200,"tags":{"highway":"traffic_signals"}}
        ]}
    """.trimIndent()

    private fun ok(body: String, req: HttpRequest) =
        HttpResponse(200, emptyList(), body.encodeToByteArray(), req.url)
}

private class FakeHttp(private val reply: (HttpRequest) -> HttpResponse) : VelaHttp {
    val requests = mutableListOf<HttpRequest>()

    override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
        requests += request
        try {
            callback(reply(request), null)
        } catch (e: Exception) {
            callback(null, e)
        }
        return Cancellable { }
    }
}

private class MemStores : KeyValueStores {
    private val stores = mutableMapOf<String, MemStore>()

    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { MemStore() }
}

private class MemStore : KeyValueStore {
    private val values = mutableMapOf<String, Any>()

    override fun contains(key: String) = values.containsKey(key)
    override fun getString(key: String, default: String?): String? = values[key] as? String ?: default
    override fun getLong(key: String, default: Long): Long = values[key] as? Long ?: default
    override fun getInt(key: String, default: Int): Int = values[key] as? Int ?: default
    override fun getBoolean(key: String, default: Boolean): Boolean = values[key] as? Boolean ?: default
    override fun getFloat(key: String, default: Float): Float = values[key] as? Float ?: default
    override fun keys(): Set<String> = values.keys.toSet()

    override fun edit(): KeyValueEditor = object : KeyValueEditor {
        private val changes = mutableMapOf<String, Any?>()
        private var clear = false

        override fun putString(key: String, value: String?): KeyValueEditor = applyChange(key, value)
        override fun putLong(key: String, value: Long): KeyValueEditor = applyChange(key, value)
        override fun putInt(key: String, value: Int): KeyValueEditor = applyChange(key, value)
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = applyChange(key, value)
        override fun putFloat(key: String, value: Float): KeyValueEditor = applyChange(key, value)
        override fun remove(key: String): KeyValueEditor = applyChange(key, null)
        override fun clear(): KeyValueEditor { clear = true; return this }

        private fun applyChange(key: String, value: Any?): KeyValueEditor {
            changes[key] = value
            return this
        }

        override fun apply() {
            if (clear) values.clear()
            for ((key, value) in changes) {
                if (value == null) values.remove(key) else values[key] = value
            }
        }

        override fun commit(): Boolean { apply(); return true }
    }
}

/** [PlatformFiles] in memory, enough for a fuel store that is never asked to download. */
private class MemoryFiles : PlatformFiles {
    private val files = mutableMapOf<String, ByteArray>()
    override val filesDir: String get() = "/files"
    override val cacheDir: String get() = "/cache"
    override val noBackupDir: String get() = "/nobackup"
    override fun exists(path: String) = files.containsKey(path)
    override fun isDirectory(path: String) = files.keys.any { it.startsWith("$path/") }
    override fun size(path: String) = files[path]?.size?.toLong() ?: 0L
    override fun lastModifiedMillis(path: String) = 0L
    override fun list(path: String): List<app.vela.core.platform.FileEntry>? = emptyList()
    override fun mkdirs(path: String) = true
    override fun readBytes(path: String) = files[path] ?: throw IllegalStateException("missing $path")
    override fun readText(path: String) = (files[path] ?: throw IllegalStateException("missing $path")).decodeToString()
    override fun writeBytes(path: String, bytes: ByteArray) { files[path] = bytes }
    override fun writeText(path: String, text: String) { files[path] = text.encodeToByteArray() }
    override fun writeTextAtomic(path: String, text: String) { files[path] = text.encodeToByteArray() }
    override fun delete(path: String): Boolean = files.remove(path) != null
    override fun deleteRecursively(path: String): Boolean {
        val hit = files.keys.filter { it == path || it.startsWith("$path/") }
        hit.forEach { files.remove(it) }
        return true
    }
    override fun rename(from: String, to: String): Boolean {
        val data = files.remove(from) ?: return false
        files[to] = data
        return true
    }
}
