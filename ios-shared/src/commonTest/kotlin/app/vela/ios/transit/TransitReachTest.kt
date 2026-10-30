package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.model.LatLng
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TransitReachTest {
    private var nowMs = 1_800_000_000_000L

    private fun stop(name: String, lat: Double, lng: Double, minutes: Int) =
        Transitous.ReachableStop(name = name, stopId = name, lat = lat, lon = lng, minutes = minutes, transfers = 1)

    private fun reply(vararg stops: Transitous.ReachableStop) = Transitous.OneToAllReply(
        result = Transitous.ReachResult(
            originName = "Ferry Building", originLat = 37.7955, originLon = -122.3937,
            stops = stops.toList(),
        ),
    )

    private val square = reply(
        stop("a", 37.79, -122.40, 5),
        stop("b", 37.79, -122.39, 8),
        stop("c", 37.80, -122.39, 10),
        stop("d", 37.80, -122.40, 12),
        stop("far", 37.90, -122.30, 45),
    )

    @Test fun theHullIsTheOutlineOfTheDots() {
        val hull = TransitReach.hullOf(
            listOf(
                LatLng(0.0, 0.0), LatLng(0.0, 2.0), LatLng(2.0, 0.0),
                LatLng(2.0, 2.0), LatLng(1.0, 1.0),
            ),
        )
        assertEquals(4, hull.size, "the interior dot is not a corner")
        assertEquals(setOf(0.0, 2.0), hull.map { it.lat }.toSet())
        // A line is not a polygon, and two points are not either.
        assertEquals(emptyList(), TransitReach.hullOf(listOf(LatLng(0.0, 0.0), LatLng(0.0, 1.0), LatLng(0.0, 2.0))))
        assertEquals(emptyList(), TransitReach.hullOf(listOf(LatLng(0.0, 0.0))))
    }

    @Test fun theAreaKeepsOnlyStopsInsideTheBudget() {
        val area = TransitReach.area(square.result!!, maxMinutes = 20, nowMillis = nowMs)
        assertEquals(4, area.stops.size, "the 45-minute stop is outside the 20-minute budget")
        assertTrue(area.stops.none { it.minutes > 20 })
        assertEquals(4, area.hull.size)
        assertEquals(-122, area.originLng.toInt())
        assertTrue(!area.rateLimited)
    }

    @Test fun oneRequestPerActionAndAFiveMinuteCache() = runTest {
        var calls = 0
        val store = TransitReachStore(backgroundScope, { _, _, _ -> calls += 1; square }, { nowMs })
        store.request(37.7955, -122.3937, 20)
        runCurrent()
        assertEquals(1, calls)
        assertEquals(4, store.state.value.area?.stops?.size)

        // The same point and budget inside five minutes is the same answer.
        store.request(37.7955, -122.3937, 20)
        runCurrent()
        assertEquals(1, calls)
        // Another budget is another user action and one more request.
        store.request(37.7955, -122.3937, 40)
        runCurrent()
        assertEquals(2, calls)
        assertEquals(4, store.state.value.area?.stops?.size)
    }

    @Test fun theBudgetIsClampedAndTheStateSaysWhyAMissIsEmpty() = runTest {
        var asked = -1
        val store = TransitReachStore(backgroundScope, { _, _, minutes -> asked = minutes; reply() }, { nowMs })
        store.request(37.7955, -122.3937, 120)
        runCurrent()
        assertEquals(60, asked)
        // A clean reply with no stop is an empty area, not an invented one.
        assertEquals(0, store.state.value.area?.stops?.size)
        assertEquals(0, store.state.value.hullCount)
    }

    @Test fun aRateLimitKeepsTheLastAreaAndStopsAsking() = runTest {
        val answers = ArrayDeque(listOf(square, Transitous.OneToAllReply(rateLimited = true)))
        val budget = TransitRequestBudget(nowMillis = { nowMs })
        val store = TransitReachStore(backgroundScope, { _, _, _ -> answers.removeFirst() }, { nowMs }, budget = budget)
        store.request(37.7955, -122.3937, 20)
        runCurrent()
        store.request(37.7956, -122.3938, 20)
        runCurrent()
        assertEquals("rate_limited", store.state.value.error)
        assertEquals(4, store.state.value.area?.stops?.size, "the last area stays on screen")
        assertTrue(store.state.value.rateLimited)
        // Every store sharing the budget stops until its back-off.
        assertTrue(!budget.take())
    }

    @Test fun theDailyBudgetStopsBeforeTheServiceDoes() = runTest {
        val budget = TransitRequestBudget(limit = 2, nowMillis = { nowMs })
        var calls = 0
        val store = TransitReachStore(backgroundScope, { _, _, _ -> calls += 1; square }, { nowMs }, budget = budget)
        store.request(1.0, 1.0, 10)
        runCurrent()
        store.request(2.0, 2.0, 10)
        runCurrent()
        store.request(3.0, 3.0, 10)
        runCurrent()
        assertEquals(2, calls)
        assertEquals("budget_exhausted", store.state.value.error)
        assertEquals(2, budget.used())
        assertEquals(0, budget.remaining())
        // After the 24 h window the counter is empty again.
        nowMs += 25L * 60L * 60L * 1000L
        assertEquals(0, budget.used())
        assertTrue(budget.take())
        assertEquals(1, budget.used())
    }

    @Test fun closingDropsTheAreaAndCancelsTheRequest() = runTest {
        val store = TransitReachStore(backgroundScope, { _, _, _ -> square }, { nowMs })
        store.request(37.7955, -122.3937, 20)
        runCurrent()
        store.clear()
        assertNull(store.state.value.area)
        assertEquals(0, store.state.value.stopCount)
    }
}
