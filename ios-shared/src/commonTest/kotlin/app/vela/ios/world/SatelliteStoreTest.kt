package app.vela.ios.world

import app.vela.core.platform.Cancellable
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.VelaHttp
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * G-3: the CelesTrak cache, the two-hour politeness window, the stop on a non-200, the horizon and
 * viewport filters, the next pass and the invalid / deep-space / stale refusals, all without a
 * network.
 *
 * The element sets are a CelesTrak snapshot of 2026-10-29. The fixed instant is 2026-10-29T00:33Z;
 * at that instant HST is 6.5 degrees above the horizon of (0, 0) and ISS, CSS, METOP-C and SWIFT
 * are below it. The reference values come from an independent SGP4 implementation.
 */
class SatelliteStoreTest {
    private val now = 1_793_233_980_000L
    private val observerLat = 0.0
    private val observerLon = 0.0

    private val hst = """
        HST
        1 20580U 90037B   26301.53981808  .00004440  00000+0  13181-3 0  9996
        2 20580  28.4736 248.2212 0001869 190.0188 170.0372 15.32105918809034
    """.trimIndent()

    private val iss = """
        ISS (ZARYA)
        1 25544U 98067A   26301.59601386  .00005724  00000+0  11161-3 0  9990
        2 25544  51.6336 359.9178 0006994 320.4528  39.5949 15.49090321592436
    """.trimIndent()

    private val metop = """
        METOP-C
        1 43689U 18087A   26302.11361821  .00000103  00000+0  65476-4 0  9995
        2 43689  98.7041 266.2806 0001327  78.5291 281.6153 14.21485067395984
    """.trimIndent()

    private val swift = """
        SWIFT
        1 28485U 04047A   26301.85033915  .00002100  00000+0  92648-4 0  9993
        2 28485  20.5575 305.9852 0008096  82.8575 277.2484 15.03098443117115
    """.trimIndent()

    // Geostationary: SGP4 near-Earth refuses it, the store must not draw it.
    private val geo = """
        METEOSAT-9 (MSG-2)
        1 28912U 05049B   26301.91771722  .00000130  00000+0  00000+0 0  9990
        2 28912   9.6618  52.8151 0000854  37.1659 323.3913  1.00269021  8344
    """.trimIndent()

    // Broken line 1 checksum.
    private val broken = """
        BROKEN
        1 12345U 58002B   26301.50000000  .00000023  00000-0  28098-4 0  4754
        2 12345  34.2682 348.7242 1859667 331.7664  19.3264 10.82419157413667
    """.trimIndent()

    private val payload = listOf(hst, iss, metop, swift).joinToString("\n")

    private suspend fun snapshot(
        store: SatelliteStore,
        nowMs: Long = now,
        zoom: Double = 1.0,
        south: Double = -80.0,
        west: Double = -180.0,
        north: Double = 80.0,
        east: Double = 180.0,
    ): SatelliteSnapshot = assertNotNull(store.refresh(
        nowMs = nowMs, observerLatDeg = observerLat, observerLonDeg = observerLon,
        south = south, west = west, north = north, east = east, zoom = zoom))

    @Test fun freshDiskCacheAnswersWithoutRequestAndFiltersTheHorizon() = runTest {
        val stores = SatMemStores()
        // Fill the cache through a successful cycle, then reopen it with a client that must not be
        // asked anything: the fetch time and the TLE text live in the store.
        val filler = SatelliteStore(RoutingHttp { 200 }, stores)
        snapshot(filler)
        val http = RoutingHttp { 200 }
        val store = SatelliteStore(http, stores)

        val answer = snapshot(store, nowMs = now + 1_000L)
        assertEquals(0, http.requests.size, "the cache is fresh for two hours, no request")
        assertEquals(WorldLayerStatuses.FRESH, answer.phase)
        assertFalse(answer.live, "a cache answer is not a live fetch")
        assertEquals(1, answer.satellites.size, "only HST is above the horizon")
        assertEquals(20580, answer.satellites.single().catalogNumber)
        assertTrue(answer.rows.any { it.id == "satellite-20580" })
        assertFalse(answer.rows.any { it.id == "satellite-25544" }, "ISS is below the horizon")
        assertEquals(now, answer.updatedAtMs, "the sheet reads the fetch time, not the read time")
    }

    @Test fun oneRefreshCyclePerTwoHoursAndOneRequestPerGroup() = runTest {
        val http = RoutingHttp { 200 }
        val store = SatelliteStore(http, SatMemStores())

        snapshot(store)
        assertEquals(SatelliteStore.GROUPS.size, http.requests.size,
            "one request per group in the first cycle")
        val groups = http.requests.map { it.url.substringAfter("GROUP=").substringBefore("&") }
        assertEquals(SatelliteStore.GROUPS, groups)
        assertTrue(http.requests.all {
            it.url.startsWith(SatelliteStore.BASE_URL) && it.url.endsWith("FORMAT=tle")
        })

        snapshot(store, nowMs = now + SatelliteStore.CACHE_MS - 1)
        assertEquals(SatelliteStore.GROUPS.size, http.requests.size,
            "a second refresh inside two hours asks nothing")

        snapshot(store, nowMs = now + SatelliteStore.CACHE_MS)
        assertEquals(SatelliteStore.GROUPS.size * 2, http.requests.size,
            "the cycle reopens exactly at two hours")
    }

    @Test fun non200StopsTheCycleAndKeepsThePreviousData() = runTest {
        var failStations = false
        val http = RoutingHttp { group -> if (failStations && group == "stations") 503 else 200 }
        val store = SatelliteStore(http, SatMemStores())
        snapshot(store)
        val before = http.requests.size
        assertEquals(3, before)

        failStations = true
        val answer = snapshot(store, nowMs = now + SatelliteStore.CACHE_MS + 1_000L)
        assertEquals(before + 1, http.requests.size,
            "the first failing group stops the cycle, no other group is asked")
        val secondCycle = http.requests.drop(before)
        assertEquals(1, secondCycle.size)
        assertTrue(secondCycle.single().url.contains("GROUP=stations"))
        assertTrue(answer.detail.contains("HTTP 503"), answer.detail)
        assertEquals(now, answer.updatedAtMs, "the kept cache keeps its fetch time")
        assertEquals(4, answer.tleCount, "the four element sets are still cached and parsed")
        assertTrue(answer.rows.first().id == "sat-status", "the kept cache still builds rows")
        assertEquals(WorldLayerStatuses.LATE, answer.phase, "the kept data ages honestly")
    }

    @Test fun viewportFilterKeepsOnlyTheSatellitesInView() = runTest {
        val store = SatelliteStore(RoutingHttp { 200 }, SatMemStores())
        snapshot(store)

        val nearHst = snapshot(store, zoom = 5.0, south = 10.0, west = -12.0, north = 18.0,
            east = -3.0)
        assertEquals(listOf(20580), nearHst.satellites.map { it.catalogNumber })

        val empty = snapshot(store, zoom = 5.0, south = 40.0, west = 60.0, north = 50.0,
            east = 70.0)
        assertTrue(empty.satellites.isEmpty(), "HST is outside this viewport")

        val overview = snapshot(store, zoom = 1.0)
        assertEquals(1, overview.satellites.size, "at z1 the whole planet is the view")
    }

    @Test fun nextPassCarriesItsStartAndMaximumElevation() = runTest {
        val store = SatelliteStore(RoutingHttp { 200 }, SatMemStores())
        snapshot(store)

        val pass = assertNotNull(store.nextPass(20580, observerLat, observerLon, now),
            "HST must have a pass in the next 48 hours")
        val startMinutes = (pass.startMs - now) / 60_000.0
        assertTrue(startMinutes in 95.0..100.0, "the reference rise is at 97.5 min, got $startMinutes")
        assertTrue(pass.maxElevationDeg in 40.0..55.0,
            "the reference maximum is 48 deg, got ${pass.maxElevationDeg}")
        assertTrue(pass.maxElevationMs > pass.startMs)
        assertTrue(pass.endMs > pass.maxElevationMs)
        assertTrue(pass.maxElevationMs - pass.startMs in 300_000L..360_000L,
            "the reference maximum is 5.5 min after the rise")
    }

    @Test fun invalidDeepSpaceAndStaleElementSetsAreRefused() = runTest {
        val stale = """
            OLD
            1 11111U 58002B   26201.50000000  .00000023  00000-0  28098-4 0  4751
            2 11111  51.6336 348.7242 0500000 331.7664  19.3264 12.00000000 12344
        """.trimIndent()
        val http = RoutingHttp { 200 } // every group gets the same mixed payload
        val store = SatelliteStore(http, SatMemStores())
        val mixed = listOf(hst, iss, geo, broken, stale).joinToString("\n")
        val answer = store.parseFixture(
            text = mixed, atMs = now, stampMs = now,
            observerLatDeg = observerLat, observerLonDeg = observerLon,
            south = -80.0, west = -180.0, north = 80.0, east = 180.0, zoom = 1.0)

        assertEquals(listOf(20580), answer.satellites.map { it.catalogNumber })
        assertEquals(2, answer.tleCount, "HST and ISS parse and propagate")
        assertEquals(2, answer.skippedCount,
            "the geostationary and the 30-day-old element sets are refused")
        assertFalse(answer.rows.any { it.id == "satellite-12345" }, "the broken checksum is dropped")
        assertFalse(answer.rows.any { it.id == "satellite-28912" }, "deep space is not drawn")
        assertFalse(answer.rows.any { it.id == "satellite-11111" }, "a 30-day-old TLE is dropped")
        assertTrue(answer.rows.first().id == "sat-status")
        assertTrue(answer.rows.first().detail.contains("two hours"))
    }

    @Test fun fixtureUsesItsFixedInstantAndNeverCallsItselfLive() {
        val store = SatelliteStore(null, SatMemStores())
        val fixture = store.parseFixture(
            text = payload, atMs = now, stampMs = now,
            observerLatDeg = observerLat, observerLonDeg = observerLon,
            south = -80.0, west = -180.0, north = 80.0, east = 180.0, zoom = 1.0)
        assertEquals(now, fixture.fixedAtMs)
        assertFalse(fixture.live)
        val hstRow = fixture.rows.first { it.id == "satellite-20580" }.detail
        assertTrue(hstRow.startsWith("Alt 4") && hstRow.contains("km/s"), hstRow)
        assertNull(SatelliteStore(null, SatMemStores())
            .nextPass(20580, observerLat, observerLon, now),
            "no TLE means no invented pass")
    }
}

/** Answers a status per group, with the same TLE payload for every 2xx answer. */
private class RoutingHttp(
    private val code: (String) -> Int,
) : VelaHttp {
    val requests = mutableListOf<HttpRequest>()
    private val payload = """
        HST
        1 20580U 90037B   26301.53981808  .00004440  00000+0  13181-3 0  9996
        2 20580  28.4736 248.2212 0001869 190.0188 170.0372 15.32105918809034
        ISS (ZARYA)
        1 25544U 98067A   26301.59601386  .00005724  00000+0  11161-3 0  9990
        2 25544  51.6336 359.9178 0006994 320.4528  39.5949 15.49090321592436
        METOP-C
        1 43689U 18087A   26302.11361821  .00000103  00000+0  65476-4 0  9995
        2 43689  98.7041 266.2806 0001327  78.5291 281.6153 14.21485067395984
        SWIFT
        1 28485U 04047A   26301.85033915  .00002100  00000+0  92648-4 0  9993
        2 28485  20.5575 305.9852 0008096  82.8575 277.2484 15.03098443117115
    """.trimIndent()

    override fun execute(
        request: HttpRequest,
        callback: (HttpResponse?, Throwable?) -> Unit,
    ): Cancellable {
        requests += request
        val group = request.url.substringAfter("GROUP=").substringBefore("&")
        val status = code(group)
        val body = if (status in 200..299) payload else ""
        callback(HttpResponse(status, emptyList(), body.encodeToByteArray(), request.url), null)
        return Cancellable { }
    }
}

private class SatMemStores : KeyValueStores {
    private val stores = mutableMapOf<String, SatMemStore>()

    override fun open(name: String): KeyValueStore = stores.getOrPut(name) { SatMemStore() }
}

private class SatMemStore : KeyValueStore {
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

        override fun putString(key: String, value: String?): KeyValueEditor = change(key, value)
        override fun putLong(key: String, value: Long): KeyValueEditor = change(key, value)
        override fun putInt(key: String, value: Int): KeyValueEditor = change(key, value)
        override fun putBoolean(key: String, value: Boolean): KeyValueEditor = change(key, value)
        override fun putFloat(key: String, value: Float): KeyValueEditor = change(key, value)
        override fun remove(key: String): KeyValueEditor = change(key, null)
        override fun clear(): KeyValueEditor { clear = true; return this }

        private fun change(key: String, value: Any?): KeyValueEditor {
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
