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
import app.vela.core.model.distanceTo
import app.vela.core.nav.NavSession
import app.vela.core.platform.Clock
import app.vela.core.platform.Log
import app.vela.core.platform.LogLevel
import app.vela.core.platform.NavHaptics
import app.vela.core.platform.NavVoice
import app.vela.ios.route.RouteStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertSame
import kotlin.test.assertTrue

private class RobustSource(private val route: Route) : MapDataSource {
    var directionCalls = 0
        private set

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?) =
        SearchResult(query, emptyList())

    override suspend fun placeDetails(id: String) = Place(id = id, name = "", location = route.polyline.last())

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> {
        if (mode != TravelMode.DRIVE) return emptyList()
        directionCalls++
        return listOf(route)
    }
}

private class RobustVoice : NavVoice {
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

private object RobustHaptics : NavHaptics {
    override fun cue(type: ManeuverType, approaching: Boolean, mode: TravelMode) {}
    override fun reroute(mode: TravelMode) {}
}

private class RobustClock : Clock {
    var now = 1_000L
    override fun nowMillis() = now
    override fun elapsedRealtimeMillis() = now
    override fun monotonicNanos() = now * 1_000_000
}

private object RobustLog : Log {
    override fun isLoggable(tag: String, level: LogLevel) = false
    override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {}
}

@OptIn(ExperimentalCoroutinesApi::class)
class NavRobustnessTest {
    private val start = LatLng(37.7749, -122.4194)
    private val middle = LatLng(37.7857, -122.4054)
    private val end = LatLng(37.7942, -122.3946)

    private class Rig(
        val nav: NavStore,
        val session: NavSession,
        val voice: RobustVoice,
        val clock: RobustClock,
        val source: RobustSource,
        val sessions: () -> Int,
    ) {
        private var nanos = 1_000_000_000L

        /** One delivered platform fix, stamped on the same monotonic clock the store reads. */
        fun fix(lat: Double, lng: Double, speed: Double, accuracy: Double) {
            clock.now += 1_000
            nanos += 1_000_000_000
            nav.onFix(lat, lng, accuracy, speed, 45.0, nanos, gnss = true)
        }
    }

    private fun TestScope.harness(route: Route): Rig {
        val source = RobustSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = route.polyline.last()))
        runCurrent()
        val clock = RobustClock()
        val voice = RobustVoice()
        val session = NavStore.session(source, voice, RobustHaptics, RobustLog, clock)
        var sessions = 0
        val nav = NavStore(routes, { source }, backgroundScope, clock, voiceProvider = { voice }) {
            sessions++
            session
        }
        nav.start()
        return Rig(nav, session, voice, clock, source) { sessions }
    }

    /** Advances the fake elapsed clock and the coroutine timers together, one second at a time. */
    private fun TestScope.advance(rig: Rig, ms: Long) {
        var left = ms
        while (left > 0) {
            rig.clock.now += 1_000
            advanceTimeBy(1_000)
            runCurrent()
            left -= 1_000
        }
    }

    @Test fun pauseFreezesTheFiguresAndResumeReusesOneSessionAndRoute() = runTest {
        val route = route()
        val rig = harness(route)
        rig.nav.startNavigation()
        runCurrent()
        assertTrue(rig.nav.state.value.navigating)
        assertSame(route, rig.session.state.value.route)
        assertEquals(1, rig.voice.openers)
        assertEquals(1, rig.sessions(), "Start must create exactly one session")

        rig.fix(start.lat, start.lng, 12.0, 10.0)
        runCurrent()
        val leftBeforePause = rig.nav.state.value.remainingDistanceMeters
        val traveledBeforePause = rig.session.state.value.nav.traveledM
        val revisionBeforePause = rig.nav.state.value.routeRevision

        rig.nav.setPaused(true)
        runCurrent()
        assertTrue(rig.nav.state.value.paused)
        assertEquals(1, rig.voice.stops, "pause must cut the prompt in flight")
        val spokenAtPause = rig.voice.spoken.size

        // Four moving fixes on the route: without a preceding stop or off-route fix the core
        // auto-resume stays disarmed, so the hold is total.
        repeat(4) { i ->
            val f = 0.005 * (i + 1)
            rig.fix(
                start.lat + (middle.lat - start.lat) * f,
                start.lng + (middle.lng - start.lng) * f,
                12.0,
                10.0,
            )
            runCurrent()
        }
        assertTrue(rig.nav.state.value.paused, "a drive paused on the route must stay paused")
        assertEquals(spokenAtPause, rig.voice.spoken.size, "a paused drive must not speak")
        assertEquals(leftBeforePause, rig.nav.state.value.remainingDistanceMeters)
        assertEquals(traveledBeforePause, rig.session.state.value.nav.traveledM)
        assertEquals(revisionBeforePause, rig.nav.state.value.routeRevision)
        assertTrue(rig.nav.state.value.active, "pause keeps the drive, and therefore one Live Activity")

        val directionsBeforeResume = rig.source.directionCalls
        val spokenBeforeResume = rig.voice.spoken.size
        rig.nav.startNavigation() // a second Start while paused is ignored
        rig.nav.setPaused(false)
        runCurrent()
        assertFalse(rig.nav.state.value.paused)
        assertEquals(directionsBeforeResume, rig.source.directionCalls, "resume must not plan another route")
        assertEquals(1, rig.voice.openers, "resume must not restart guidance")
        assertEquals(1, rig.sessions(), "resume must not create a second session")
        assertEquals(spokenBeforeResume + 1, rig.voice.spoken.size, "resume says the current instruction")
        assertTrue(rig.nav.state.value.active)
        assertEquals(revisionBeforePause, rig.nav.state.value.routeRevision)

        rig.nav.stop()
        runCurrent()
        assertFalse(rig.nav.state.value.active)
    }

    @Test fun aStandstillAtSignalLossShowsTheChipWithoutTalkingOrMoving() = runTest {
        val rig = harness(route())
        rig.nav.startNavigation()
        runCurrent()
        rig.fix(start.lat, start.lng, 0.0, 10.0)
        runCurrent()
        val spoken = rig.voice.spoken.size
        val left = rig.nav.state.value.remainingDistanceMeters

        advance(rig, 12_000)
        assertTrue(rig.nav.state.value.starved, "12 s without a guidance fix must raise the no-GPS state")
        assertFalse(rig.nav.state.value.deadReckoning, "a standstill never starts dead reckoning")
        assertEquals(spoken, rig.voice.spoken.size, "a starved standstill must not repeat an instruction")
        assertEquals(left, rig.nav.state.value.remainingDistanceMeters)

        rig.fix(start.lat, start.lng, 12.0, 10.0)
        runCurrent()
        assertFalse(rig.nav.state.value.starved, "the first real fix clears the no-GPS state")
        assertFalse(rig.nav.state.value.deadReckoning)
        rig.nav.stop()
    }

    @Test fun deadReckoningAdvancesThenHoldsShortOfTheNextTurn() = runTest {
        val turn = LatLng(start.lat + 0.0004, start.lng)
        val route = shortTurnRoute(start, turn, LatLng(start.lat + 0.005, start.lng))
        val rig = harness(route)
        rig.nav.startNavigation()
        runCurrent()
        rig.fix(start.lat, start.lng, 12.0, 10.0)
        runCurrent()
        assertEquals(0.0, rig.session.state.value.nav.traveledM, 1.0)

        advance(rig, 5_000)
        assertTrue(rig.nav.state.value.deadReckoning, "guidance went quiet, so the estimator must steer")
        assertFalse(rig.nav.state.value.starved, "the chip waits the Android 10 s window")

        advance(rig, 20_000)
        assertTrue(rig.nav.state.value.starved)
        assertTrue(rig.nav.state.value.deadReckoning)
        val traveled = rig.session.state.value.nav.traveledM
        val turnAt = traveled + rig.session.state.value.nav.distanceToNextManeuver
        assertTrue(traveled > 5.0, "the estimate must move along the route")
        assertTrue(turnAt - traveled >= 10.0, "the estimate must hold short of the turn: $traveled of $turnAt")

        // The car really did take the turn: the first real fix re-anchors and guidance continues.
        rig.fix(turn.lat + 0.0003, turn.lng, 12.0, 10.0)
        runCurrent()
        assertFalse(rig.nav.state.value.starved)
        assertFalse(rig.nav.state.value.deadReckoning)
        assertSame(route, rig.session.state.value.route, "dead reckoning never replaces the route")
        rig.nav.stop()
    }

    @Test fun aPoorAccuracyFixMovesTheDotButNeverGuides() = runTest {
        val rig = harness(route())
        rig.nav.startNavigation()
        runCurrent()
        val left = rig.nav.state.value.remainingDistanceMeters
        rig.fix(middle.lat, middle.lng, 12.0, 80.0)
        runCurrent()
        assertEquals(middle.lat, rig.nav.state.value.latitude, "the dot still takes a coarse fix")
        assertEquals(left, rig.nav.state.value.remainingDistanceMeters, "an 80 m fix must not guide")
        assertEquals(80.0, rig.nav.state.value.accuracyM)

        advance(rig, 11_000)
        assertTrue(rig.nav.state.value.starved, "coarse fixes do not end starvation")

        rig.fix(middle.lat, middle.lng, 12.0, 10.0)
        runCurrent()
        assertFalse(rig.nav.state.value.starved)
        assertTrue(rig.nav.state.value.remainingDistanceMeters < left, "a 10 m fix guides again")
        rig.nav.stop()
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

    private fun shortTurnRoute(from: LatLng, turn: LatLng, destination: LatLng): Route {
        val first = from.distanceTo(turn)
        val second = turn.distanceTo(destination)
        val maneuvers = listOf(
            Maneuver(ManeuverType.DEPART, "Head north", from, first, 5.0, "Fixture Street"),
            Maneuver(ManeuverType.TURN_LEFT, "Turn left", turn, second, 40.0, "Second Street"),
            Maneuver(ManeuverType.ARRIVE, "Arrive", destination, 0.0, 0.0),
        )
        return Route(
            polyline = listOf(from, turn, destination),
            legs = listOf(RouteLeg(first + second, 45.0, null, maneuvers)),
            distanceMeters = first + second,
            durationSeconds = 45.0,
            durationInTrafficSeconds = null,
        )
    }
}
