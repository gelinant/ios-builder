package app.vela.ios.replay

import app.vela.core.model.LatLng
import app.vela.core.model.bearingTo
import app.vela.core.model.distanceTo

/** One frame of the demo replay: where the puck is, how fast, which way and how far along. */
data class ReplaySample(
    val latitude: Double,
    val longitude: Double,
    val bearingDeg: Double,
    val speedMps: Double,
    /** Meters from the first fix, along the trace. */
    val distanceM: Double,
    /** The recorded time this frame stands for, relative to the first fix. */
    val traceMs: Long,
    val finished: Boolean,
)

/**
 * The timeline of a demo replay: a recorded trace walked at [speedup] times its own pace,
 * interpolating position, speed, distance and heading by the fixes' timestamps.
 *
 * This is deliberately pure and carries no guidance: the caller only draws the returned frame and
 * labels it a replay. It never starts navigation, speaks, estimates an arrival or posts a Live
 * Activity, so a demo can never be mistaken for live guidance.
 */
class DemoReplay(points: List<TripPoint>, val speedup: Double = 4.0) {
    private val fixes: List<TripPoint> = points.filter { it.tMs >= 0L }
    private val pace: Double = if (speedup.isFinite() && speedup > 0.0) speedup else 1.0

    /** The recorded time from the first fix to the last, in milliseconds. */
    val traceDurationMs: Long =
        if (fixes.size < 2) 0L else (fixes.last().tMs - fixes.first().tMs).coerceAtLeast(0L)

    /** How long playing the whole trace takes at [speedup]. */
    val durationMs: Long = (traceDurationMs / pace).toLong().coerceAtLeast(0L)

    /** The frame at [playheadMs] of the replay, clamped to both ends. Null for an empty trace. */
    fun sampleAt(playheadMs: Long): ReplaySample? {
        val first = fixes.firstOrNull() ?: return null
        if (fixes.size == 1) {
            return ReplaySample(
                first.lat, first.lng, 0.0, first.speedMps, first.distanceM,
                traceMs = 0L, finished = true,
            )
        }
        val play = playheadMs.coerceAtLeast(0L)
        val traceMs = (play * pace).toLong().coerceIn(0L, traceDurationMs)
        val last = fixes.last()
        if (traceMs >= traceDurationMs) {
            return ReplaySample(
                last.lat, last.lng, bearingAt(fixes.lastIndex), last.speedMps, last.distanceM,
                traceMs = traceDurationMs, finished = play >= durationMs,
            )
        }
        var lo = 0
        var hi = fixes.lastIndex
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (fixes[mid].tMs < traceMs) lo = mid + 1 else hi = mid
        }
        val to = fixes[lo]
        val from = fixes[(lo - 1).coerceAtLeast(0)]
        val span = (to.tMs - from.tMs).coerceAtLeast(0L)
        val f = if (span == 0L) 1.0 else (traceMs - from.tMs).toDouble() / span
        return ReplaySample(
            latitude = from.lat + (to.lat - from.lat) * f,
            longitude = from.lng + (to.lng - from.lng) * f,
            bearingDeg = bearingAt(lo),
            speedMps = from.speedMps + (to.speedMps - from.speedMps) * f,
            distanceM = from.distanceM + (to.distanceM - from.distanceM) * f,
            traceMs = traceMs,
            finished = play >= durationMs,
        )
    }

    /** The heading of the segment ending at [index], searching outward for real movement. */
    private fun bearingAt(index: Int): Double {
        var i = index.coerceIn(0, fixes.lastIndex)
        while (i < fixes.lastIndex) {
            val a = LatLng(fixes[i].lat, fixes[i].lng)
            val b = LatLng(fixes[i + 1].lat, fixes[i + 1].lng)
            if (a.distanceTo(b) >= 0.5) return a.bearingTo(b)
            i++
        }
        while (i > 0) {
            val a = LatLng(fixes[i - 1].lat, fixes[i - 1].lng)
            val b = LatLng(fixes[i].lat, fixes[i].lng)
            if (a.distanceTo(b) >= 0.5) return a.bearingTo(b)
            i--
        }
        return 0.0
    }
}
