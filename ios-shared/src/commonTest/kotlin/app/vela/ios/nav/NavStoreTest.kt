package app.vela.ios.nav

import app.vela.core.data.MapDataSource
import app.vela.core.model.Lane
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

private class NavSource(private val routes: List<Route>) : MapDataSource {
    constructor(route: Route) : this(listOf(route))

    var directionCalls = 0
        private set

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?) = SearchResult(query, emptyList())
    override suspend fun placeDetails(id: String) = Place(id = id, name = "", location = routes.first().polyline.last())
    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> {
        if (mode != TravelMode.DRIVE) return emptyList()
        val route = routes[directionCalls.coerceAtMost(routes.lastIndex)]
        directionCalls++
        return listOf(route)
    }
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
    var now = 1_000L
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

    @Test fun trafficOfferIsMirroredAndAcceptanceAdoptsTheCandidate() = runTest {
        if (!app.vela.ios.backgroundSchedulingIsDeterministic()) {
            println("traffic-offer timing test: JVM only (see TestPlatformSupport)")
            return@runTest
        }
        val current = route().copy(durationSeconds = 400.0, durationInTrafficSeconds = 600.0)
        val detour = LatLng(middle.lat + 0.004, middle.lng)
        val fasterManeuvers = listOf(
            Maneuver(ManeuverType.DEPART, "Head out", start, 2_600.0, 300.0, "Market Street"),
            Maneuver(ManeuverType.ARRIVE, "Arrive", end, 0.0, 0.0),
        )
        val faster = Route(
            polyline = listOf(start, detour, end),
            legs = listOf(RouteLeg(2_600.0, 300.0, 350.0, fasterManeuvers)),
            distanceMeters = 2_600.0,
            durationSeconds = 300.0,
            durationInTrafficSeconds = 350.0,
        )
        val source = NavSource(listOf(current, faster))
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = end))
        runCurrent()
        val clock = NavClock()
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { session }
        nav.start()
        nav.startNavigation()
        runCurrent()
        assertEquals(200.0, nav.state.value.trafficDelaySeconds, 0.0001)

        val notes = mutableListOf<String>()
        session.onNote = { notes += it }
        clock.now += 200_000L
        nav.onFix(start.lat, start.lng, 10.0, 12.0, 45.0, 2_000_000_000, gnss = true)
        // The common session runs its live recheck on its own scope. A loaded CI simulator can take
        // well over five seconds to finish it, so wait on the state with a generous deadline.
        withContext(Dispatchers.Default) {
            // A runner that also drives three simulators can take far longer than twenty seconds
            // to schedule this coroutine, so the deadline is generous on purpose.
            var tries = 0
            while (session.state.value.fasterRoute == null && tries < 9_000) {
                delay(10)
                tries++
            }
        }
        runCurrent()
        assertTrue(source.directionCalls >= 2, "the common session did not run its live recheck")
        assertTrue(
            nav.state.value.fasterRouteOffered,
            "no faster offer after the live recheck: ${notes.joinToString()} calls=${source.directionCalls}")
        assertTrue(nav.state.value.fasterSavingSeconds > 90.0)

        nav.acceptFasterRoute()
        runCurrent()
        assertSame(faster, session.state.value.route)
        assertFalse(nav.state.value.fasterRouteOffered)
        assertEquals(2_600.0, nav.state.value.routeDistanceMeters)
        assertEquals(350.0, nav.state.value.remainingDurationSeconds)
        nav.stop()
    }

    @Test fun maneuverCarriesLanesRefAndCurrentRoad() = runTest {
        val maneuvers = listOf(
            Maneuver(
                ManeuverType.DEPART, "Head out", start, 1_300.0, 100.0, "Market Street",
                ref = "I 80"),
            Maneuver(
                ManeuverType.TURN_LEFT, "Turn left onto US 50", middle, 1_300.0, 100.0, "US 50",
                ref = "US 50",
                laneHint = "Use the left 2 lanes",
                lanes = listOf(
                    Lane(listOf("left"), true),
                    Lane(listOf("left", "straight"), true),
                    Lane(listOf("straight", "right"), false),
                )),
            Maneuver(ManeuverType.ARRIVE, "Arrive", end, 0.0, 0.0),
        )
        val route = Route(
            polyline = listOf(start, middle, end),
            legs = listOf(RouteLeg(2_600.0, 200.0, null, maneuvers)),
            distanceMeters = 2_600.0,
            durationSeconds = 200.0,
            durationInTrafficSeconds = null,
        )
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = end))
        runCurrent()
        val clock = NavClock()
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { session }
        nav.start()
        nav.startNavigation()
        runCurrent()

        nav.onFix(
            (start.lat + middle.lat) / 2,
            (start.lng + middle.lng) / 2,
            10.0, 12.0, 45.0, 2_000_000_000, gnss = true)
        runCurrent()

        val state = nav.state.value
        assertEquals("TURN_LEFT", state.maneuver?.type)
        assertEquals("US 50", state.maneuver?.ref)
        assertEquals("Use the left 2 lanes", state.maneuver?.laneHint)
        assertEquals(3, state.maneuver?.lanes?.size)
        assertEquals(listOf("left", "straight"), state.maneuver?.lanes?.get(1)?.indications)
        assertTrue(state.maneuver?.lanes?.get(1)?.valid == true)
        assertFalse(state.maneuver?.lanes?.get(2)?.valid == true)
        // The road under the car came from the leg just entered, not from the next turn.
        assertEquals("I 80", state.currentRoadRef)
        assertEquals("I 80", state.currentRoadLabel)
    }

    @Test fun bannerPreviewWalksStepsAndRestoresLiveGuidance() = runTest {
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = end))
        runCurrent()
        val clock = NavClock()
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { session }
        nav.start()
        nav.startNavigation()
        runCurrent()

        nav.preview(stepOffset = 1)
        assertEquals(1, nav.state.value.previewIndex)
        assertEquals("TURN_LEFT", nav.state.value.previewManeuver?.type)
        nav.preview(stepOffset = 1)
        assertEquals(2, nav.state.value.previewIndex)
        assertEquals("ARRIVE", nav.state.value.previewManeuver?.type)
        nav.preview(stepOffset = -1)
        assertEquals(1, nav.state.value.previewIndex)

        nav.exitPreview()
        assertEquals(null, nav.state.value.previewIndex)
        assertEquals(null, nav.state.value.previewManeuver)
        assertEquals("DEPART", nav.state.value.maneuver?.type)
    }

    @Test fun voiceModePersistsUnderAndroidKeys() = runTest {
        val stores = NavMemStores()
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = end))
        runCurrent()
        val clock = NavClock()
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock, keyValues = { stores }) { session }
        nav.start()
        runCurrent()
        assertFalse(nav.state.value.voiceMuted)
        assertFalse(nav.state.value.voiceAlertsOnly)

        nav.cycleVoiceMode()
        assertTrue(nav.state.value.voiceMuted)
        assertTrue(nav.state.value.voiceAlertsOnly)
        val settings = stores.open(NavStore.SETTINGS_STORE)
        assertFalse(settings.getBoolean(NavStore.KEY_SPOKEN_DIRECTIONS, true))
        assertTrue(settings.getBoolean(NavStore.KEY_SPOKEN_ALERTS_ONLY, false))

        nav.cycleVoiceMode()
        assertTrue(nav.state.value.voiceMuted)
        assertFalse(nav.state.value.voiceAlertsOnly)
        assertFalse(settings.getBoolean(NavStore.KEY_SPOKEN_ALERTS_ONLY, true))

        // A second process reads the same two keys and starts in the same voice mode.
        val secondSession = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val second = NavStore(routes, { source }, backgroundScope, clock, keyValues = { stores }) { secondSession }
        second.start()
        runCurrent()
        assertTrue(second.state.value.voiceMuted)
        assertFalse(second.state.value.voiceAlertsOnly)
        second.stop()
    }

    @Test fun freeDriveShowsTheRoadLimitAndKeepsTheVoiceMode() = runTest {
        val stores = NavMemStores()
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        val clock = NavClock().also { it.now = 100_000L }
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock, keyValues = { stores }) { session }
        nav.attachFreeDriveHttp(FreeDriveTestHttp())
        nav.start()
        nav.startFreeDrive()
        runCurrent()
        assertTrue(nav.state.value.freeDriving)
        assertFalse(nav.state.value.navigating)
        assertFalse(nav.state.value.active)
        assertFalse(stores.open(NavStore.RESUME_STORE).contains(NavStore.RESUME_LAT),
            "free driving must not write a guided-drive resume record")

        nav.onFix(37.7749, -122.4194, 6.0, 20.0, 45.0, 2_000_000_000, gnss = true)
        runCurrent()
        assertEquals(20.0, nav.state.value.speedMps)
        assertEquals(50.0, nav.state.value.speedLimitKmh, "the OSM maxspeed did not reach the badge")
        assertEquals("Market Street", nav.state.value.currentRoadLabel)
        assertEquals("US 101", nav.state.value.currentRoadRef)

        nav.cycleVoiceMode()
        assertTrue(nav.state.value.voiceMuted)
        assertTrue(nav.state.value.voiceAlertsOnly)
        val settings = stores.open(NavStore.SETTINGS_STORE)
        assertFalse(settings.getBoolean(NavStore.KEY_SPOKEN_DIRECTIONS, true))
        assertTrue(settings.getBoolean(NavStore.KEY_SPOKEN_ALERTS_ONLY, false))

        nav.stopFreeDrive()
        runCurrent()
        assertFalse(nav.state.value.freeDriving)
        assertNull(nav.state.value.speedLimitKmh)
        assertTrue(nav.state.value.currentRoadLabel.isEmpty())
        assertEquals(20.0, nav.state.value.speedMps, "leaving the mode keeps the live speed on the map")
        assertTrue(session.state.value.route == null, "free driving must not start a navigation session")
        assertFalse(stores.open(NavStore.RESUME_STORE).contains(NavStore.RESUME_LAT))
    }

    @Test fun freeDriveSurvivesAForegroundWithoutStartingThePersistedDrive() = runTest {
        val stores = NavMemStores()
        stores.open(NavStore.RESUME_STORE).edit()
            .putLong(NavStore.RESUME_AT, 1_000L)
            .putString(NavStore.RESUME_LAT, end.lat.toString())
            .putString(NavStore.RESUME_LNG, end.lng.toString())
            .putString(NavStore.RESUME_LABEL, "Fixture destination")
            .putString(NavStore.RESUME_MODE, "DRIVE")
            .apply()
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        val clock = NavClock().also { it.now = 100_000L }
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock, keyValues = { stores }) { session }
        nav.start()
        nav.startFreeDrive()
        runCurrent()
        assertTrue(nav.state.value.freeDriving)
        assertFalse(nav.state.value.navigating)

        nav.resumeNavigation()
        runCurrent()
        assertFalse(nav.state.value.navigating)
        assertFalse(nav.state.value.resumedFromRecord)
        assertEquals(0, nav.state.value.sessionStarts, "a free drive has no session to resume")
    }

    @Test fun addingAStopDuringADriveShowsRecalculationThenFreshStopEta() = runTest {
        val stop = LatLng(37.7857, -122.4054)
        val first = route()
        val throughStop = Route(
            polyline = listOf(start, stop, end),
            legs = listOf(RouteLeg(2_700.0, 220.0, null, first.maneuvers)),
            distanceMeters = 2_700.0,
            durationSeconds = 220.0,
            durationInTrafficSeconds = null,
        )
        val source = NavSource(listOf(first, throughStop))
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        routes.directionsTo(Place(id = "destination", name = "Fixture destination", location = end))
        runCurrent()
        val clock = NavClock().also { it.now = 1_000L }
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { session }
        nav.start()
        nav.startNavigation()
        runCurrent()
        nav.onFix(start.lat, start.lng, 6.0, 10.0, 45.0, 2_000_000_000, gnss = true)
        runCurrent()
        assertEquals(0, nav.state.value.stopsAhead)

        nav.addStop(name = "Coffee", latitude = stop.lat, longitude = stop.lng)
        // The recalculation starts at once, before the new route lands.
        assertTrue(nav.state.value.stopsRecalculating)
        assertEquals(1, nav.state.value.stopAdds)
        assertEquals(1, session.remainingStops().size)

        withContext(Dispatchers.Default) {
            var tries = 0
            while (nav.state.value.stopsRecalculating && tries < 500) {
                delay(10)
                tries++
            }
        }
        runCurrent()
        assertFalse(nav.state.value.stopsRecalculating, "the recalculation state stayed on after the route")
        assertEquals(1, nav.state.value.stopsAhead)
        assertTrue(nav.state.value.nextStopLabel.isNotEmpty(), "the new stop has no name")
        assertTrue(nav.state.value.nextStopSeconds > 0.0, "the per-stop ETA did not refresh")
        assertEquals(1, nav.state.value.sessionStarts, "adding a stop must not start a second session")
        assertTrue(nav.state.value.navigating)
        nav.stop()
    }

    @Test fun alertCueFollowsTheThreeWayVoiceMode() {
        assertEquals(NavAlertCue.SPEAK, navAlertCue(muted = false, alertsOnly = false))
        assertEquals(NavAlertCue.CHIME, navAlertCue(muted = true, alertsOnly = true))
        assertEquals(NavAlertCue.SILENT, navAlertCue(muted = true, alertsOnly = false))
    }

    @Test fun resumeRecordRestoresTheDriveAndEndClearsIt() = runTest {
        val stores = NavMemStores()
        stores.open(NavStore.RESUME_STORE).edit()
            .putLong(NavStore.RESUME_AT, 1_000L)
            .putString(NavStore.RESUME_LAT, end.lat.toString())
            .putString(NavStore.RESUME_LNG, end.lng.toString())
            .putString(NavStore.RESUME_LABEL, "Fixture destination")
            .putString(NavStore.RESUME_MODE, "DRIVE")
            .apply()
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        val clock = NavClock().also { it.now = 5_000L }
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock, keyValues = { stores }) { session }
        nav.onFix(middle.lat, middle.lng, 10.0, 12.0, 45.0, 2_000_000_000, gnss = true)
        nav.start()
        runCurrent()

        assertTrue(nav.state.value.navigating, "the persisted drive did not resume")
        assertTrue(nav.state.value.resumedFromRecord)
        assertEquals("Fixture destination", nav.state.value.destinationLabel)
        assertEquals(1, nav.state.value.sessionStarts)
        assertTrue(nav.state.value.remainingDurationSeconds > 0.0)
        assertSame(route, session.state.value.route)
        assertEquals(1, source.directionCalls, "the resumed drive must be planned exactly once")

        nav.resumeNavigation()
        runCurrent()
        assertEquals(1, nav.state.value.sessionStarts, "a second plan would duplicate the session")

        nav.stop()
        runCurrent()
        assertFalse(stores.open(NavStore.RESUME_STORE).contains(NavStore.RESUME_LAT))
    }

    @Test fun staleResumeRecordIsDropped() = runTest {
        val stores = NavMemStores()
        stores.open(NavStore.RESUME_STORE).edit()
            .putLong(NavStore.RESUME_AT, 1_000L)
            .putString(NavStore.RESUME_LAT, end.lat.toString())
            .putString(NavStore.RESUME_LNG, end.lng.toString())
            .putString(NavStore.RESUME_LABEL, "Old destination")
            .putString(NavStore.RESUME_MODE, "DRIVE")
            .apply()
        val route = route()
        val source = NavSource(route)
        val routes = RouteStore({ source }, backgroundScope).also { it.start() }
        val clock = NavClock().also { it.now = 2 * 60 * 60 * 1000L }
        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock, keyValues = { stores }) { session }
        nav.start()
        runCurrent()
        assertFalse(nav.state.value.navigating)
        assertFalse(stores.open(NavStore.RESUME_STORE).contains(NavStore.RESUME_LAT))
    }

    @Test fun closingWarningSurvivesARouteSwapAndClearsOnEnd() = runTest {
        val nowMs = 1_791_460_000_000L
        val nowSec = nowMs / 1_000L
        val clock = NavClock().also { it.now = nowMs }
        val long = timedRoute(1_200.0)
        val source = NavSource(long)
        val routes = RouteStore({ source }, backgroundScope, now = { nowMs }).also { it.start() }
        routes.onLocation(start.lat, start.lng)
        val destination = Place(
            id = "destination", name = "Vela Shop", location = end,
            statusText = closingStatus(nowSec, 75), openNow = true)
        routes.directionsTo(destination)
        runCurrent()

        val session = NavStore.session(source, RecordingVoice(), NoHaptics, NoLog, clock)
        val nav = NavStore(routes, { source }, backgroundScope, clock) { session }
        nav.start()
        nav.startNavigation()
        runCurrent()

        val warning = assertNotNull(nav.state.value.closingWarning)
        assertEquals("Vela Shop", warning.name)
        assertFalse(warning.beforeArrival)

        // A swap to a five-minute route lands 70 minutes before closing: the line goes away.
        session.replaySetRoute(timedRoute(300.0), chime = false)
        runCurrent()
        assertNull(nav.state.value.closingWarning)

        // The long route again: the destination still closes inside the window.
        session.replaySetRoute(long, chime = false)
        runCurrent()
        assertNotNull(nav.state.value.closingWarning)

        nav.stop()
        runCurrent()
        assertNull(nav.state.value.closingWarning)
    }

    private fun route(): Route = timedRoute(200.0)

    private fun timedRoute(seconds: Double): Route {
        val maneuvers = listOf(
            Maneuver(ManeuverType.DEPART, "Head out", start, 1_300.0, 100.0, "Market Street"),
            Maneuver(ManeuverType.TURN_LEFT, "Turn left", middle, 1_300.0, 100.0, "Second Street"),
            Maneuver(ManeuverType.ARRIVE, "Arrive", end, 0.0, 0.0),
        )
        return Route(
            polyline = listOf(start, middle, end),
            legs = listOf(RouteLeg(2_600.0, seconds, null, maneuvers)),
            distanceMeters = 2_600.0,
            durationSeconds = seconds,
            durationInTrafficSeconds = null,
        )
    }
}

private fun twoDigits(n: Int) = if (n < 10) "0$n" else "$n"

/** Google's own status shape, [plusMinutes] after [nowSec] in the phone's zone. */
private fun closingStatus(nowSec: Long, plusMinutes: Int): String {
    val at = Instant.fromEpochSeconds(nowSec).toLocalDateTime(TimeZone.currentSystemDefault())
    val minute = (at.hour * 60 + at.minute + plusMinutes) % 1_440
    return "Open · Closes ${twoDigits(minute / 60)}:${twoDigits(minute % 60)}"
}

/** In-memory [KeyValueStores] with the platform contract: one type per key, clear first. */
/** The free-drive road reply: one drivable way through the fixture fix, with name, ref and limit. */
private class FreeDriveTestHttp : app.vela.core.platform.VelaHttp {
    override fun execute(
        request: app.vela.core.platform.HttpRequest,
        callback: (app.vela.core.platform.HttpResponse?, Throwable?) -> Unit,
    ): app.vela.core.platform.Cancellable {
        val body = """
            {"elements":[{"tags":{"highway":"primary","name":"Market Street","ref":"US 101","maxspeed":"50"},
            "geometry":[{"lat":37.7749,"lon":-122.4195},{"lat":37.7749,"lon":-122.4193}]}]}
        """.trimIndent()
        callback(
            app.vela.core.platform.HttpResponse(
                code = 200,
                headers = emptyList(),
                body = body.encodeToByteArray(),
                finalUrl = request.url,
            ),
            null,
        )
        return app.vela.core.platform.Cancellable {}
    }
}

private class NavMemStores : app.vela.core.platform.KeyValueStores {
    private val stores = HashMap<String, NavMemStore>()
    override fun open(name: String): app.vela.core.platform.KeyValueStore =
        stores.getOrPut(name) { NavMemStore() }
}

private class NavMemStore : app.vela.core.platform.KeyValueStore {
    private val values = LinkedHashMap<String, Any>()

    private inline fun <reified T> get(key: String, default: T): T {
        val value = values[key] ?: return default
        return value as? T ?: throw ClassCastException(key)
    }

    override fun contains(key: String): Boolean = key in values
    override fun getString(key: String, default: String?): String? =
        values[key]?.let { it as? String ?: throw ClassCastException(key) } ?: default
    override fun getLong(key: String, default: Long): Long = get(key, default)
    override fun getInt(key: String, default: Int): Int = get(key, default)
    override fun getBoolean(key: String, default: Boolean): Boolean = get(key, default)
    override fun getFloat(key: String, default: Float): Float = get(key, default)
    override fun keys(): Set<String> = values.keys.toSet()

    override fun edit(): app.vela.core.platform.KeyValueEditor = object : app.vela.core.platform.KeyValueEditor {
        private var clear = false
        private val changes = ArrayList<(MutableMap<String, Any>) -> Unit>()

        override fun putString(key: String, value: String?): app.vela.core.platform.KeyValueEditor =
            op { if (value == null) it.remove(key) else it[key] = value }
        override fun putLong(key: String, value: Long): app.vela.core.platform.KeyValueEditor =
            op { it[key] = value }
        override fun putInt(key: String, value: Int): app.vela.core.platform.KeyValueEditor =
            op { it[key] = value }
        override fun putBoolean(key: String, value: Boolean): app.vela.core.platform.KeyValueEditor =
            op { it[key] = value }
        override fun putFloat(key: String, value: Float): app.vela.core.platform.KeyValueEditor =
            op { it[key] = value }
        override fun remove(key: String): app.vela.core.platform.KeyValueEditor =
            op { it.remove(key) }
        override fun clear(): app.vela.core.platform.KeyValueEditor = also { clear = true }

        override fun apply() {
            if (clear) values.clear()
            changes.forEach { it(values) }
        }

        override fun commit(): Boolean {
            apply()
            return true
        }

        private fun op(change: (MutableMap<String, Any>) -> Unit): app.vela.core.platform.KeyValueEditor =
            also { changes += change }
    }
}
