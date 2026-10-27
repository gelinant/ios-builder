package app.vela.ios.route

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.RoutingPrefs
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.Lane
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.RouteLeg
import app.vela.core.model.TrafficSpan
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitLine
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import app.vela.core.model.TravelMode
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

private data class Ask(
    val origin: LatLng,
    val dest: LatLng,
    val mode: TravelMode,
    val avoidTolls: Boolean,
    val avoidHighways: Boolean,
    val avoidFerries: Boolean = false,
    val waypoints: List<LatLng> = emptyList(),
)

/** A source whose answers the test hands out one call at a time. */
private class FakeDirections : MapDataSource {
    val asks = mutableListOf<Ask>()
    val answers = mutableListOf<CompletableDeferred<List<Route>>>()

    override suspend fun search(query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?): SearchResult = error("unused")
    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean, departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> {
        asks += Ask(origin, destination, mode, avoidTolls, avoidHighways, avoidFerries, waypoints)
        val answer = CompletableDeferred<List<Route>>()
        answers += answer
        return answer.await()
    }

    var naming: (Route) -> Route = { it }

    override suspend fun nameRoute(
        route: Route, origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean,
    ): Route = naming(route)
}

private class MemKv : KeyValueStore {
    val values = mutableMapOf<String, Any?>()
    override fun contains(key: String) = key in values
    override fun getString(key: String, default: String?) = values[key] as String? ?: default
    override fun getLong(key: String, default: Long) = values[key] as Long? ?: default
    override fun getInt(key: String, default: Int) = values[key] as Int? ?: default
    override fun getBoolean(key: String, default: Boolean) = values[key] as Boolean? ?: default
    override fun getFloat(key: String, default: Float) = values[key] as Float? ?: default
    override fun keys() = values.keys.toSet()
    override fun edit(): KeyValueEditor = Editor()

    private inner class Editor : KeyValueEditor {
        val pending = mutableMapOf<String, Any?>()
        private fun put(key: String, value: Any?): KeyValueEditor { pending[key] = value; return this }
        override fun putString(key: String, value: String?) = put(key, value)
        override fun putLong(key: String, value: Long) = put(key, value)
        override fun putInt(key: String, value: Int) = put(key, value)
        override fun putBoolean(key: String, value: Boolean) = put(key, value)
        override fun putFloat(key: String, value: Float) = put(key, value)
        override fun remove(key: String) = put(key, null)
        override fun clear(): KeyValueEditor = this
        override fun apply() { values.putAll(pending) }
        override fun commit(): Boolean { apply(); return true }
    }
}

private val ME = LatLng(37.7749, -122.4194)
private val FERRY = LatLng(37.7942, -122.3946)
private val ferry = Place(id = "ferry", name = "Ferry Building", location = FERRY)

private fun route(seconds: Double, traffic: Double? = null, via: String = "Market St") = Route(
    polyline = listOf(ME, LatLng(37.7857, -122.4054), FERRY),
    legs = emptyList(),
    distanceMeters = 2600.0,
    durationSeconds = seconds,
    durationInTrafficSeconds = traffic,
    summary = via,
)

@OptIn(ExperimentalCoroutinesApi::class)
class RouteStoreTest {
    @Test fun constructionDoesNothingAndDirectionsWaitForStart() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope)
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        assertFalse(store.state.value.open)
        assertTrue(src.asks.isEmpty())
    }

    @Test fun aDirectionsLinkGivesItsOwnStartAndMode() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        val sacramento = Place(
            id = "link:sacramento", name = "Sacramento, CA",
            location = LatLng(38.5815719, -121.4943996))
        val davis = Place(
            id = "link:davis", name = "Davis, CA",
            location = LatLng(38.5449065, -121.7405167))
        store.directionsFrom(sacramento, davis, TravelMode.WALK)
        runCurrent()
        assertEquals(
            Ask(LatLng(38.5815719, -121.4943996), LatLng(38.5449065, -121.7405167), TravelMode.WALK, false, false),
            src.asks.single())
        assertEquals("WALK", store.state.value.modeName)
        assertEquals("Davis, CA", store.state.value.destination?.name)
        assertEquals("Sacramento, CA", store.state.value.origin?.name)
    }

    @Test fun directionsRouteFromTheFixAndKeepTheRouteObjects() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        assertTrue(store.state.value.loading)
        assertEquals(Ask(ME, FERRY, TravelMode.DRIVE, false, false), src.asks.single())
        val a = route(600.0, 720.0)
        val b = route(660.0, 700.0, via = "Mission St")
        src.answers[0].complete(listOf(a, b))
        runCurrent()
        val s = store.state.value
        assertFalse(s.loading)
        assertSame(a, s.active)
        assertSame(a, s.routes[0])
        assertSame(b, s.routes[1])
        assertEquals(0, s.activeIndex)
        assertEquals(700.0, s.modeSeconds[TravelMode.DRIVE])
        assertEquals(700.0, s.secondsOf("DRIVE"))
        assertEquals(-1.0, s.secondsOf("WALK"))
        assertEquals(RouteRow(720.0, 2600.0, "Market St", 120.0, true), s.rows()[0])
        assertEquals("DRIVE", s.modeName)
        store.select(1)
        assertSame(b, store.state.value.active)
        assertEquals(1, store.state.value.activeIndex)
        assertEquals(120.0, RouteStore.trafficDelaySeconds(a))
        assertEquals(0.0, RouteStore.trafficDelaySeconds(route(600.0)))
    }

    @Test fun theOtherModesAreTimedAfterTheFirstAndNotForTransit() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        src.answers[0].complete(listOf(route(600.0)))
        runCurrent()
        assertEquals(TravelMode.WALK, src.asks[1].mode)
        src.answers[1].complete(listOf(route(2000.0)))
        runCurrent()
        assertEquals(TravelMode.BICYCLE, src.asks[2].mode)
        src.answers[2].complete(emptyList())
        runCurrent()
        assertEquals(3, src.asks.size)
        assertEquals(mapOf(TravelMode.DRIVE to 600.0, TravelMode.WALK to 2000.0), store.state.value.modeSeconds)
        // Walking is now known: switching asks once, the cached time stays.
        store.setMode(TravelMode.WALK)
        runCurrent()
        assertEquals(TravelMode.WALK, src.asks[3].mode)
        assertEquals(4, src.asks.size)
        store.setMode(TravelMode.TRANSIT)
        runCurrent()
        assertIs<RouteError.ModeUnavailable>(store.state.value.error)
        // Transit itself asks nothing; the bike time still missing is fetched.
        assertEquals(5, src.asks.size)
        assertEquals(TravelMode.BICYCLE, src.asks.last().mode)
    }

    @Test fun aReplyForAModeLeftBehindIsDropped() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        store.setMode(TravelMode.WALK)
        runCurrent()
        src.answers[0].complete(listOf(route(600.0)))
        runCurrent()
        assertTrue(store.state.value.routes.isEmpty())
        val walk = route(2000.0)
        src.answers[1].complete(listOf(walk))
        runCurrent()
        assertSame(walk, store.state.value.active)
        store.close()
        assertFalse(store.state.value.open)
        assertNull(store.state.value.active)
    }

    @Test fun withoutAFixTheMapCenterIsTheStartAndReverseSwapsTheEnds() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.directionsTo(ferry)
        runCurrent()
        assertIs<RouteError.NoOrigin>(store.state.value.error)
        assertTrue(src.asks.isEmpty())
        store.onMapCenter(FERRY.lat, FERRY.lng)
        store.retry()
        assertIs<RouteError.NoOrigin>(store.state.value.error)
        store.onMapCenter(ME.lat, ME.lng)
        store.retry()
        runCurrent()
        assertTrue(store.state.value.fromMapCenter)
        assertEquals(ME, src.asks[0].origin)
        store.swap()
        runCurrent()
        assertTrue(store.state.value.reversed)
        assertEquals(FERRY, src.asks[1].origin)
        assertEquals(ME, src.asks[1].dest)
        val davis = Place(id = "d", name = "Davis", location = LatLng(38.5449, -121.7405))
        store.setOrigin(davis)
        runCurrent()
        assertFalse(store.state.value.fromMapCenter)
        assertEquals(davis.location, src.asks[2].dest)
    }

    @Test fun originChoicesSurviveSwapAndEditTheDisplayedStart() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        val pin = LatLng(37.7810, -122.4100)
        store.onLocation(ME.lat, ME.lng)
        store.onMapCenter(pin.lat, pin.lng)
        store.directionsTo(ferry)
        runCurrent()
        val searched = Place(id = "searched", name = "Embarcadero", location = LatLng(37.7955, -122.3968))
        store.setStart(searched)
        runCurrent()
        assertEquals(searched.location, src.asks[1].origin)
        store.swap()
        runCurrent()
        assertTrue(store.state.value.reversed)
        assertEquals(FERRY, src.asks[2].origin)
        assertEquals(searched.location, src.asks[2].dest)

        // Editing the displayed origin of the reversed trip keeps its displayed destination.
        store.setStartPlace("saved", "Saved place", null, 37.7920, -122.4000)
        runCurrent()
        assertFalse(store.state.value.reversed)
        assertEquals(searched, store.state.value.destination)
        assertEquals(LatLng(37.7920, -122.4000), src.asks[3].origin)
        assertEquals(searched.location, src.asks[3].dest)
        store.setStartToMapCenter()
        runCurrent()
        assertEquals(pin, src.asks[4].origin)
        assertEquals("Dropped pin", store.state.value.origin?.name)
        store.setStart(null)
        runCurrent()
        assertEquals(ME, src.asks[5].origin)
        assertNull(store.state.value.origin)
    }

    @Test fun waypointsAreAddedReorderedRemovedAndSentInTravelOrder() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        val a = Place(id = "a", name = "Stop A", location = LatLng(37.7800, -122.4100))
        val b = Place(id = "b", name = "Stop B", location = LatLng(37.7900, -122.4000))
        store.addWaypoint(a)
        runCurrent()
        store.addWaypointPlace(b.id, b.name, null, b.location.lat, b.location.lng)
        runCurrent()
        assertEquals(listOf(a.location, b.location), src.asks[2].waypoints)
        store.moveWaypoint(0, 1)
        runCurrent()
        assertEquals(listOf(b, a), store.state.value.waypoints)
        assertEquals(listOf(b.location, a.location), src.asks[3].waypoints)
        store.swap()
        runCurrent()
        assertEquals(listOf(a, b), store.state.value.waypoints)
        assertEquals(listOf(a.location, b.location), src.asks[4].waypoints)
        assertEquals(FERRY, src.asks[4].origin)
        assertEquals(ME, src.asks[4].dest)
        store.removeWaypoint(0)
        runCurrent()
        assertEquals(listOf(b), store.state.value.waypoints)
        assertEquals(listOf(b.location), src.asks[5].waypoints)
        assertEquals(listOf(b.location.lat, b.location.lng), store.waypointPoints().toList())
    }

    @Test fun timeChangesOnlyRefetchTransitAndPassDepartAndArrive() = runTest {
        val src = FakeDirections()
        val timeAsks = mutableListOf<Pair<Int, Long?>>()
        val store = RouteStore({ src }, backgroundScope, transitPlanner = { _, _, mode, epoch ->
            timeAsks += mode to epoch
            emptyList()
        }).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        assertEquals(1, src.asks.size)
        store.setTime(1, 2_000)
        runCurrent()
        assertEquals(1, src.asks.size, "keyless driving must not refetch for a departure time")
        assertEquals(1, store.state.value.timeMode)
        assertEquals(2_000L, store.state.value.timeEpoch)
        store.setMode(TravelMode.TRANSIT)
        runCurrent()
        store.setTime(2, 3_000)
        runCurrent()
        store.setTime(0, 0)
        runCurrent()
        assertEquals(listOf(1 to 2_000L, 2 to 3_000L, 0 to null), timeAsks)
        assertNull(store.state.value.timeEpochSec)
    }

    @Test fun modeAndAvoidsAreStickyInVelaSettings() = runTest {
        val kv = MemKv()
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope, settings = { kv }).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        store.setAvoidHighways(true)
        runCurrent()
        assertTrue(src.asks.last().avoidHighways)
        assertTrue(RoutingPrefs.avoidHighways)
        store.setMode(TravelMode.BICYCLE)
        store.setAvoidTolls(true)
        store.setAvoidFerries(true)
        assertEquals("BICYCLE", kv.values["travel_mode"])
        assertEquals(true, kv.values["avoid_highways"])
        assertEquals(true, kv.values["avoid_tolls"])
        assertEquals(true, kv.values["avoid_ferries"])
        val next = RouteStore({ src }, backgroundScope, settings = { kv }).also { it.start() }
        assertEquals(TravelMode.BICYCLE, next.state.value.mode)
        assertTrue(next.state.value.avoidHighways)
        assertTrue(next.state.value.avoidTolls)
        assertTrue(next.state.value.avoidFerries)
        store.setAvoidHighways(false)
        store.setAvoidTolls(false)
        store.setAvoidFerries(false)
        assertFalse(RoutingPrefs.avoidHighways)
        assertFalse(RoutingPrefs.avoidTolls)
        assertFalse(RoutingPrefs.avoidFerries)
    }

    @Test fun bikeSafeFollowsTheAndroidPreferenceKey() = runTest {
        val old = RoutingPrefs.bikeSafe
        try {
            val kv = MemKv().apply { values["bike_safe"] = false }
            val src = FakeDirections()
            val store = RouteStore({ src }, backgroundScope, settings = { kv }).also { it.start() }
            assertFalse(store.state.value.bikeSafe)
            assertFalse(RoutingPrefs.bikeSafe)
            store.onLocation(ME.lat, ME.lng)
            store.directionsTo(ferry)
            runCurrent()
            store.setBikeSafe(true)
            assertTrue(store.state.value.bikeSafe)
            assertTrue(RoutingPrefs.bikeSafe)
            assertEquals(true, kv.values["bike_safe"])
            // A bike route is replanned at once when the preference changes.
            store.setMode(TravelMode.BICYCLE)
            runCurrent()
            val before = src.asks.size
            store.setBikeSafe(false)
            runCurrent()
            assertEquals(before + 1, src.asks.size)
            assertEquals(TravelMode.BICYCLE, src.asks.last().mode)
        } finally {
            RoutingPrefs.bikeSafe = old
        }
    }

    @Test fun noGoogleTransitWithoutAPlannerIsAnHonestError() = runTest {
        val old = NoGoogle.enabled
        NoGoogle.enabled = true
        try {
            val src = FakeDirections()
            val store = RouteStore({ src }, backgroundScope).also { it.start() }
            store.onLocation(ME.lat, ME.lng)
            store.directionsTo(ferry)
            runCurrent()
            assertTrue(store.state.value.googleOff)
            store.setMode(TravelMode.TRANSIT)
            runCurrent()
            assertIs<RouteError.ModeUnavailable>(store.state.value.error)
            assertEquals(TravelMode.TRANSIT.name, store.state.value.modeName)
        } finally {
            NoGoogle.enabled = old
        }
    }

    @Test fun errorsAreTyped() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        src.answers[0].complete(emptyList())
        runCurrent()
        assertEquals(RouteError.NoRoute(TravelMode.DRIVE), store.state.value.error)
        store.retry()
        runCurrent()
        src.answers.last().completeExceptionally(CalibrationNeededException("directions"))
        runCurrent()
        assertIs<RouteError.NeedsRecalibration>(store.state.value.error)
    }

    @Test fun trafficSpansAreCutOutOfTheDrawnLine() {
        val r = route(600.0, 700.0).copy(trafficSpans = listOf(TrafficSpan(2, 500.0, 600.0)))
        val lines = RouteStore.trafficOn(r)
        val line = lines.single()
        assertEquals(2, line.level)
        assertTrue(line.points.size >= 4)
        assertEquals(6, RouteStore.lineOf(r).size)
    }

    @Test fun transitAsksThePlannerAndListsItsLegs() = runTest {
        val src = FakeDirections()
        val plans = mutableListOf<CompletableDeferred<List<TransitItinerary>>>()
        val store = RouteStore({ src }, backgroundScope, transitPlanner = { _, _, _, _ ->
            CompletableDeferred<List<TransitItinerary>>().also { plans += it }.await()
        }).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        store.setMode(TravelMode.TRANSIT)
        runCurrent()
        assertTrue(store.state.value.loading)
        val bus = TransitStep(
            mode = TransitMode.BUS, durationText = "12 min", line = TransitLine("14", TransitMode.BUS, "#cc0000"),
            departText = "9:05 AM", arriveText = "9:17 AM", boardStop = TransitStopTime("Mission & 9th", location = ME),
            alightStop = TransitStopTime("Ferry Plaza", location = FERRY), numStops = 9,
        )
        val walk = TransitStep(mode = TransitMode.WALK, durationText = "3 min", walkFrom = FERRY, walkTo = FERRY)
        val trip = TransitItinerary(departureEpochSec = 1_000, arrivalEpochSec = 1_900, departureText = "9:05 AM", steps = listOf(bus, walk))
        plans.last().complete(listOf(trip, trip.copy(departureEpochSec = 1_600, arrivalEpochSec = 2_400)))
        runCurrent()
        val s = store.state.value
        assertEquals(2, s.transit.size)
        assertEquals(0, s.activeIndex)
        assertEquals(900.0, s.secondsOf("TRANSIT"))
        val row = s.transitRows()[0]
        assertEquals(900.0, row.seconds)
        assertEquals(TransitLegRow("BUS", "14", "#cc0000", null, "12 min", "9:05 AM", "9:17 AM", "Mission & 9th", "Ferry Plaza", null, 9, null), row.legs[0])
        assertEquals("WALK", row.legs[1].kind)
        assertEquals(8, store.line(0).size)
        store.select(1)
        assertEquals(1, store.state.value.activeIndex)
        store.showSteps(true)
        assertTrue(store.state.value.showSteps)
        store.setMode(TravelMode.DRIVE)
        assertTrue(store.state.value.transit.isEmpty())
    }

    @Test fun transitOptionsReachThePlannerAndReplan() = runTest {
        val src = FakeDirections()
        val queries = mutableListOf<app.vela.ios.transit.TransitPlanQuery>()
        val plans = mutableListOf<CompletableDeferred<List<TransitItinerary>>>()
        val store = RouteStore(
            { src }, backgroundScope,
            transitOptionsPlanner = { _, _, q ->
                queries += q
                CompletableDeferred<List<TransitItinerary>>().also { plans += it }.await()
            },
        ).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        store.setMode(TravelMode.TRANSIT)
        runCurrent()
        val first = queries.last()
        assertEquals(0, first.timeMode)
        assertEquals(null, first.timeEpochSec)
        assertEquals(emptySet(), first.prefer)
        assertEquals(0, first.routePref)

        store.setTransitPreferFlags(bus = false, subway = false, train = true, tram = true)
        runCurrent()
        assertEquals(setOf(2, 3), queries.last().prefer)
        assertEquals(listOf("RAIL", "TRAM"), queries.last().modeNames())

        store.setTime(mode = 1, epochSec = 1_800_000_000L)
        runCurrent()
        assertEquals(1, queries.last().timeMode)
        assertEquals(1_800_000_000L, queries.last().timeEpochSec)

        store.setTransitRoutePreference(2)
        runCurrent()
        assertEquals(2, queries.last().routePref)
        // An unsupported preference never triggers a search.
        val before = queries.size
        store.setTransitRoutePreference(1)
        runCurrent()
        assertEquals(before, queries.size)

        // The chosen options survive a re-plan and are readable by Swift through the state.
        val s = store.state.value
        assertEquals(1, s.timeMode)
        assertEquals(1_800_000_000L, s.timeEpoch)
        assertEquals(true, s.prefersTrain)
        assertEquals(true, s.prefersTram)
        assertEquals(false, s.prefersBus)
        assertEquals(2, s.transitRoutePref)
        plans.last().complete(emptyList())
        runCurrent()
    }

    @Test fun stepsCarryRoadsLanesAndExits() {
        val m = Maneuver(
            ManeuverType.ROUNDABOUT, "At the roundabout, take the 2nd exit onto Main St", ME, 120.0, 20.0,
            road = "Main St", ref = "CA 1", laneHint = "Use the right lane",
            lanes = listOf(Lane(listOf("left"), false), Lane(listOf("straight", "right"), true)), roundaboutExit = 2,
        )
        val r = route(600.0).copy(legs = listOf(RouteLeg(2600.0, 600.0, null, listOf(m))))
        val step = RouteState(routes = listOf(r), active = r).steps().single()
        assertEquals(StepRow("ROUNDABOUT", m.instruction, 120.0, "Main St", "CA 1", "Use the right lane",
            listOf(LaneRow("left", false), LaneRow("straight,right", true)), 2), step)
    }

    @Test fun aPickedProvisionalAlternateIsNamedInPlace() = runTest {
        val src = FakeDirections()
        val store = RouteStore({ src }, backgroundScope).also { it.start() }
        store.onLocation(ME.lat, ME.lng)
        store.directionsTo(ferry)
        runCurrent()
        val a = route(600.0)
        val b = route(650.0, via = "Mission St").copy(provisional = true)
        val named = b.copy(provisional = false, summary = "Mission St named")
        src.naming = { if (it === b) named else it }
        src.answers[0].complete(listOf(a, b))
        runCurrent()
        store.select(1)
        runCurrent()
        val s = store.state.value
        assertSame(a, s.routes[0])
        assertSame(named, s.routes[1])
        assertSame(named, s.active)
    }
}
