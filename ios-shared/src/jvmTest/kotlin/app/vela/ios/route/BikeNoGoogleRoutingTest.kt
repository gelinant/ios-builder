package app.vela.ios.route

import app.vela.core.data.NoGoogle
import app.vela.core.data.RoutingPrefs
import app.vela.core.data.google.PolylineCodec
import app.vela.core.model.LatLng
import app.vela.core.model.RouteSource
import app.vela.core.model.TravelMode
import app.vela.core.platform.HttpResponse
import app.vela.ios.search.FakeHttp
import app.vela.ios.search.IosSources
import app.vela.ios.search.ok
import java.util.zip.GZIPInputStream
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * R-2: bicycle routing and the no-Google path, against the hybrid router that serves the chooser.
 * Valhalla's bicycle profile is the safe route (SPEC 4.3), the fastest bike chain runs only when
 * the preference is off, and no mode sends a request to a Google host while "Use Vela without
 * Google" is on.
 */
class BikeNoGoogleRoutingTest {
    private val sf = LatLng(37.7749, -122.4194)
    private val ferry = LatLng(37.7942, -122.3946)

    private fun fixture(name: String): String =
        GZIPInputStream(javaClass.getResourceAsStream("/$name.txt.gz")!!).readBytes().decodeToString()

    /** A small bicycle trip in Valhalla's own reply shape: depart, turn, arrive. */
    private fun valhallaBikeTrip(): String {
        val pts = listOf(sf, LatLng(37.7800, -122.4150), ferry)
        val shape = PolylineCodec.encode(pts, 6).replace("\\", "\\\\").replace("\"", "\\\"")
        return """{"trip":{"summary":{"length":3.0,"time":600.0},"legs":[{"shape":"$shape","maneuvers":[
            {"type":2,"instruction":"Bike south on Market Street.","street_names":["Market Street"],"length":1.4,"time":280.0,"begin_shape_index":0,"end_shape_index":1,"bearing_after":180},
            {"type":10,"instruction":"Turn left onto The Embarcadero.","street_names":["The Embarcadero"],"length":1.6,"time":320.0,"begin_shape_index":1,"end_shape_index":2,"bearing_before":180,"bearing_after":20},
            {"type":4,"instruction":"You have arrived.","length":0.0,"time":0.0,"begin_shape_index":2,"end_shape_index":2,"bearing_before":20}]}]}}"""
    }

    private suspend fun <T> withFlags(bikeSafe: Boolean, noGoogle: Boolean, block: suspend () -> T): T {
        val oldBike = RoutingPrefs.bikeSafe
        val oldGoogle = NoGoogle.enabled
        RoutingPrefs.bikeSafe = bikeSafe
        NoGoogle.enabled = noGoogle
        return try {
            block()
        } finally {
            RoutingPrefs.bikeSafe = oldBike
            NoGoogle.enabled = oldGoogle
        }
    }

    @Test fun bikeSafeAsksValhallaWithTheSafetyWeightedProfile() = runBlocking {
        val http = FakeHttp { r ->
            when {
                "valhalla1.openstreetmap.de/route" in r.url -> ok(valhallaBikeTrip())
                "www.google.com" in r.url -> ok("")
                else -> HttpResponse(404, emptyList(), ByteArray(0), r.url)
            }
        }
        withFlags(bikeSafe = true, noGoogle = false) {
            val routes = IosSources.hybridOver(http).directions(sf, ferry, TravelMode.BICYCLE)
            assertTrue(routes.isNotEmpty(), "no bicycle route")
            assertEquals(RouteSource.VALHALLA, routes.first().source)
            val valhalla = http.requests.single { "valhalla1.openstreetmap.de/route" in it.url }
            val body = valhalla.body!!.decodeToString()
            assertTrue("\"costing\":\"bicycle\"" in body, body)
            assertTrue("\"use_roads\":0.1" in body, body)
            assertTrue("\"use_hills\":0.5" in body, body)
            assertTrue("\"bicycle_type\":\"Hybrid\"" in body, body)
            assertTrue("\"alternates\":2" in body, body)
            assertTrue(http.requests.none { "google" in it.url }, "a bike route asked Google: ${http.requests.map { it.url }}")
        }
    }

    @Test fun bikeFastOffSkipsValhallaAndUsesTheOpenBikeRouter() = runBlocking {
        val http = FakeHttp { r ->
            when {
                "/routed-bike/" in r.url -> ok(fixture("osrm-car-sf"))
                "www.google.com" in r.url -> ok("")
                else -> HttpResponse(404, emptyList(), ByteArray(0), r.url)
            }
        }
        withFlags(bikeSafe = false, noGoogle = false) {
            val routes = IosSources.hybridOver(http).directions(sf, ferry, TravelMode.BICYCLE)
            assertTrue(routes.isNotEmpty(), "no fast bicycle route")
            assertTrue(http.requests.any { "/routed-bike/" in it.url }, "the bike chain was not asked")
            assertTrue(http.requests.none { "valhalla1.openstreetmap.de" in it.url }, "Valhalla was asked with the preference off")
        }
    }

    @Test fun noGoogleDriveAndWalkNeverAskAGoogleHost() = runBlocking {
        val http = FakeHttp { r ->
            when {
                "/maps/preview/directions?" in r.url -> ok(if ("!1e2" in r.url.replace("%21", "!")) fixture("directions-walk-sf") else fixture("directions-drive-sf"))
                "/routed-car/" in r.url -> ok(fixture("osrm-car-sf"))
                "/routed-foot/" in r.url -> ok(fixture("osrm-foot-sf"))
                "www.google.com" in r.url -> ok("")
                else -> HttpResponse(404, emptyList(), ByteArray(0), r.url)
            }
        }
        withFlags(bikeSafe = true, noGoogle = true) {
            val source = IosSources.hybridOver(http)
            val drive = source.directions(sf, ferry, TravelMode.DRIVE)
            assertTrue(drive.isNotEmpty(), "no drive route without Google")
            assertTrue(drive.none { it.source == RouteSource.GOOGLE_NAMED || it.source == RouteSource.GOOGLE_HYBRID || it.source == RouteSource.GOOGLE_ABBREVIATED }, "a Google route was adopted")
            assertTrue(drive.all { it.trafficSpans.isEmpty() }, "traffic arrived without Google")
            val walk = source.directions(sf, ferry, TravelMode.WALK)
            assertTrue(walk.isNotEmpty(), "no walk route without Google")
            assertTrue(http.requests.none { "google" in it.url }, "Google was asked with NoGoogle on: ${http.requests.map { it.url }}")
        }
    }

    @Test fun theWalkComparisonUsesTheFifteenPercentRule() {
        val source = IosSources.hybridOver(FakeHttp { r -> HttpResponse(404, emptyList(), ByteArray(0), r.url) })
        assertTrue(source.googleWalkIsShorter(openMeters = null, googleMeters = 5_000.0))
        assertTrue(source.googleWalkIsShorter(openMeters = 2_000.0, googleMeters = 1_700.0))
        assertTrue(source.googleWalkIsShorter(openMeters = 2_000.0, googleMeters = 1_400.0))
        assertFalse(source.googleWalkIsShorter(openMeters = 2_000.0, googleMeters = 1_701.0))
        assertFalse(source.googleWalkIsShorter(openMeters = 2_000.0, googleMeters = 2_000.0))
    }
}
