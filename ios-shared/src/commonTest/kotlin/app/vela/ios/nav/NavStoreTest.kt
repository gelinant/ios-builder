package app.vela.ios.nav

import app.vela.core.data.MapDataSource
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.core.platform.Clock
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice
import app.vela.ios.route.RouteStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

private class NavSource(private val route: Route) : MapDataSource {
    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?) = SearchResult(query, emptyList())
    override suspend fun placeDetails(id: String) = Place(id = id, name = "", location = route.polyline.last())
    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = if (mode == TravelMode.DRIVE) listOf(route) else emptyList()
}

private class RecordingVoice : NavVoice {
    var openers = 0
    var stops = 0
    val spoken = mutableListOf<String>()
    override fun init(enginePackage: String?) {}
    override fun speak(text: String, interrupt: Boolean, ignoreMute: Boolean) { spoken += text }
    override fun prepare(text: String, onDone: () -> Unit) = onDone()
    override fun speakOpener(text: String) { openers++ }
    override fun stop() { stops++ }
    override fun reroutingChime() {}
    override fun fasterRouteChime() {}
}

private object NoHaptics : NavHaptics {
    override fun cue(type: app.vela.core.model.ManeuverType, approaching: Boolean, mode: TravelMode) {}
    override fun reroute(mode: TravelMode) {}
}

private class NavClock : Clock {
    private var now = 1_000L
    override fun nowMillis() = now
    override fun elapsedRealtimeMillis() = now
    override fun monotonicNanos() = now * 1_000_000
}

private object NoLog : Log {
    override fun isLoggable(tag: String, level: LogLevel) = false
    override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
}

@OptIn(ExperimentalCoroutinesApi::class)
class NavStoreTest {
    private val start = LatLng(37.7749, -122.4194)
    private val middle = LatLng(37.7857, -122.4054)
    private val end = LatLng(37.7942, -122.3946)

    @Test fun startUsesTheSelectedRouteItselfAndEndRestoresTheMap() = runTest {
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        val destination = Place(id = "destination", name = "Fixture destination", location = end)
        routes.directionsTo(destination)
        runCurrent()
        assertSame(route, routes.state.value.active)

        val voice = RecordingVoice()
        val clock = NavClock()
        val session = NavStore.session(source, voice, NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { session }
        nav.start()
        nav.startNavigation()
        nav.startNavigation()
        runCurrent()

        assertTrue(nav.state.value.navigating)
        assertSame(route, session.state.value.route, "NavSession route identity must survive Start")
        assertEquals(1, voice.openers)
        assertFalse(routes.state.value.open)
        assertEquals("DEPART", nav.state.value.maneuver?.type)
        assertEquals("TURN_LEFT", nav.state.value.nextManeuver?.type)

        nav.onFix(middle.lat, middle.lng, 10.0, 12.0, 45.0, 2_000_000_000, gnss = true)
        runCurrent()
        assertTrue(nav.state.value.remainingDistanceMeters < route.distanceMeters)
        assertEquals(12.0, nav.state.value.speedMps)
        assertTrue(nav.line().isNotEmpty())

        nav.stop()
        runCurrent()
        assertFalse(nav.state.value.active)
        assertEquals(1, voice.stops)
        assertTrue(nav.line().isEmpty())
        assertFalse(session.state.value.navigating)
    }

    private fun route(): Route {
        val maneuvers = listOf(
            Maneuver(ManeuverType.DEPART, "Head out", start, 1_300.0, 100.0, "Market Street"),
            Maneuver(ManeuverType.TURN_LEFT, "Turn left", middle, 1_300.0, 100.0, "Second Street"),
            Maneuver(ManeuverType.ARRIVE, "Arrive", end, 0.0, 0.0),
        )
        return Route(
            polyline = listOf(start, middle, end),
            legs = listOf(RouteLeg(2_600.0, 200.0, null, maneuvers)),
            distanceMeters = 2_600.0,
            durationSeconds = 200.0,
            durationInTrafficSeconds = null,
        )
    }
}
