package app.vela.ios.route

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
import app.vela.core.model.RouteSource
import app.vela.core.model.TransitMode
import app.vela.core.model.TravelMode
import app.vela.core.platform.HttpResponse
import app.vela.ios.search.FakeHttp
import app.vela.ios.search.FakeLocale
import app.vela.ios.search.IosSources
import app.vela.ios.search.ok
import java.util.zip.GZIPInputStream
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * The hybrid router (`IosGoogle.hybridSource`) and the transit planner over real replies for
 * the San Francisco point to the Ferry Building, recorded on the macOS runner
 * (scripts/ios/ci-ipa.sh, run i4b-routes-polish-20261025-160955-20980): Google's directions,
 * the open router's car and foot routes, Transitous' plan. Valhalla and the tiles do not answer.
 */
class RecordedHybridReplyTest {
    private fun fixture(name: String): String =
        GZIPInputStream(javaClass.getResourceAsStream("/$name.txt.gz")!!).readBytes().decodeToString()

    private val sf = LatLng(37.7749, -122.4194)
    private val ferry = LatLng(37.7942, -122.3946)

    private val http = FakeHttp { r ->
        when {
            "/maps/preview/directions?" in r.url && "!1e2" in r.url.replace("%21", "!") -> ok(fixture("directions-walk-sf"))
            "/maps/preview/directions?" in r.url -> ok(fixture("directions-drive-sf"))
            "/routed-car/" in r.url -> ok(fixture("osrm-car-sf"))
            "/routed-foot/" in r.url -> ok(fixture("osrm-foot-sf"))
            "/api/v1/plan?" in r.url -> ok(fixture("transit-plan-sf"))
            "www.google.com" in r.url -> ok("")
            else -> HttpResponse(404, emptyList(), ByteArray(0), r.url)
        }
    }

    @Test fun theHybridDriveHasTheOpenRoutersSteps() = runBlocking {
        val routes = IosSources.hybridOver(http).directions(sf, ferry, TravelMode.DRIVE)
        assertTrue(routes.isNotEmpty(), "no route")
        val r = routes.first()
        val named = r.maneuvers.count { !it.road.isNullOrBlank() }
        println("hybrid drive: ${routes.size} routes, ${r.source}, ${r.distanceMeters} m, steps ${r.maneuvers.size}, named $named: " +
            r.maneuvers.joinToString(" | ") { it.instruction })
        assertTrue(r.maneuvers.size > 2, "steps ${r.maneuvers.size}")
        assertTrue(named >= 2, "named $named")
        assertTrue(r.source != RouteSource.GOOGLE_NAMED, "source ${r.source}")
    }

    @Test fun theWalkIsTheFootRouters() = runBlocking {
        val routes = IosSources.hybridOver(http).directions(sf, ferry, TravelMode.WALK)
        assertTrue(routes.isNotEmpty(), "no walk")
        val r = routes.first()
        println("hybrid walk: ${r.source}, ${r.distanceMeters} m, steps ${r.maneuvers.size}")
        assertTrue(r.maneuvers.size > 2)
    }

    @Test fun thePlanHasRides() = runBlocking {
        val core = app.vela.ios.testGraph(http)
        val trips = Transitous.plan(TransitousHttp(core.http, FakeLocale("en-US"), core.text), sf, ferry)
        println("transit: ${trips.size} itineraries; first ${trips.firstOrNull()?.durationText}: " +
            trips.firstOrNull()?.steps?.joinToString(" > ") { "${it.mode} ${it.line?.name.orEmpty()} ${it.durationText.orEmpty()}" })
        assertTrue(trips.isNotEmpty())
        assertTrue(trips.any { t -> t.steps.any { it.mode != TransitMode.WALK && it.line != null } })
        assertTrue(RouteStore.transitLineOf(trips.first()).size >= 4)
    }
}
