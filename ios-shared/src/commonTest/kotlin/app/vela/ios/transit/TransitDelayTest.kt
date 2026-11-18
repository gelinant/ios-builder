package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TransitDelayTest {
    private var nowMs = 1_800_000_000_000L

    private fun line(
        label: String = "9",
        mode: TransitMode = TransitMode.BUS,
        color: String? = null,
        delay: Int? = null,
        live: Boolean = true,
    ) = Transitous.MapTripLine(
        label = label, mode = mode, colorHex = color, destination = "Terminus",
        segmentCount = 2, delayMinutes = delay, live = live,
        paths = listOf(listOf(LatLng(37.79, -122.40), LatLng(37.80, -122.39))),
    )

    private fun reply(vararg lines: Transitous.MapTripLine) = Transitous.MapTripsReply(
        lines = lines.toList(), segmentCount = lines.sumOf { it.segmentCount },
    )

    @Test fun theThreeBandsAreTwoAndFiveMinutes() {
        assertEquals(TransitLiveLines.LEVEL_NONE, TransitLiveLines.delayLevel(null))
        assertEquals(TransitLiveLines.LEVEL_GREEN, TransitLiveLines.delayLevel(0))
        assertEquals(TransitLiveLines.LEVEL_GREEN, TransitLiveLines.delayLevel(1))
        assertEquals(TransitLiveLines.LEVEL_AMBER, TransitLiveLines.delayLevel(2))
        assertEquals(TransitLiveLines.LEVEL_AMBER, TransitLiveLines.delayLevel(5))
        assertEquals(TransitLiveLines.LEVEL_RED, TransitLiveLines.delayLevel(6))
        // An early run is judged on its distance from the timetable, not its sign.
        assertEquals(TransitLiveLines.LEVEL_RED, TransitLiveLines.delayLevel(-8))
        assertEquals(TransitLiveLines.LEVEL_GREEN, TransitLiveLines.delayLevel(-1))
    }

    @Test fun aLineWithoutFeedColorTakesItsModeColor() {
        val mapped = TransitLiveLines.line(line(mode = TransitMode.BUS))
        assertEquals("#0f6cbd", mapped.colorHex)
        assertNull(mapped.feedColorHex)
        assertEquals("BUS", mapped.mode)
        val tram = TransitLiveLines.line(line(mode = TransitMode.TRAM, color = "#73d700"))
        assertEquals("#73d700", tram.colorHex)
        assertEquals("#73d700", tram.feedColorHex)
    }

    @Test fun noScheduledPairMeansNoDelayColor() {
        val mapped = TransitLiveLines.line(line(delay = null))
        assertEquals(TransitLiveLines.LEVEL_NONE, mapped.delayLevel)
        assertNull(mapped.delayMinutes)
        val live = TransitLiveLines.line(line(delay = 4))
        assertEquals(TransitLiveLines.LEVEL_AMBER, live.delayLevel)
        assertEquals(4, live.delayMinutes)
    }

    @Test fun onlyTheFeedsRealtimeFlagMarksALineLive() {
        assertTrue(TransitLiveLines.line(line(live = true)).live)
        assertTrue(!TransitLiveLines.line(line(live = false)).live)
    }

    @Test fun theStateCountsColorsLiveAndBands() {
        val state = TransitLiveLinesState(
            lines = listOf(
                TransitLiveLines.line(line(label = "1", delay = 1, live = true)),
                TransitLiveLines.line(line(label = "2", color = "#ff0000", delay = 4, live = false)),
                TransitLiveLines.line(line(label = "3", delay = 9, live = true)),
                TransitLiveLines.line(line(label = "4", delay = null, live = false)),
            ),
        )
        assertEquals(4, state.lineCount)
        assertEquals(2, state.liveCount)
        assertEquals(1, state.coloredCount)
        assertEquals(3, state.delayedCount)
        assertEquals(1, state.greenCount)
        assertEquals(1, state.amberCount)
        assertEquals(1, state.redCount)
    }

    @Test fun theStoreAsksOncePerViewportAndCachesTwoMinutes() = runTest {
        var calls = 0
        val store = TransitLiveLinesStore(
            backgroundScope,
            { _, _, _, _, _, _, _ -> calls += 1; reply(line()) },
            { nowMs },
        )
        store.request(37.79, -122.41, 37.81, -122.39, 15, 1_800_000_000L, 1_800_000_600L)
        runCurrent()
        assertEquals(1, calls)
        assertEquals(1, store.state.value.lineCount)
        store.request(37.79, -122.41, 37.81, -122.39, 15, 1_800_000_000L, 1_800_000_600L)
        runCurrent()
        assertEquals(1, calls, "the same box inside two minutes is the same answer")
        store.request(37.79, -122.41, 37.81, -122.39, 16, 1_800_000_000L, 1_800_000_600L)
        runCurrent()
        assertEquals(2, calls, "another zoom is another action")
    }

    @Test fun theWindowIsCappedAtTenMinutes() = runTest {
        var askedEnd = 0L
        val store = TransitLiveLinesStore(
            backgroundScope,
            { _, _, _, _, _, start, end -> askedEnd = end; reply(line()) },
            { nowMs },
        )
        store.request(37.79, -122.41, 37.81, -122.39, 15, 1_800_000_000L, 1_800_090_000L)
        runCurrent()
        assertEquals(1_800_000_600L, askedEnd)
    }

    @Test fun aRateLimitIsNamedAndKeepsTheLastLines() = runTest {
        val answers = ArrayDeque(listOf(reply(line()), Transitous.MapTripsReply(rateLimited = true)))
        val store = TransitLiveLinesStore(
            backgroundScope,
            { _, _, _, _, _, _, _ -> answers.removeFirst() },
            { nowMs },
        )
        store.request(37.79, -122.41, 37.81, -122.39, 15, 1_800_000_000L, 1_800_000_600L)
        runCurrent()
        store.request(37.79, -122.41, 37.81, -122.39, 16, 1_800_000_000L, 1_800_000_600L)
        runCurrent()
        assertEquals("rate_limited", store.state.value.error)
        assertEquals(1, store.state.value.lineCount, "the last lines stay on screen")
    }
}
