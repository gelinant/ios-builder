package app.vela.ios.streetview

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.SearchResult
import app.vela.core.model.StreetViewLink
import app.vela.core.model.StreetViewPano
import app.vela.core.platform.Cancellable
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.ios.MemFiles
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

private const val PANO = "panoAAAAAAAAAAAAAAAAAA"
private const val NEIGHBOR = "neighborBBBBBBBBBBBBBB"

private fun pano(id: String = PANO, heading: Double = 30.0, label: String? = "620 G St, Davis, CA") =
    StreetViewPano(
        panoId = id, lat = 38.5449, lng = -121.7405, headingDeg = heading,
        tileSize = 512, maxZoom = 4,
        levelDims = listOf(512 to 256, 1024 to 512, 2048 to 1024, 4096 to 2048),
        addressLabel = label, copyright = "© 2026 Google", captureYear = 2025, captureMonth = 5,
        neighbors = listOf(StreetViewLink(NEIGHBOR, 38.5450, -121.7404, 12.0, 8.0)),
    )

/** Answers Street View calls from the test and records what it was asked. */
private class StreetSource : MapDataSource {
    var nearest: StreetViewPano? = null
    val byPano = mutableMapOf<String, StreetViewPano>()
    val nearestCalls = mutableListOf<String?>()
    val byIdCalls = mutableListOf<String>()
    val tileCalls = mutableListOf<String>()
    val tiles = mutableMapOf<String, ByteArray>()

    override suspend fun streetView(location: LatLng, preferStreet: String?): StreetViewPano? {
        nearestCalls += preferStreet
        return nearest
    }

    override suspend fun streetViewByPano(panoId: String): StreetViewPano? {
        byIdCalls += panoId
        return byPano[panoId]
    }

    override suspend fun streetViewTile(panoId: String, x: Int, y: Int, zoom: Int): ByteArray? {
        tileCalls += "$panoId/$zoom/$x/$y"
        return tiles["$panoId/$zoom/$x/$y"]
    }

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult =
        error("unused")

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: app.vela.core.model.TravelMode,
        waypoints: List<LatLng>, avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean,
        urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<app.vela.core.model.Route> = error("unused")
}

private class RecordingHttp(private val body: ByteArray = byteArrayOf(9, 8, 7)) : VelaHttp {
    val requests = mutableListOf<HttpRequest>()
    override fun execute(request: HttpRequest, callback: (HttpResponse?, Throwable?) -> Unit): Cancellable {
        requests += request
        callback(HttpResponse(200, emptyList(), body, request.url), null)
        return Cancellable {}
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class StreetViewStoreTest {
    /** The viewer only runs with Google on; another test class may flip the process switch. */
    @BeforeTest fun googleOn() {
        NoGoogle.enabled = false
    }

    @AfterTest fun googleBackOn() {
        NoGoogle.enabled = false
    }

    private fun TestScope.store(
        source: StreetSource,
        files: MemFiles? = null,
        http: VelaHttp? = null,
        headers: List<app.vela.core.platform.HttpHeader> = emptyList(),
    ) = StreetViewStore(
        source = { source },
        scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler)),
        http = http,
        tileHeaders = { headers },
        files = files,
        io = StandardTestDispatcher(testScheduler),
    )

    @Test fun `open asks for the address street and keeps Google's capture heading`() = runTest {
        val source = StreetSource().apply { nearest = pano() }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA 95616", null, 12.0)
        advanceUntilIdle()

        val state = store.state.value
        assertFalse(state.loading)
        assertNull(state.error)
        val shown = assertNotNull(state.pano)
        assertEquals(PANO, shown.panoId)
        assertEquals(30.0, shown.headingDeg)          // texture reference, never overwritten
        assertEquals(12.0, shown.initialFacingDeg)    // the place's own direction
        assertEquals(listOf<String?>("g st"), source.nearestCalls)
        assertTrue(source.byIdCalls.isEmpty())
    }

    @Test fun `a thumbnail pano is fetched by id before any nearest lookup`() = runTest {
        val source = StreetSource().apply {
            byPano[PANO] = pano()
            nearest = pano("otherCCCCCCCCCCCCCCCCC")
        }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", PANO, Double.NaN)
        advanceUntilIdle()

        assertEquals(listOf(PANO), source.byIdCalls)
        assertTrue(source.nearestCalls.isEmpty())
        assertEquals(PANO, store.state.value.pano?.panoId)
    }

    @Test fun `a failed by-id fetch falls back to the nearest pano`() = runTest {
        val source = StreetSource().apply { nearest = pano() }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", "missingPanoid000000000", 5.0)
        advanceUntilIdle()

        assertEquals(listOf("missingPanoid000000000"), source.byIdCalls)
        assertEquals(listOf<String?>("g st"), source.nearestCalls)
        assertEquals(PANO, store.state.value.pano?.panoId)
    }

    @Test fun `no imagery is reported without inventing a pano`() = runTest {
        val source = StreetSource()
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        val state = store.state.value
        assertNull(state.pano)
        assertFalse(state.loading)
        assertEquals("no_imagery", state.error)
    }

    @Test fun `walk fetches the neighbor by pano id and faces the walk direction`() = runTest {
        val source = StreetSource().apply {
            nearest = pano()
            byPano[NEIGHBOR] = pano(NEIGHBOR, heading = 100.0, label = "G St")
        }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        store.walk(NEIGHBOR, 80.0)
        advanceUntilIdle()

        assertEquals(listOf(NEIGHBOR), source.byIdCalls)
        val shown = assertNotNull(store.state.value.pano)
        assertEquals(NEIGHBOR, shown.panoId)
        assertEquals(100.0, shown.headingDeg)
        assertEquals(80.0, shown.initialFacingDeg)
    }

    @Test fun `a walk to a missing pano keeps the current one and says why`() = runTest {
        val source = StreetSource().apply { nearest = pano() }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        store.walk(NEIGHBOR, Double.NaN)
        advanceUntilIdle()

        assertEquals(PANO, store.state.value.pano?.panoId)
        assertEquals("no_imagery", store.state.value.error)
    }

    @Test fun `a tile comes from the network once and then from the disk cache`() = runTest {
        val source = StreetSource().apply { tiles["$PANO/2/3/4"] = byteArrayOf(1, 2, 3) }
        val files = MemFiles()
        val store = store(source, files = files)
        val first = store.tile(PANO, 2, 3, 4)
        val second = store.tile(PANO, 2, 3, 4)

        assertContentEquals(byteArrayOf(1, 2, 3), first)
        assertContentEquals(byteArrayOf(1, 2, 3), second)
        assertEquals(1, source.tileCalls.size)
        assertTrue(files.exists("/cache/svtiles/${StreetViewTiles.cacheKey(PANO, 2, 3, 4)}.jpg"))
    }

    @Test fun `tiles go through the shared HTTP client and the given image headers`() = runTest {
        val http = RecordingHttp(byteArrayOf(4, 5, 6))
        val headers = listOf(
            app.vela.core.platform.HttpHeader("User-Agent", "Safari fixture"),
            app.vela.core.platform.HttpHeader("Referer", StreetViewTiles.REFERER),
        )
        val store = store(StreetSource(), http = http, headers = headers)

        assertContentEquals(byteArrayOf(4, 5, 6), store.tile(PANO, 1, 2, 3))

        assertEquals(1, http.requests.size)
        val request = http.requests.single()
        assertEquals(StreetViewTiles.url(PANO, 2, 3, 1), request.url)
        assertEquals("Safari fixture", request.headers.first { it.name == "User-Agent" }.value)
        assertEquals(StreetViewTiles.REFERER, request.headers.first { it.name == "Referer" }.value)
    }

    @Test fun `time travel loads the older capture and keeps the spot history and bearing`() = runTest {
        val old = "oldCCCCCCCCCCCCCCCCCCC"
        val history = listOf(
            app.vela.core.model.StreetViewTime(PANO, 2025, 5),
            app.vela.core.model.StreetViewTime(old, 2012, 7),
        )
        val base = pano().copy(history = history)
        val older = pano(old, heading = 200.0, label = "620 G St").copy(
            captureYear = 2012, captureMonth = 7,
            tileSize = 416, levelDims = listOf(416 to 208, 832 to 416, 1664 to 832),
        )
        val source = StreetSource().apply {
            nearest = base
            byPano[old] = older
        }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        store.timeTravel(app.vela.core.model.StreetViewTime(old, 2012, 7), 40.0)
        advanceUntilIdle()

        val state = store.state.value
        assertTrue(state.historical)
        assertFalse(state.loading)
        val shown = assertNotNull(state.pano)
        assertEquals(old, shown.panoId)
        assertEquals(200.0, shown.headingDeg)          // the older capture's own texture frame
        assertEquals(40.0, shown.initialFacingDeg)     // the compass bearing on screen is kept
        assertEquals(2012, shown.captureYear)
        assertEquals(7, shown.captureMonth)
        assertEquals(2, shown.history.size)            // the date chip comes back with the spot
        assertEquals(416, shown.tileSize)              // its own pre-2016 pyramid
        assertEquals(listOf(old), source.byIdCalls)

        store.timeTravel(app.vela.core.model.StreetViewTime(PANO, 2025, 5), 50.0)
        advanceUntilIdle()

        val back = assertNotNull(store.state.value.pano)
        assertEquals(PANO, back.panoId)
        assertEquals(30.0, back.headingDeg)
        assertEquals(2025, back.captureYear)
        assertFalse(store.state.value.historical)
    }

    @Test fun `a second visit to an older capture is answered from the metadata cache`() = runTest {
        val old = "oldCCCCCCCCCCCCCCCCCCC"
        val history = listOf(
            app.vela.core.model.StreetViewTime(PANO, 2025, 5),
            app.vela.core.model.StreetViewTime(old, 2012, 7),
        )
        val base = pano().copy(history = history)
        val source = StreetSource().apply {
            nearest = base
            byPano[old] = pano(old, heading = 200.0).copy(captureYear = 2012, captureMonth = 7)
        }
        val store = store(source, files = MemFiles())
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        store.timeTravel(app.vela.core.model.StreetViewTime(old, 2012, 7), 40.0)
        advanceUntilIdle()
        store.timeTravel(app.vela.core.model.StreetViewTime(PANO, 2025, 5), 40.0)
        advanceUntilIdle()
        store.timeTravel(app.vela.core.model.StreetViewTime(old, 2012, 7), 40.0)
        advanceUntilIdle()

        assertEquals(listOf(old), source.byIdCalls)
        assertEquals(old, store.state.value.pano?.panoId)
    }

    @Test fun `time travel without metadata keeps the base pyramid and invents no heading`() = runTest {
        val old = "oldCCCCCCCCCCCCCCCCCCC"
        val base = pano().copy(history = listOf(app.vela.core.model.StreetViewTime(old, 2012, 7)))
        val source = StreetSource().apply { nearest = base }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        store.timeTravel(app.vela.core.model.StreetViewTime(old, 2012, 7), 60.0)
        advanceUntilIdle()

        val shown = assertNotNull(store.state.value.pano)
        assertEquals(old, shown.panoId)
        assertEquals(30.0, shown.headingDeg)           // the base's, not a made-up one
        assertEquals(60.0, shown.initialFacingDeg)
        assertEquals(2012, shown.captureYear)
        assertTrue(store.state.value.historical)
    }

    @Test fun `close clears the pano and the in-flight work`() = runTest {
        val source = StreetSource().apply { nearest = pano() }
        val store = store(source)
        store.open(38.5449, -121.7405, "620 G St, Davis, CA", null, Double.NaN)
        advanceUntilIdle()

        store.close()
        advanceUntilIdle()

        assertNull(store.state.value.pano)
        assertNull(store.state.value.error)
        assertFalse(store.state.value.loading)
    }
}
