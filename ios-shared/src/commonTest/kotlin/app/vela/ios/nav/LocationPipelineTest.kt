package app.vela.ios.nav

import app.vela.core.platform.Clock
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private class PipelineClock : Clock {
    var now = 0L
    override fun nowMillis() = now
    override fun elapsedRealtimeMillis() = now
    override fun monotonicNanos() = now * 1_000_000
}

@OptIn(ExperimentalCoroutinesApi::class)
class LocationPipelineTest {
    @Test fun monotonicOrderAndTheGuidanceAccuracyGate() = runTest {
        val clock = PipelineClock()
        val guided = mutableListOf<GuidanceFix>()
        val pipeline = LocationPipeline(backgroundScope, clock, onGuidance = { guided += it })
        pipeline.navigationStarted()
        pipeline.onFix(fix(accuracy = 80.0, nanos = 1_000_000_000))
        assertTrue(guided.isEmpty())
        assertEquals(80.0, pipeline.state.value.accuracyM)
        pipeline.onFix(fix(accuracy = 12.0, nanos = 1_000_000_000))
        assertEquals(1, pipeline.state.value.fixSequence)
        pipeline.onFix(fix(accuracy = 12.0, nanos = 2_000_000_000))
        assertEquals(1, guided.size)
        assertEquals(2, pipeline.state.value.fixSequence)
        assertFalse(pipeline.state.value.starved)
    }

    @Test fun anOutlierIsHeldAndAPersistentMoveIsAccepted() = runTest {
        val pipeline = LocationPipeline(backgroundScope, PipelineClock())
        pipeline.onFix(fix(nanos = 1_000_000_000))
        val firstLat = pipeline.state.value.latitude
        repeat(2) {
            pipeline.onFix(fix(lat = 38.0, nanos = 2_000_000_000L + it))
            assertEquals(firstLat, pipeline.state.value.latitude)
        }
        pipeline.onFix(fix(lat = 38.0, nanos = 4_000_000_000))
        assertEquals(38.0, pipeline.state.value.latitude)
    }

    @Test fun aSpeedSpikeIsHeldOnceThenAccepted() = runTest {
        val pipeline = LocationPipeline(backgroundScope, PipelineClock())
        pipeline.onFix(fix(speed = 10.0, nanos = 1_000_000_000))
        pipeline.onFix(fix(speed = 50.0, nanos = 2_000_000_000))
        assertEquals(10.0, pipeline.state.value.speedMps)
        pipeline.onFix(fix(speed = 50.0, nanos = 3_000_000_000))
        assertEquals(50.0, pipeline.state.value.speedMps)
    }

    @Test fun starvationNeedsNavigationAndAnOldGuidanceFix() = runTest {
        val clock = PipelineClock()
        val pipeline = LocationPipeline(backgroundScope, clock)
        pipeline.start()
        pipeline.onFix(fix(nanos = 1_000_000_000))
        clock.now = 11_000
        advanceTimeBy(1_000)
        runCurrent()
        assertFalse(pipeline.state.value.starved)
        pipeline.navigationStarted()
        clock.now = 22_000
        advanceTimeBy(1_000)
        runCurrent()
        assertTrue(pipeline.state.value.starved)
        pipeline.onFix(fix(nanos = 2_000_000_000))
        assertFalse(pipeline.state.value.starved)
    }

    private fun fix(
        lat: Double = 37.7749,
        accuracy: Double = 10.0,
        speed: Double = 0.0,
        nanos: Long,
    ) = LocationFix(lat, -122.4194, accuracy, speed, null, nanos, gnss = true)
}
