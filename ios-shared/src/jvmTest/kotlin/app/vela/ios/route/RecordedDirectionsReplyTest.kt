package app.vela.ios.route

import app.vela.core.model.LatLng
import app.vela.core.model.TravelMode
import app.vela.core.model.distanceTo
import app.vela.ios.search.FakeHttp
import app.vela.ios.search.IosSources
import app.vela.ios.search.ok
import java.util.zip.GZIPInputStream
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Real directions replies from the San Francisco point to the Ferry Building (the sf-market
 * fixture's ends), driving and walking, recorded on the macOS runner (scripts/ios/ci-ipa.sh, run
 * i4-routes-20261025-014114-30713) with the iOS identity.
 */
class RecordedDirectionsReplyTest {
    private fun fixture(name: String): String =
        GZIPInputStream(javaClass.getResourceAsStream("/$name.txt.gz")!!).readBytes().decodeToString()

    private val sf = LatLng(37.7749, -122.4194)
    private val ferry = LatLng(37.7942, -122.3946)

    private fun source(reply: String, onDirections: (String) -> Unit = {}) = IosSources.over(FakeHttp { r ->
        if ("/maps/preview/directions?" in r.url) { onDirections(r.url); ok(reply) } else ok("")
    })

    @Test fun theRecordedDriveParsesIntoRoutesWithSteps() = runTest {
        val routes = source(fixture("directions-drive-sf")).directions(sf, ferry, TravelMode.DRIVE)
        assertTrue(routes.isNotEmpty(), "no route")
        val r = routes.first()
        assertTrue(r.distanceMeters in 2_000.0..6_000.0, "distance ${r.distanceMeters}")
        assertTrue(r.durationSeconds in 180.0..1_800.0, "duration ${r.durationSeconds}")
        assertTrue(r.polyline.size > 10)
        assertTrue(r.polyline.first().distanceTo(sf) < 300.0)
        assertTrue(r.polyline.last().distanceTo(ferry) < 300.0)
        assertTrue(r.maneuvers.isNotEmpty())
        println(
            "recorded drive: ${routes.size} routes, first ${r.distanceMeters} m ${r.durationSeconds} s " +
                "traffic ${r.durationInTrafficSeconds} spans ${r.trafficSpans.size} steps ${r.maneuvers.size} via ${r.summary}",
        )
        for (t in RouteStore.trafficOn(r)) assertTrue(t.points.size >= 4)
    }

    @Test fun theRecordedWalkIsAskedAndKept() = runTest {
        var asked = ""
        val routes = source(fixture("directions-walk-sf")) { asked = it }.directions(sf, ferry, TravelMode.WALK)
        assertTrue("!1e2" in asked || "%211e2" in asked, "walk mode not in the request")
        assertTrue(routes.isNotEmpty(), "no walk")
        val r = routes.first()
        assertTrue(r.distanceMeters in 2_000.0..5_000.0, "distance ${r.distanceMeters}")
        println("recorded walk: ${routes.size} routes, ${r.distanceMeters} m ${r.durationSeconds} s steps ${r.maneuvers.size}")
    }

    @Test fun theStoreKeepsTheParsedRouteObjects() = runBlocking {
        val src = source(fixture("directions-drive-sf"))
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val store = RouteStore({ src }, scope).also { it.start() }
        store.onLocation(sf.lat, sf.lng)
        store.directionsTo(app.vela.core.model.Place(id = "ferry", name = "Ferry Building", location = ferry))
        withTimeout(10_000) { store.state.first { !it.loading } }
        val s = store.state.value
        assertTrue(s.routes.isNotEmpty(), "error ${s.error}")
        assertSame(s.routes[0], s.active)
        if (s.routes.size > 1) {
            store.select(1)
            assertSame(s.routes[1], store.state.value.active)
        }
        assertEquals(s.routes.size, s.rows().size)
        scope.cancel()
    }
}
