package app.vela.ios.world

import app.vela.core.platform.Cancellable
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.HttpResponse
import app.vela.core.platform.VelaHttp
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * A-1: the adsb.lol point answer, its cap, its cache, the 429 quota window, the 60 s expiry and
 * the viewport filter, all without a network.
 *
 * The small JSON below is a captured snippet of the real `/v2/point` answer around Oakland
 * (2026-10-28), trimmed to the fields A-1 reads. The 305-aircraft answer is generated so the cap
 * is tested without a large resource.
 */
class AviationStoreTest {
    private val south = 37.50
    private val west = -122.55
    private val north = 37.75
    private val east = -122.20
    private val now = 1_700_000_000_000L

    private val captured = """
        {"ac":[
          {"hex":"a671bf","flight":"OPS18   ","lat":37.6283,"lon":-122.393291,"alt_baro":"ground","gs":0.0,"on_ground":true,"seen_pos":1.8},
          {"hex":"a0b6f9","flight":"N145TN  ","lat":37.529437,"lon":-122.276698,"alt_baro":1800,"alt_geom":1875,"gs":98.0,"track":139.96,"seen_pos":0.4},
          {"hex":"ad7ab8","flight":".N968JT ","lat":37.611053,"lon":-122.385153,"alt_baro":"ground","on_ground":true},
          {"hex":"a657bf","lat":37.611310,"lon":-122.386740,"alt_baro":25,"gs":3.0},
          {"hex":"out001","flight":"OUT123  ","lat":40.0,"lon":-100.0,"alt_baro":30000,"track":90.0}
        ]}
    """.trimIndent()

    @Test fun capturedFixtureKeepsIdentificationAltitudeAndHeading() {
        val store = AviationStore(null)
        val answer = store.parseFixture(captured, south, west, north, east, now)

        assertEquals(AviationPhases.FRESH, answer.phase)
        assertEquals(4, answer.aircraft.size, "the aircraft outside the viewport is rejected")
        assertFalse(answer.live, "a fixture is never reported as live")
        assertEquals(now, answer.updatedAtMs)

        val ground = answer.aircraft.first { it.hex == "a671bf" }
        assertEquals("OPS18", ground.identification)
        assertTrue(ground.onGround)
        assertEquals(-1, ground.altitudeFt, "a ground aircraft has no altitude, not 0 ft")

        val airborne = answer.aircraft.first { it.hex == "a0b6f9" }
        assertEquals("N145TN", airborne.identification)
        assertEquals(1800, airborne.altitudeFt)
        assertEquals(139.96, airborne.headingDeg)
        assertEquals(98.0, airborne.groundSpeedKt)

        val unnamed = answer.aircraft.first { it.hex == "a657bf" }
        assertEquals("A657BF", unnamed.identification, "a missing callsign keeps its hex")
        assertEquals(-1.0, unnamed.headingDeg, "no heading is invented")
    }

    @Test fun nearestThreeHundredAircraftAreKept() {
        val many = manyAircraft(305)
        val store = AviationStore(null)
        val answer = store.parseFixture(many, south, west, north, east, now)

        assertEquals(AviationStore.MAX_AIRCRAFT, answer.aircraft.size)
        assertEquals("AC0000", answer.aircraft.first().identification,
                     "the aircraft nearest the view center comes first")
        assertEquals(AviationStore.MAX_AIRCRAFT, answer.aircraft.map { it.hex }.toSet().size)
    }

    @Test fun tenSecondCacheDoesNotSpendASecondRequest() = runTest {
        val http = CountingHttp(listOf({ request -> ok(captured, request) }))
        val store = AviationStore(http)
        store.fetch(south, west, north, east, now)
        store.fetch(south, west, north, east, now + AviationStore.CACHE_MS - 1)
        assertEquals(1, http.requests.size, "the second viewport inside the cache is free")

        store.fetch(south, west, north, east, now + AviationStore.CACHE_MS)
        assertEquals(2, http.requests.size, "the cache expires after 10 s")
        assertTrue(http.requests.first().url.startsWith(AviationStore.BASE_URL))
        assertTrue(http.requests.first().url.contains("/37.6250/-122.3750/"),
                   "the point is the view center: ${http.requests.first().url}")
    }

    @Test fun quotaStopsRequestsForSixtySeconds() = runTest {
        val http = CountingHttp(listOf(
            { request -> HttpResponse(429, emptyList(), ByteArray(0), request.url) },
            { request -> ok(captured, request) },
        ))
        val store = AviationStore(http)

        val first = store.fetch(south, west, north, east, now)
        assertEquals(AviationPhases.QUOTA, first.phase)
        assertTrue(first.detail.startsWith("Quota reached"))
        assertEquals(60, first.quotaRemainingSeconds)
        assertTrue(first.aircraft.isEmpty(), "a quota answer draws nothing")

        val within = store.fetch(south, west, north, east, now + 59_000)
        assertEquals(AviationPhases.QUOTA, within.phase)
        assertEquals(1, within.quotaRemainingSeconds)
        assertEquals(1, http.requests.size, "no request during the 60 s cooldown")

        val after = store.fetch(south, west, north, east, now + 60_001)
        assertEquals(2, http.requests.size, "the cooldown ends after 60 s")
        assertEquals(AviationPhases.FRESH, after.phase)
        assertEquals(4, after.aircraft.size)
    }

    @Test fun acceptedDataExpiresAtSixtySeconds() {
        val store = AviationStore(null)
        store.parseFixture(captured, south, west, north, east, now)

        val fresh = store.snapshot(now + 60_000)
        assertEquals(AviationPhases.FRESH, fresh.phase)
        assertEquals(4, fresh.aircraft.size)

        val late = store.snapshot(now + 60_001)
        assertEquals(AviationPhases.LATE, late.phase)
        assertTrue(late.aircraft.isEmpty(), "past the window the layer stops drawing")
        assertFalse(late.live)
        assertTrue(late.detail.contains("older than 60 s"))
        assertEquals(now, late.updatedAtMs, "the timestamp still says when the data was produced")
    }

    @Test fun httpFailureKeepsFreshDataButSaysItIsUnavailable() = runTest {
        val http = CountingHttp(listOf(
            { request -> ok(captured, request) },
            { request -> HttpResponse(503, emptyList(), ByteArray(0), request.url) },
        ))
        val store = AviationStore(http)
        store.fetch(south, west, north, east, now)
        val after = store.fetch(south, west, north, east, now + AviationStore.CACHE_MS)
        assertEquals(4, after.aircraft.size, "a failure does not erase data still inside the window")
        assertTrue(after.detail.contains("HTTP 503"))
    }

    private fun manyAircraft(count: Int): String {
        val entries = (0 until count).joinToString(",") { index ->
            val lat = 37.65 + (index % 19) * 0.001
            val lng = -122.375 + (index / 19) * 0.001
            val hex = "ac" + index.toString().padStart(4, '0')
            val callsign = "AC" + index.toString().padStart(4, '0')
            """{"hex":"$hex","flight":"$callsign","lat":$lat,"lon":$lng,"alt_baro":1000,"track":90.0}"""
        }
        return """{"ac":[$entries]}"""
    }

    private fun ok(body: String, request: HttpRequest): HttpResponse =
        HttpResponse(200, emptyList(), body.encodeToByteArray(), request.url)
}

private class CountingHttp(
    private val answers: List<(HttpRequest) -> HttpResponse>,
) : VelaHttp {
    val requests = mutableListOf<HttpRequest>()
    private var index = 0

    override fun execute(
        request: HttpRequest,
        callback: (HttpResponse?, Throwable?) -> Unit,
    ): Cancellable {
        requests += request
        val answer = answers[index.coerceAtMost(answers.size - 1)]
        index += 1
        callback(answer(request), null)
        return Cancellable { }
    }
}
