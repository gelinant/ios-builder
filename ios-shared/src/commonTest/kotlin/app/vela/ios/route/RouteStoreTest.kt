package app.vela.ios.route

import app.vela.core.data.CalibrationNeededException
import app.vela.core.data.MapDataSource
import app.vela.core.data.RoutingPrefs
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TrafficSpan
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

private data class Ask(val origin: LatLng, val dest: LatLng, val mode: TravelMode, val avoidTolls: Boolean, val avoidHighways: Boolean)

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
        asks += Ask(origin, destination, mode, avoidTolls, avoidHighways)
        val answer = CompletableDeferred<List<Route>>()
        answers += answer
        return answer.await()
    }
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
        assertEquals("BICYCLE", kv.values["travel_mode"])
        assertEquals(true, kv.values["avoid_highways"])
        val next = RouteStore({ src }, backgroundScope, settings = { kv }).also { it.start() }
        assertEquals(TravelMode.BICYCLE, next.state.value.mode)
        assertTrue(next.state.value.avoidHighways)
        store.setAvoidHighways(false)
        assertFalse(RoutingPrefs.avoidHighways)
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
}
