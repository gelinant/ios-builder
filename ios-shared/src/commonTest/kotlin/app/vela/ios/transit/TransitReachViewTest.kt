package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * The half of T2-REACH the screen reads: the stop order, the four budgets and the explicit empty
 * answer. No network and no clock of its own.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TransitReachViewTest {
    private val nowMs = 1_800_000_000_000L

    private fun stop(name: String, minutes: Int, transfers: Int = 0) =
        TransitReachStop(name = name, stopId = name, lat = 37.79, lng = -122.40,
            minutes = minutes, transfers = transfers)

    @Test fun theScreenReadsStopsByTimeThenTransfersThenName() {
        val area = TransitReach.areaOf(
            originName = "Ferry Building", originLat = 37.7955, originLng = -122.3937,
            maxMinutes = 45,
            stops = listOf(
                stop("Slow", 20),
                stop("Fast with a change", 5, transfers = 1),
                stop("Fast direct", 5, transfers = 0),
                stop("Outside", 60),
            ),
            nowMillis = nowMs,
        )
        assertEquals(
            listOf("Fast direct", "Fast with a change", "Slow"),
            area.stopsByTime.map { it.name },
            "the list is not sorted by travel time",
        )
        assertEquals(3, area.stops.size, "the 60-minute stop is outside the 45-minute budget")
        assertFalse(area.isEmpty)
    }

    @Test fun theFourBudgetsAreTheOnesTheScreenOffers() {
        assertEquals(listOf(15, 30, 45, 60), TransitReach.MINUTE_OPTIONS)
        assertTrue(TransitReach.MINUTE_OPTIONS.all { it in Transitous.MIN_REACH_MIN..Transitous.MAX_REACH_MIN })
    }

    @Test fun aCleanEmptyReplyIsAnExplicitEmptyStateNotAFailure() = runTest {
        val empty = Transitous.OneToAllReply(
            result = Transitous.ReachResult(
                originName = "Ferry Building", originLat = 37.7955, originLon = -122.3937,
                stops = emptyList(),
            ),
        )
        val store = TransitReachStore(backgroundScope, { _, _, _ -> empty }, { nowMs })
        store.request(37.7955, -122.3937, 30)
        runCurrent()
        val state = store.state.value
        assertTrue(state.empty, "an empty feed answer is an empty state")
        assertEquals("", state.error ?: "", "an empty answer is not a network failure")
        assertEquals(0, state.hullCount)
        assertFalse(state.needsNetwork)
    }

    @Test fun anEmptyAreaHasNoHullAndNoCorners() {
        val area = TransitReach.areaOf(
            originName = "Ferry Building", originLat = 37.7955, originLng = -122.3937,
            maxMinutes = 30, stops = emptyList(), nowMillis = nowMs,
        )
        assertTrue(area.isEmpty)
        assertTrue(area.hull.isEmpty(), "a hull needs at least three stops")
        assertTrue(area.stopsByTime.isEmpty())
    }
}
