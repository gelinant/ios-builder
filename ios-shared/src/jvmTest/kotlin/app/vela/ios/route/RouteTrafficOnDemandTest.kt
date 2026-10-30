package app.vela.ios.route

import app.vela.core.data.MapDataSource
import app.vela.core.data.NoGoogle
import app.vela.core.data.RoutingPrefs
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** A source that records each directions ask and waits for the test's answer. */
private class RecordingDirections : MapDataSource {
    data class Ask(val mode: TravelMode)

    val asks = mutableListOf<Ask>()
    val answers = mutableListOf<CompletableDeferred<List<Route>>>()

    override suspend fun search(
        query: String, near: LatLng?, spanMeters: Double?, rankFrom: LatLng?, lang: String?,
    ): SearchResult = error("unused")

    override suspend fun placeDetails(id: String): Place = error("unused")

    override suspend fun directions(
        origin: LatLng, destination: LatLng, mode: TravelMode, waypoints: List<LatLng>,
        avoidTolls: Boolean, avoidHighways: Boolean, avoidFerries: Boolean, urgent: Boolean,
        departBearingDeg: Double?, budgetMs: Long?,
    ): List<Route> {
        asks += Ask(mode)
        val answer = CompletableDeferred<List<Route>>()
        answers += answer
        return answer.await()
    }

    override suspend fun nameRoute(
        route: Route, origin: LatLng, destination: LatLng, mode: TravelMode, avoidTolls: Boolean,
        avoidHighways: Boolean, avoidFerries: Boolean,
    ): Route = route
}

private val home = LatLng(37.7749, -122.4194)
private val ferry = Place(
    id = "ferry", name = "Ferry Building", location = LatLng(37.7942, -122.3946))

private fun driveRoute(
    seconds: Double, traffic: Double? = null, typical: Pair<Double, Double>? = null,
): Route = Route(
    polyline = listOf(home, ferry.location),
    legs = emptyList(),
    distanceMeters = 2_600.0,
    durationSeconds = seconds,
    durationInTrafficSeconds = traffic,
    typicalLowSeconds = typical?.first,
    typicalHighSeconds = typical?.second,
)

/**
 * L117: a drive plans on the open router until "Show traffic" is tapped, the tap opens only the
 * traffic gate (never Google off), and a new trip closes it again. Google's answer stays the only
 * source of a live ETA; a typical range is exposed as such.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RouteTrafficOnDemandTest {
    @Test fun aDriveWaitsForTheTapAndThenAsksGoogle() = runTest {
        val old = RoutingPrefs.googleTraffic
        try {
            val src = RecordingDirections()
            val store = RouteStore({ src }, backgroundScope).also { it.start() }
            store.onLocation(home.lat, home.lng)
            store.directionsTo(ferry)
            runCurrent()
            val first = store.state.value
            assertTrue(first.trafficOnTap, "iOS defaults to traffic on demand")
            assertTrue(first.canShowTraffic, "the compact picker must offer Show traffic")
            assertFalse(first.trafficRequested)
            assertFalse(RoutingPrefs.googleTraffic, "the first drive asked Google before the tap")
            assertEquals(TravelMode.DRIVE, src.asks.first().mode)

            val before = src.asks.size
            store.requestTraffic()
            runCurrent()
            val after = store.state.value
            assertTrue(after.trafficRequested)
            assertTrue(RoutingPrefs.googleTraffic, "the tap did not open the gate")
            assertTrue(src.asks.size > before)
            assertEquals(TravelMode.DRIVE, src.asks.last().mode)
            assertFalse(after.canShowTraffic, "the offer stays after the tap")

            src.answers.last().complete(listOf(driveRoute(600.0, traffic = 720.0)))
            runCurrent()
            val row = store.state.value.rows().single()
            assertEquals(720.0, row.seconds)
            assertTrue(row.hasTraffic)
        } finally {
            RoutingPrefs.googleTraffic = old
        }
    }

    @Test fun aNewTripClosesTheGateAgain() = runTest {
        val old = RoutingPrefs.googleTraffic
        try {
            val src = RecordingDirections()
            val store = RouteStore({ src }, backgroundScope).also { it.start() }
            store.onLocation(home.lat, home.lng)
            store.directionsTo(ferry)
            runCurrent()
            store.requestTraffic()
            runCurrent()
            assertTrue(store.state.value.trafficRequested)

            store.directionsTo(ferry)
            runCurrent()
            assertFalse(store.state.value.trafficRequested)
            assertFalse(RoutingPrefs.googleTraffic)
        } finally {
            RoutingPrefs.googleTraffic = old
        }
    }

    @Test fun googleOffNeverRequestsTraffic() = runTest {
        val oldGoogle = NoGoogle.enabled
        val oldTraffic = RoutingPrefs.googleTraffic
        NoGoogle.enabled = true
        try {
            val src = RecordingDirections()
            val store = RouteStore({ src }, backgroundScope).also { it.start() }
            store.onLocation(home.lat, home.lng)
            store.directionsTo(ferry)
            runCurrent()
            assertTrue(store.state.value.googleOff)
            assertFalse(store.state.value.canShowTraffic, "a NoGoogle trip shows no traffic offer")
            val before = src.asks.size
            store.requestTraffic()
            runCurrent()
            assertFalse(store.state.value.trafficRequested)
            assertEquals(before, src.asks.size, "the tap asked a source with Google off")
            assertFalse(RoutingPrefs.googleTraffic)
        } finally {
            NoGoogle.enabled = oldGoogle
            RoutingPrefs.googleTraffic = oldTraffic
        }
    }

    @Test fun withOnDemandOffTheDriveKeepsGoogleTraffic() = runTest {
        val old = RoutingPrefs.googleTraffic
        try {
            val src = RecordingDirections()
            val store = RouteStore(
                { src }, backgroundScope, trafficOnTapDefault = false,
            ).also { it.start() }
            store.onLocation(home.lat, home.lng)
            store.directionsTo(ferry)
            runCurrent()
            assertFalse(store.state.value.trafficOnTap)
            assertTrue(RoutingPrefs.googleTraffic)
            val before = src.asks.size
            store.requestTraffic()
            runCurrent()
            assertFalse(store.state.value.trafficRequested)
            assertEquals(before, src.asks.size)
        } finally {
            RoutingPrefs.googleTraffic = old
        }
    }

    @Test fun aTypicalRangeIsNotLiveTraffic() {
        val route = driveRoute(600.0, typical = 540.0 to 780.0)
        val row = RouteState(routes = listOf(route), active = route).rows().single()
        assertFalse(row.hasTraffic)
        assertEquals(540.0, row.typicalLowSeconds)
        assertEquals(780.0, row.typicalHighSeconds)
    }

    @Test fun closingTheChooserLeavesNavigationItsOwnRechecks() = runTest {
        val old = RoutingPrefs.googleTraffic
        try {
            val src = RecordingDirections()
            val store = RouteStore({ src }, backgroundScope).also { it.start() }
            store.onLocation(home.lat, home.lng)
            store.directionsTo(ferry)
            runCurrent()
            assertFalse(RoutingPrefs.googleTraffic)
            store.close()
            assertTrue(RoutingPrefs.googleTraffic)
            store.directionsTo(ferry)
            runCurrent()
            store.prepareNavigation()
            assertTrue(RoutingPrefs.googleTraffic)
        } finally {
            RoutingPrefs.googleTraffic = old
        }
    }
}
