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
 * viewport filters, the next pass, the SGP4 / SDP4 routing and the invalid / stale refusals, all
 * without a network.
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

    // Geostationary: a deep-space element set, drawn through SDP4.
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
        assertEquals(listOf("stations", "weather", "science", "gnss"), groups,
            "the navigation group is asked last, after the three original groups")
        assertTrue(http.requests.all {
            it.url.startsWith(SatelliteStore.BASE_URL) && it.url.endsWith("FORMAT=tle")
        })

        snapshot(store, nowMs = now + SatelliteStore.CACHE_MS - 1)
        assertEquals(SatelliteStore.GROUPS.size, http.requests.size,
            "a second refresh inside two hours asks nothing")

        snapshot(store, nowMs = now + SatelliteStore.CACHE_MS)
        assertEquals(SatelliteStore.GROUPS.size * 2, http.requests.size,
            "the cycle reopens exactly at two hours with the same four requests")
    }

    @Test fun navigationGroupIsLastAndCountsFourRequestsPerCycle() {
        assertEquals(4, SatelliteStore.GROUPS.size)
        assertEquals("gnss", SatelliteStore.GROUPS.last(),
            "navigation is appended after the original groups, never before them")
        assertEquals(SatelliteStore.GROUPS.size, SatelliteStore.groupCount())
    }

    @Test fun non200StopsTheCycleAndKeepsThePreviousData() = runTest {
        var failStations = false
        val http = RoutingHttp { group -> if (failStations && group == "stations") 503 else 200 }
        val store = SatelliteStore(http, SatMemStores())
        snapshot(store)
        val before = http.requests.size
        assertEquals(SatelliteStore.GROUPS.size, before)

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

    @Test fun navigationFailureStopsTheCycleAndKeepsTheThreeOriginalGroups() = runTest {
        var failGnss = false
        val http = RoutingHttp { group -> if (failGnss && group == "gnss") 503 else 200 }
        val store = SatelliteStore(http, SatMemStores())
        snapshot(store)
        assertEquals(4, http.requests.size)

        failGnss = true
        val answer = snapshot(store, nowMs = now + SatelliteStore.CACHE_MS + 1_000L)
        assertEquals(8, http.requests.size,
            "stations, weather and science are asked, then gnss fails and the cycle stops")
        assertEquals(
            listOf("stations", "weather", "science", "gnss"),
            http.requests.drop(4).map { it.url.substringAfter("GROUP=").substringBefore("&") })
        assertTrue(answer.detail.contains("HTTP 503"), answer.detail)
        assertEquals(4, answer.tleCount, "the original element sets stay cached and parsed")
        assertEquals(WorldLayerStatuses.FRESH, answer.phase,
            "the three original groups were refreshed before the failure")
        assertTrue(answer.rows.first().id == "sat-status",
            "a failed navigation group never evicts the station element sets")
    }

    @Test fun capReservesASharePerOrbitBandSoNavigationCannotStarveNearEarth() {
        val store = SatelliteStore(null, SatMemStores())
        // Two hundred medium-Earth navigation candidates, all far higher in the sky than one
        // near-Earth weather satellite and one geostationary weather satellite.
        val navigation = (1..200).map { index ->
            SatelliteSky(
                catalogNumber = index,
                name = "GPS $index",
                latDeg = 0.0,
                lonDeg = 0.0,
                altitudeKm = 20_200.0,
                speedKmS = 3.87,
                elevationDeg = 85.0 - index * 0.01,
                azimuthDeg = 0.0,
                tleEpochMs = now)
        }
        val metop = SatelliteSky(90_001, "METOP-C", 0.0, 0.0, 800.0, 7.45, 2.0, 0.0, now)
        val meteosat = SatelliteSky(90_002, "METEOSAT-9", 0.0, 0.0, 35_786.0, 3.07, 1.0, 0.0, now)

        val selected = store.selectForCap(listOf(metop, meteosat) + navigation)
        assertEquals(SatelliteStore.MAX_SATELLITES, selected.size)
        assertEquals(selected.size, selected.map { it.catalogNumber }.distinct().size,
            "no satellite is kept twice")
        assertTrue(selected.any { it.catalogNumber == 90_001 },
            "the near-Earth weather satellite keeps its reserved band slot")
        assertTrue(selected.any { it.catalogNumber == 90_002 },
            "the geostationary weather satellite keeps its reserved band slot")
        assertEquals(1, selected.first().catalogNumber,
            "the fill still puts the highest elevation first")
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

    @Test fun invalidAndStaleElementSetsAreRefused() = runTest {
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

        assertTrue(answer.satellites.any { it.catalogNumber == 20580 }, "HST is above the horizon")
        assertTrue(answer.satellites.any { it.catalogNumber == 28912 },
            "the geostationary object is now drawn by SDP4")
        assertEquals(3, answer.tleCount, "HST, ISS and the geostationary element set parse")
        assertEquals(1, answer.skippedCount, "the 30-day-old element set is refused")
        assertFalse(answer.rows.any { it.id == "satellite-12345" }, "the broken checksum is dropped")
        assertFalse(answer.rows.any { it.id == "satellite-11111" }, "a 30-day-old TLE is dropped")
        assertTrue(answer.rows.first().id == "sat-status")
        assertTrue(answer.rows.first().detail.contains("two hours"))
    }

    @Test fun deepSpaceGeostationaryAndMolniyaGetPositions() = runTest {
        // A Molniya element set from the AIAA deep-space verification case, re-dated to the
        // fixture day so it is not refused as stale.
        val molniya = """
            MOLNIYA 1-36
            1 08195U 75081A   26301.50000000  .00000099  00000-0  11873-3 0   814
            2 08195  64.1586 279.0717 6877146 264.7651  20.2257  2.00491383225656
        """.trimIndent()

        val geoAnswer = SatelliteStore(null, SatMemStores()).parseFixture(
            text = geo, atMs = now, stampMs = now,
            observerLatDeg = observerLat, observerLonDeg = observerLon,
            south = -80.0, west = -180.0, north = 80.0, east = 180.0, zoom = 1.0)
        val geoSky = geoAnswer.satellites.single()
        assertEquals(28912, geoSky.catalogNumber)
        assertTrue(geoSky.altitudeKm in 34_000.0..37_000.0,
            "geostationary altitude ${geoSky.altitudeKm} km")
        assertTrue(geoSky.speedKmS in 2.5..3.5, "geostationary speed ${geoSky.speedKmS} km/s")

        // The Molniya orbit is drawn from directly below it, so the horizon filter cannot hide it.
        val molniyaTle = app.vela.core.sat.Sgp4.parseTles(molniya).single()
        val under = assertNotNull(app.vela.core.sat.Sgp4.fix(molniyaTle, now))
        val molniyaAnswer = SatelliteStore(null, SatMemStores()).parseFixture(
            text = molniya, atMs = now, stampMs = now,
            observerLatDeg = under.latDeg, observerLonDeg = under.lonDeg,
            south = -80.0, west = -180.0, north = 80.0, east = 180.0, zoom = 1.0)
        val molniyaSky = molniyaAnswer.satellites.single()
        assertEquals(8195, molniyaSky.catalogNumber)
        assertTrue(molniyaSky.altitudeKm in 8_000.0..46_000.0,
            "Molniya altitude ${molniyaSky.altitudeKm} km")
        assertTrue(molniyaSky.speedKmS in 1.0..11.0, "Molniya speed ${molniyaSky.speedKmS} km/s")
        assertTrue(molniyaSky.elevationDeg > 89.0, "the observer is under the satellite")
    }

    @Test fun navigationElementSetIsDrawnFromTheGnssGroup() {
        // A GPS operational element set, the constellation the `gnss` group adds. Its 12-hour
        // period routes it through SDP4. At the fixture instant it is above (0, 0).
        val gps = """
            GPS BIIR-8 (PRN 16)
            1 27663U 03005A   26302.74051294  .00000019  00000+0  00000+0 0  9995
            2 27663  54.8575 209.6286 0152556  54.2138 317.0404  2.00553218174018
        """.trimIndent()
        val answer = SatelliteStore(http = null, cache = null).parseFixture(
            text = gps, atMs = now, stampMs = now,
            observerLatDeg = observerLat, observerLonDeg = observerLon,
            south = -80.0, west = -180.0, north = 80.0, east = 180.0, zoom = 1.0)
        val sky = answer.satellites.single()
        assertEquals(27663, sky.catalogNumber)
        assertTrue(sky.name.startsWith("GPS "), "the navigation name is kept: ${sky.name}")
        assertTrue(sky.altitudeKm in 19_000.0..22_000.0,
            "GPS altitude ${sky.altitudeKm} km")
        assertTrue(sky.elevationDeg > 0.0, "the GPS satellite is above the fixture horizon")
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
