package app.vela.ios.nav

import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.nav.NavSession
import app.vela.core.nav.NavState
import app.vela.core.platform.Clock
import app.vela.ios.search.FakeHttp
import app.vela.ios.search.ok
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

private class AlertClock(var now: Long = 0L) : Clock {
    override fun nowMillis() = now
    override fun elapsedRealtimeMillis() = now
    override fun monotonicNanos() = now * 1_000_000L
}

@OptIn(ExperimentalCoroutinesApi::class)
class NavAlertsTest {
    private val start = LatLng(37.7749, -122.4194)
    private val middle = LatLng(37.7857, -122.4054)
    private val end = LatLng(37.7942, -122.3946)

    @Test fun overpassLoadsDedupesAndProjectsRouteData() = runTest {
        val http = FakeHttp { request ->
            when {
                "speed_camera" in request.url -> ok("""{"elements":[{"lat":37.7857,"lon":-122.4054},{"lat":37.7857,"lon":-122.4054}]}""", request.url)
                "surveillance" in request.url -> ok("""{"elements":[{"lat":37.7857,"lon":-122.4054,"tags":{}},{"lat":37.7857,"lon":-122.4054,"tags":{}},{"lat":37.7858,"lon":-122.4054,"tags":{}}]}""", request.url)
                else -> ok("""{"elements":[{"tags":{"maxspeed":"30 mph"},"geometry":[{"lat":37.7749,"lon":-122.4194},{"lat":37.7857,"lon":-122.4054},{"lat":37.7942,"lon":-122.3946}]}]}""", request.url)
            }
        }
        val data = OverpassNavAlertProvider(http, nowMillis = { 0L }).load(route())

        assertEquals(3, http.requests.size)
        assertEquals(2, data.cameraGroups.size)
        val speed = data.cameraGroups.single { it.kind == NavRoadAlertKind.SPEED_CAMERA }
        val alpr = data.cameraGroups.single { it.kind == NavRoadAlertKind.ALPR_CAMERA }
        assertEquals(1, speed.count)
        assertEquals(2, alpr.count, "exact duplicates collapse before nearby cameras join one group")
        assertEquals(48.28032, assertNotNull(data.speedLimitAt(0.0)), 0.0001)
        assertEquals(48.28032, assertNotNull(data.speedLimitAt(1_000.0)), 0.0001)
    }

    @Test fun routeLoadsOnceAndCameraAlertIsNotRepeated() = runTest {
        var loads = 0
        val provider = object : NavAlertProvider {
            override suspend fun load(route: Route): NavRouteData {
                loads++
                return NavRouteData(cameraGroups = listOf(NavCameraGroup(NavRoadAlertKind.SPEED_CAMERA, 150.0, 1)))
            }
        }
        val audible = mutableListOf<NavRoadAlert>()
        var road = NavAlertState()
        val alerts = NavAlerts(provider, backgroundScope, AlertClock(), { false }, { audible += it }, { road = it })
        val route = route()
        alerts.onRoute(route)
        runCurrent()
        assertEquals(1, loads)

        val session = session(route, 0.0)
        alerts.update(session, 12.0)
        alerts.update(session, 12.0)
        alerts.onRoute(route)
        runCurrent()
        assertEquals(1, audible.size)
        assertEquals(NavRoadAlertKind.SPEED_CAMERA, audible.single().kind)
        assertEquals(1, loads)
        assertEquals(1, road.loadedCameraGroups)

        advanceTimeBy(6_000L)
        runCurrent()
        assertNull(road.alert)
    }

    @Test fun speedBadgeThresholdsAndSpokenHoldMatchAndroid() = runTest {
        assertFalse(NavSpeedDisplay.isSpeeding(15.0, 50.0, imperial = false))
        assertTrue(NavSpeedDisplay.isSpeeding(15.3, 50.0, imperial = false))
        assertFalse(NavSpeedDisplay.isSpeeding(14.7, 48.28032, imperial = true))
        assertTrue(NavSpeedDisplay.isSpeeding(15.0, 48.28032, imperial = true))

        val clock = AlertClock()
        val audible = mutableListOf<NavRoadAlert>()
        var road = NavAlertState()
        val route = route()
        val provider = object : NavAlertProvider {
            override suspend fun load(route: Route) = NavRouteData(
                speedLimits = listOf(NavSpeedLimitSpan(0.0, route.distanceMeters, 50.0)),
            )
        }
        val alerts = NavAlerts(provider, backgroundScope, clock, { false }, { audible += it }, { road = it })
        alerts.onRoute(route)
        runCurrent()
        for (second in 0L..4L) {
            clock.now = second * 1_000L
            alerts.update(session(route, 0.0), 20.0)
            if (second == 0L) assertTrue(road.speeding)
            if (second < 4L) assertTrue(audible.isEmpty())
        }
        assertEquals(listOf(NavRoadAlertKind.SPEEDING), audible.map { it.kind })
        assertNotNull(road.alert)
    }

    @Test fun bridgeOnTheRouteIsAnnouncedOnce() = runTest {
        val now = 1_700_000_000_000L
        val clock = AlertClock(now)
        val route = route()
        val open = app.vela.core.data.BridgeOpening(middle, now, null, openNow = true)
        val provider = object : NavAlertProvider {
            override suspend fun load(route: Route) = NavRouteData(
                bridges = listOf(app.vela.core.data.BridgeAlerts.OnRoute(1_200.0, listOf(open))),
            )
        }
        val audible = mutableListOf<NavRoadAlert>()
        var road = NavAlertState()
        val alerts = NavAlerts(provider, backgroundScope, clock, { false }, { audible += it }, { road = it })
        alerts.onRoute(route)
        runCurrent()
        assertEquals(1, road.loadedBridges)

        val traveled = 800.0
        alerts.update(session(route, traveled), 12.0)
        assertEquals(listOf(NavRoadAlertKind.BRIDGE_OPEN), audible.map { it.kind })
        alerts.update(session(route, traveled), 12.0)
        assertEquals(1, audible.size, "a bridge is announced once per route")
    }

    private fun session(route: Route, traveled: Double) = NavSession.State(
        navigating = true,
        route = route,
        nav = NavState(traveledM = traveled),
    )

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
