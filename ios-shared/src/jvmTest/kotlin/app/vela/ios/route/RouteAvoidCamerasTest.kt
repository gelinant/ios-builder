package app.vela.ios.route

import app.vela.core.data.AlprCamera
import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.core.platform.KeyValueEditor
import app.vela.core.platform.KeyValueStore
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private data class CameraAsk(val mode: TravelMode, val waypoints: List<LatLng>)

/** A source that answers every directions ask at once, so the camera pass can run to the end. */
private class CameraDirections(private val answer: (CameraAsk) -> List<Route>) : MapDataSource {
    val asks = mutableListOf<CameraAsk>()

    override suspend fun search(
        query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?,
    ): SearchResult = error("unused")

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>,
        avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean,
        departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> {
        val ask = CameraAsk(mode, waypoints)
        asks += ask
        return answer(ask)
    }

    override suspend fun nameRoute(
        route: Route, origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean,
    ): Route = route
}

private class CameraKv : KeyValueStore {
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
private val MID = LatLng(37.7857, -122.4054)
private val FERRY = LatLng(37.7942, -122.3946)
private val ferryBuilding = Place(id = "ferry", name = "Ferry Building", location = FERRY)

private fun baseRoute(seconds: Double = 600.0, meters: Double = 2_600.0): Route = Route(
    polyline = listOf(ME, MID, FERRY),
    legs = emptyList(),
    distanceMeters = meters,
    durationSeconds = seconds,
    durationInTrafficSeconds = null,
)

/** An alternate that shares both ends but leaves the base road in the middle. */
private fun alternateRoute(seconds: Double = 660.0, meters: Double = 2_800.0): Route = Route(
    polyline = listOf(ME, LatLng(37.7850, -122.4100), LatLng(37.7900, -122.4000), FERRY),
    legs = emptyList(),
    distanceMeters = meters,
    durationSeconds = seconds,
    durationInTrafficSeconds = null,
)

/** The same road, re-snapped two meters over: a router that answered a detour with the old road. */
private fun resnapped(route: Route): Route = route.copy(
    polyline = route.polyline.map { LatLng(it.lat + 0.00002, it.lng + 0.00002) })

/** A side street 150 m over for the middle of the trip. */
private fun sideStreet(seconds: Double = 640.0, meters: Double = 2_900.0): Route = Route(
    polyline = listOf(ME, LatLng(MID.lat, MID.lng + 150.0 / (111_320.0 * 0.78)), FERRY),
    legs = emptyList(),
    distanceMeters = meters,
    durationSeconds = seconds,
    durationInTrafficSeconds = null,
)

private val cameraA = AlprCamera(LatLng(37.7800, -122.4129))
private val cameraB = AlprCamera(LatLng(37.7830, -122.4092))

/** The two cameras sit on the base road; only a line that is that road passes them. */
private suspend fun cameraSource(polyline: List<LatLng>): List<AlprCamera> =
    if (app.vela.core.nav.CameraDetour.sameRoute(baseRoute().polyline, polyline)) {
        listOf(cameraA, cameraB)
    } else {
        emptyList()
    }

@OptIn(ExperimentalCoroutinesApi::class)
class RouteAvoidCamerasTest {
    @Test fun theStoredPreferenceCountsCamerasBeforeTheFirstRouteIsShown() = runTest {
        val kv = CameraKv().apply { values[RouteStore.KEY_AVOID_CAMERAS] = true }
        val src = CameraDirections { listOf(baseRoute()) }
        var calls = 0
        val s = RouteStore({ src }, backgroundScope, settings = { kv },
            camerasAlong = { calls++; cameraSource(it) }, online = { true })
        s.start()
        assertTrue(s.state.value.avoidCameras, "the stored preference was not applied at start")
        assertTrue(s.state.value.canAvoidCameras)
        s.onLocation(ME.lat, ME.lng)
        s.directionsTo(ferryBuilding)
        runCurrent()
        assertEquals(1, calls, "the first route was shown without counting its cameras")
        assertEquals(listOf(2), s.state.value.cameraCounts)
        assertEquals(2, s.state.value.rows().single().cameras)
        assertEquals(0, s.state.value.camerasAvoided, "a single route avoids nothing")
    }

    @Test fun aLighterAlternateInsideTheCapLeadsAndReportsWhatItAvoids() = runTest {
        val kv = CameraKv().apply { values[RouteStore.KEY_AVOID_CAMERAS] = true }
        val fast = baseRoute()
        val alt = alternateRoute()
        val src = CameraDirections { listOf(fast, alt) }
        val s = RouteStore({ src }, backgroundScope, settings = { kv },
            camerasAlong = { cameraSource(it) }, online = { true })
        s.start()
        s.onLocation(ME.lat, ME.lng)
        s.directionsTo(ferryBuilding)
        runCurrent()
        val state = s.state.value
        assertTrue(state.routes.first() === alt, "the camera-lighter alternate did not lead")
        assertTrue(state.active === alt)
        assertEquals(listOf(0, 2), state.cameraCounts, "counts stay aligned with the reordered routes")
        assertEquals(2, state.camerasAvoided)
        assertEquals(60.0, state.cameraDetourSeconds, 0.1)
        assertEquals(200.0, state.cameraDetourMeters, 0.1)
        assertTrue(state.cameraBaselineIsFastest)
    }

    @Test fun anAlternateOverTheCapKeepsTheFastestAndClaimsNothing() = runTest {
        val kv = CameraKv().apply { values[RouteStore.KEY_AVOID_CAMERAS] = true }
        val fast = baseRoute()
        val slow = alternateRoute(seconds = 900.0)
        val src = CameraDirections { listOf(fast, slow) }
        val s = RouteStore({ src }, backgroundScope, settings = { kv },
            camerasAlong = { cameraSource(it) }, online = { true })
        s.start()
        s.onLocation(ME.lat, ME.lng)
        s.directionsTo(ferryBuilding)
        runCurrent()
        val state = s.state.value
        assertTrue(state.routes.first() === fast)
        assertEquals(listOf(2, 0), state.cameraCounts, "the counts are still shown beside the choice")
        assertEquals(0, state.camerasAvoided)
        assertEquals(0.0, state.cameraDetourSeconds)
    }

    @Test fun theSideStreetPassKeepsARouteThatDropsTheCameras() = runTest {
        val kv = CameraKv().apply {
            values[RouteStore.KEY_AVOID_CAMERAS] = true
            values[RouteStore.KEY_CAMERA_SIDE_STREETS] = true
        }
        val detour = sideStreet()
        val src = CameraDirections { ask ->
            if (ask.mode == TravelMode.DRIVE && ask.waypoints.isNotEmpty()) listOf(detour)
            else listOf(baseRoute())
        }
        val s = RouteStore({ src }, backgroundScope, settings = { kv },
            camerasAlong = { cameraSource(it) }, online = { true })
        s.start()
        s.onLocation(ME.lat, ME.lng)
        s.directionsTo(ferryBuilding)
        runCurrent()
        val state = s.state.value
        assertEquals(2, state.routes.size, "the detour did not join the list")
        assertFalse(state.routes.first() === state.routes.last(), "the detour did not lead")
        assertEquals(0, state.cameraCounts.first(), "the leading route still passes the cameras")
        assertTrue(state.routes.first().detourPlan.isNotEmpty(), "the detour plan was lost")
        assertEquals(2, state.camerasAvoided)
        assertEquals(40.0, state.cameraDetourSeconds, 0.1)
        assertTrue(state.cameraDetourMeters > 0.0)
    }

    @Test fun aRouterThatReturnsTheSameRoadIsNeverAnAvoidance() = runTest {
        val kv = CameraKv().apply {
            values[RouteStore.KEY_AVOID_CAMERAS] = true
            values[RouteStore.KEY_CAMERA_SIDE_STREETS] = true
        }
        val sameRoad = resnapped(baseRoute())
        val src = CameraDirections { ask ->
            if (ask.mode == TravelMode.DRIVE && ask.waypoints.isNotEmpty()) listOf(sameRoad)
            else listOf(baseRoute())
        }
        val s = RouteStore({ src }, backgroundScope, settings = { kv },
            camerasAlong = { cameraSource(it) }, online = { true })
        s.start()
        s.onLocation(ME.lat, ME.lng)
        s.directionsTo(ferryBuilding)
        runCurrent()
        val state = s.state.value
        assertEquals(1, state.routes.size, "the same road was kept as a detour")
        assertEquals(0, state.camerasAvoided, "the picker claimed an avoidance the router did not make")
        assertEquals(0.0, state.cameraDetourSeconds)
    }

    @Test fun googleOffStillCountsCamerasFromTheVelaLayer() = runTest {
        val old = NoGoogle.enabled
        NoGoogle.enabled = true
        try {
            val kv = CameraKv().apply { values[RouteStore.KEY_AVOID_CAMERAS] = true }
            val src = CameraDirections { listOf(baseRoute()) }
            val s = RouteStore({ src }, backgroundScope, settings = { kv },
                camerasAlong = { cameraSource(it) }, online = { true })
            s.start()
            s.onLocation(ME.lat, ME.lng)
            s.directionsTo(ferryBuilding)
            runCurrent()
            assertTrue(s.state.value.googleOff)
            assertTrue(s.state.value.canAvoidCameras, "the camera layer was lost with Google off")
            assertEquals(listOf(2), s.state.value.cameraCounts)
        } finally {
            NoGoogle.enabled = old
        }
    }

    @Test fun offlineHidesTheCameraChoiceAndNeverCounts() = runTest {
        val kv = CameraKv().apply { values[RouteStore.KEY_AVOID_CAMERAS] = true }
        var calls = 0
        val src = CameraDirections { listOf(baseRoute()) }
        val s = RouteStore({ src }, backgroundScope, settings = { kv },
            camerasAlong = { calls++; cameraSource(it) }, online = { false })
        s.start()
        assertFalse(s.state.value.canAvoidCameras, "an offline build offered a detour it cannot plan")
        s.onLocation(ME.lat, ME.lng)
        s.directionsTo(ferryBuilding)
        runCurrent()
        assertEquals(0, calls)
        assertTrue(s.state.value.cameraCounts.isEmpty())
        assertEquals(0, s.state.value.camerasAvoided)
    }

    @Test fun bothCameraSwitchesPersistUnderAndroidsKeys() = runTest {
        val kv = CameraKv()
        val first = RouteStore({ CameraDirections { listOf(baseRoute()) } }, backgroundScope,
            settings = { kv }, camerasAlong = { cameraSource(it) })
        first.start()
        first.setAvoidCameras(true)
        first.setCameraSideStreets(true)
        assertEquals(true, kv.values[RouteStore.KEY_AVOID_CAMERAS])
        assertEquals(true, kv.values[RouteStore.KEY_CAMERA_SIDE_STREETS])
        val second = RouteStore({ CameraDirections { listOf(baseRoute()) } }, backgroundScope,
            settings = { kv }, camerasAlong = { cameraSource(it) })
        second.start()
        assertTrue(second.state.value.avoidCameras)
        assertTrue(second.state.value.cameraSideStreets)
    }
}
