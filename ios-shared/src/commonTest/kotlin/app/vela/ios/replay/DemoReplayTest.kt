package app.vela.ios.replay

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The demo replay timeline: interpolation, speedup, heading and both ends. */
class DemoReplayTest {

    // Davis, California: points about 50 m apart, one fix per second.
    private fun trace(count: Int = 11): List<TripPoint> = List(count) { i ->
        TripPoint(
            lat = 38.5449 + i * 0.00045,
            lng = -121.7405,
            tMs = i * 1_000L,
            speedMps = 10.0 + i,
            distanceM = i * 50.0,
        )
    }

    @Test
    fun aTracePlaysFromBothEndsAndInterpolates() {
        val replay = DemoReplay(trace(), speedup = 1.0)
        assertEquals(10_000L, replay.durationMs)

        val first = replay.sampleAt(0L)
        assertEquals(38.5449, first!!.latitude, 1e-9)
        assertEquals(0.0, first.bearingDeg, 1e-6, "the Davis fixture runs north")
        assertEquals(0.0, first.distanceM, 1e-9)
        assertTrue(!first.finished)

        val half = replay.sampleAt(5_000L)!!
        assertEquals(38.5449 + 5 * 0.00045, half.latitude, 1e-9)
        assertEquals(15.0, half.speedMps, 1e-9)
        assertEquals(250.0, half.distanceM, 1e-9)
        assertEquals(5_000L, half.traceMs)

        val last = replay.sampleAt(10_000L)!!
        assertEquals(38.5449 + 10 * 0.00045, last.latitude, 1e-9)
        assertEquals(10_000L, last.traceMs)
        assertTrue(last.finished)
    }

    @Test
    fun playheadIsClampedAndSpeedupScalesTheWholeTimeline() {
        val replay = DemoReplay(trace(), speedup = 2.0)
        assertEquals(5_000L, replay.durationMs)
        // Two replay seconds are four recorded seconds.
        val scaled = replay.sampleAt(2_000L)!!
        assertEquals(4_000L, scaled.traceMs)
        assertEquals(38.5449 + 4 * 0.00045, scaled.latitude, 1e-9)

        assertTrue(replay.sampleAt(9_999L)!!.finished)
        assertEquals(replay.sampleAt(5_000L)!!.latitude, replay.sampleAt(60_000L)!!.latitude, 1e-9)
        assertEquals(0L, replay.sampleAt(-5_000L)!!.traceMs)
    }

    @Test
    fun headingFollowsTheSegmentAndEmptyTracesReturnNothing() {
        val east = List(4) { i ->
            TripPoint(38.5449, -121.7405 + i * 0.0005, i * 1_000L, 9.0, i * 40.0)
        }
        val bearing = DemoReplay(east, speedup = 1.0).sampleAt(1_500L)!!.bearingDeg
        assertTrue(abs(bearing - 90.0) < 2.0, "an eastward trace heads east, got $bearing")

        assertNull(DemoReplay(emptyList()).sampleAt(0L))
        val one = DemoReplay(listOf(TripPoint(38.5, -121.7, 0L, 0.0, 0.0)), speedup = 4.0)
        val sample = one.sampleAt(0L)!!
        assertEquals(38.5, sample.latitude, 1e-9)
        assertEquals(0L, one.durationMs)
        assertTrue(sample.finished)
    }

    @Test
    fun aZeroOrInvalidSpeedupStillPlaysRealTime() {
        assertEquals(10_000L, DemoReplay(trace(), speedup = 0.0).durationMs)
        assertEquals(10_000L, DemoReplay(trace(), speedup = Double.NaN).durationMs)
    }
}
