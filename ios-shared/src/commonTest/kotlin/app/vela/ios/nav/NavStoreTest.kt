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
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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
            var tries = 0
            while (session.state.value.fasterRoute == null && tries < 2_000) {
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

/** In-memory [KeyValueStores] with the platform contract: one type per key, clear first. */
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
