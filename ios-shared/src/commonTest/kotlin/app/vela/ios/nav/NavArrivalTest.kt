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
import app.vela.core.nav.RouteProjection
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
import kotlin.test.assertTrue

private class ArrivalSource(private val route: Route) : MapDataSource {
    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?) =
        SearchResult(query, emptyList())
    override suspend fun placeDetails(id: String) = Place(id = id, name = "", location = route.polyline.last())
    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> = if (mode == TravelMode.DRIVE) listOf(route) else emptyList()
}

private class ArrivalVoice : NavVoice {
    val spoken = mutableListOf<String>()
    override fun init(enginePackage: String?) {}
    override fun speak(text: String, interrupt: Boolean, ignoreMute: Boolean) { spoken += text }
    override fun prepare(text: String, onDone: () -> Unit) = onDone()
    override fun speakOpener(text: String) {}
    override fun stop() {}
    override fun reroutingChime() {}
    override fun fasterRouteChime() {}
}

private object ArrivalHaptics : NavHaptics {
    override fun cue(type: ManeuverType, approaching: Boolean, mode: TravelMode) {}
    override fun reroute(mode: TravelMode) {}
}

private class ArrivalClock : Clock {
    var now = 1_000L
    override fun nowMillis() = now
    override fun elapsedRealtimeMillis() = now
    override fun monotonicNanos() = now * 1_000_000
}

private object ArrivalLog : Log {
    override fun isLoggable(tag: String, level: LogLevel) = false
    override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
}

/** N-4: the waypoint card continues the same drive, and the arrival card's parking offer gates. */
@OptIn(ExperimentalCoroutinesApi::class)
class NavArrivalTest {
    private val start = LatLng(37.7749, -122.4194)
    private val stop = LatLng(37.7857, -122.4054)
    private val end = LatLng(37.7942, -122.3946)

    private fun route(): Route {
        val maneuvers = listOf(
            Maneuver(ManeuverType.DEPART, "Head out", start, 1_300.0, 100.0, "Market Street"),
            Maneuver(ManeuverType.TURN_LEFT, "Turn left", stop, 1_300.0, 100.0, "Second Street"),
            Maneuver(ManeuverType.ARRIVE, "Arrive", end, 0.0, 0.0),
        )
        return Route(
            polyline = listOf(start, stop, end),
            legs = listOf(RouteLeg(2_600.0, 200.0, null, maneuvers)),
            distanceMeters = 2_600.0,
            durationSeconds = 200.0,
            durationInTrafficSeconds = null,
        )
    }

    @Test fun aWaypointIsAnnouncedAndTheDriveContinuesToTheDestination() = runTest {
        val route = route()
        val source = ArrivalSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = end))
        runCurrent()
        routes.addWaypointPlace(
            id = "stop", name = "Davis Food Co-op", address = null,
            lat = stop.lat, lng = stop.lng)
        runCurrent()
        assertEquals(1, routes.state.value.waypoints.size, "the chooser lost the stop")

        val voice = ArrivalVoice()
        val clock = ArrivalClock()
        var sessions = 0
        val session = NavStore.session(source, voice, ArrivalHaptics, ArrivalLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { sessions++; session }
        nav.start()
        nav.startNavigation()
        nav.startNavigation()
        runCurrent()
        assertEquals(1, sessions, "two sessions before the drive even started")
        assertEquals("Davis Food Co-op", nav.state.value.nextStopLabel)
        assertEquals(1, nav.state.value.stopsAhead)

        // The pipeline caps one-fix leaps below a plausible speed, as a real receiver does, so the
        // drive is fed 80 m fixes: past the stop, then to the destination.
        val cum = RouteProjection.cumulative(route.polyline)
        val total = cum.last()
        var m = 0.0
        var nanos = 1_000_000_000L
        fun driveTo(target: Double) {
            while (m < target) {
                val p = RouteProjection.pointAt(route.polyline, cum, m)
                clock.now += 2_000L
                nanos += 2_000_000_000L
                nav.onFix(p.lat, p.lng, 10.0, 15.0, 45.0, nanos, gnss = true)
                runCurrent()
                m += 80.0
            }
        }
        driveTo(1800.0)
        assertEquals("Davis Food Co-op", nav.state.value.reachedStopLabel)
        assertEquals(1L, nav.state.value.reachedStopSerial)
        assertEquals(0, nav.state.value.stopsAhead)
        assertTrue(nav.state.value.navigating, "the waypoint ended the drive")
        assertFalse(nav.state.value.arrived, "a waypoint is not the destination")
        assertTrue(voice.spoken.any { it.contains("Davis Food Co-op") }, "the stop was not spoken: ${voice.spoken}")
        assertEquals(1, sessions, "reaching a stop created another session")
        assertEquals(1L, nav.state.value.reachedStopSerial, "the same stop was announced twice")

        driveTo(total + 1.0)
        assertTrue(nav.state.value.arrived, "the destination never arrived")
        assertFalse(nav.state.value.navigating)
        assertEquals("Fixture destination", nav.state.value.destinationLabel)
        assertTrue(nav.state.value.tripElapsedSeconds > 0.0)
        assertEquals(1, sessions, "arrival created another session")
        assertTrue(nav.state.value.parkingOffer, "the drive should offer to save the car's spot")
    }

    @Test fun theArrivalParkingOfferNeedsADriveAndAPosition() {
        val arrived = NavUiState(
            arrived = true, travelMode = "DRIVE", latitude = end.lat, longitude = end.lng)
        assertTrue(arrived.parkingOffer)
        assertFalse(arrived.copy(travelMode = "WALK").parkingOffer, "a walk offered parking")
        assertFalse(arrived.copy(travelMode = "BICYCLE").parkingOffer, "a ride offered parking")
        assertFalse(arrived.copy(arrived = false).parkingOffer, "a drive in progress offered parking")
        assertFalse(arrived.copy(latitude = null).parkingOffer, "no fix offered parking")
    }
}
