package app.vela.ios.transit

import app.vela.core.data.transit.TransitLineClient
import app.vela.core.data.transit.TransitLineRun
import app.vela.core.model.LatLng
import app.vela.core.model.TransitMode
import app.vela.core.model.defaultColorHex

/**
 * The color a line keeps across Vela: the feed's own `routeColor` when it sent a usable one, else
 * Vela's mode color. [source] says which of the two it is, so the sheet can tell the rider; a
 * feed color is never presented as Vela's and a mode color is never presented as the agency's.
 */
object TransitLineColor {
    const val SOURCE_FEED = "feed"
    const val SOURCE_MODE = "mode"

    fun hex(feedHex: String?, mode: TransitMode): String =
        TransitLineClient.colorOf(feedHex) ?: mode.defaultColorHex

    fun source(feedHex: String?): String =
        if (TransitLineClient.colorOf(feedHex) != null) SOURCE_FEED else SOURCE_MODE
}

/** One other line at a stop, drawn as its own badge in the ribbon. */
data class TransitLineBadge(
    val label: String,
    val mode: String,
    val colorHex: String,
)

/**
 * One stop of the ribbon. [minutes] is signed: negative once the run has called there.
 * [hasTime] is false for a call the feed sent without a time; [expectedEpochSec] is then 0 and no
 * countdown is computed from it.
 */
data class TransitLineStop(
    val name: String,
    val code: String?,
    val stopId: String?,
    val clockText: String?,
    val scheduledText: String?,
    val expectedEpochSec: Long,
    val hasTime: Boolean,
    val minutes: Int,
    val delayMin: Int,
    val hasDelay: Boolean,
    val canceled: Boolean,
    val latitude: Double,
    val longitude: Double,
    val passed: Boolean,
    val next: Boolean,
    val transferLines: List<TransitLineBadge>,
)

/**
 * Where the vehicle is, computed from the run's own timetable and real-time calls: [fraction] of
 * the way from [fromIndex] to [toIndex], heading to [stopIndex]. It is an ESTIMATE, never a GPS
 * fix or a vehicle id: the feed publishes neither. [estimated] stays true so no surface can call
 * it live tracking.
 */
data class TransitLinePosition(
    val estimated: Boolean,
    val fromIndex: Int,
    val toIndex: Int,
    val stopIndex: Int,
    val fraction: Double,
    val passedCount: Int,
    val beforeStart: Boolean,
    val finished: Boolean,
    val nextStopName: String,
    val secondsToNextStop: Int,
)

/** The ribbon's data for one run. Empty [stops] means the feed gave no sequence. */
data class TransitLinePlan(
    val stops: List<TransitLineStop> = emptyList(),
    val position: TransitLinePosition? = null,
    val fromName: String = "",
    val toName: String = "",
) {
    val stopCount: Int get() = stops.size
}

/**
 * Builds the ribbon from the feed's run and the clock. No stop, time, delay or badge is invented:
 * every row comes from [run], and the position only interpolates between two times the feed sent.
 * [transfers] are the other lines of the board the sheet was opened from; they are attached to the
 * one stop whose id (or, failing an id, name) matches [openedStopId]/[openedStopName].
 */
object TransitLineRoute {
    fun build(
        run: TransitLineRun,
        nowEpochSec: Long,
        transfers: List<TransitLineBadge> = emptyList(),
        openedStopId: String? = null,
        openedStopName: String = "",
    ): TransitLinePlan {
        val rows = run.stops.map { stop ->
            val expected = stop.expectedEpochSec
            val scheduled = stop.scheduledEpochSec
            val delay = if (expected != null && scheduled != null) {
                ((expected - scheduled) / 60).toInt()
            } else {
                0
            }
            TransitLineStop(
                name = stop.name,
                code = stop.code,
                stopId = stop.stopId,
                clockText = stop.clockText,
                scheduledText = stop.scheduledText,
                expectedEpochSec = expected ?: 0L,
                hasTime = expected != null,
                minutes = expected?.let { ((it - nowEpochSec) / 60).toInt() } ?: 0,
                delayMin = delay,
                hasDelay = expected != null && scheduled != null && delay != 0,
                canceled = stop.canceled,
                latitude = stop.latitude,
                longitude = stop.longitude,
                passed = expected != null && expected < nowEpochSec,
                next = false,
                transferLines = if (matchesStop(stop.stopId, stop.name, openedStopId, openedStopName)) {
                    transfers
                } else {
                    emptyList()
                },
            )
        }
        val nextIndex = rows.indexOfFirst { it.hasTime && it.expectedEpochSec > nowEpochSec }
        val marked = if (nextIndex >= 0) rows.toMutableList().also { it[nextIndex] = it[nextIndex].copy(next = true) } else rows
        return TransitLinePlan(
            stops = marked,
            position = positionOf(rows, nowEpochSec),
            fromName = rows.firstOrNull()?.name ?: run.stops.first().name,
            toName = rows.lastOrNull()?.name ?: run.stops.last().name,
        )
    }

    /**
     * The board and the trip can name the same physical stop from two feeds (`us-ca-SF-bayarea_15419`
     * on a board, `us-ca-SFMTA_15419` in a run), so the id is tried first and the exact name after.
     */
    private fun matchesStop(stopId: String?, name: String, openedId: String?, openedName: String): Boolean {
        if (openedId != null && stopId != null && stopId == openedId) return true
        return openedName.isNotBlank() && name.trim().equals(openedName.trim(), ignoreCase = true)
    }

    /** Pure interpolation between the two calls that bracket [now]. Null when the feed timed no stop. */
    fun positionOf(stops: List<TransitLineStop>, nowEpochSec: Long): TransitLinePosition? {
        val timed = stops.withIndex().filter { it.value.hasTime }
        if (timed.isEmpty()) return null
        val passedCount = stops.count { it.hasTime && it.expectedEpochSec < nowEpochSec }
        val first = timed.first()
        val last = timed.last()
        val firstEpoch = first.value.expectedEpochSec
        val lastEpoch = last.value.expectedEpochSec
        if (nowEpochSec < firstEpoch) {
            return TransitLinePosition(
                estimated = true, fromIndex = first.index, toIndex = first.index,
                stopIndex = first.index, fraction = 0.0, passedCount = 0,
                beforeStart = true, finished = false,
                nextStopName = first.value.name,
                secondsToNextStop = (firstEpoch - nowEpochSec).toInt(),
            )
        }
        if (nowEpochSec >= lastEpoch) {
            return TransitLinePosition(
                estimated = true, fromIndex = last.index, toIndex = last.index,
                stopIndex = last.index, fraction = 1.0, passedCount = passedCount,
                beforeStart = false, finished = true,
                nextStopName = last.value.name, secondsToNextStop = 0,
            )
        }
        for (k in 0 until timed.size - 1) {
            val from = timed[k]
            val to = timed[k + 1]
            val start = from.value.expectedEpochSec
            val end = to.value.expectedEpochSec
            if (nowEpochSec >= start && nowEpochSec < end) {
                val span = (end - start).coerceAtLeast(1L)
                return TransitLinePosition(
                    estimated = true, fromIndex = from.index, toIndex = to.index,
                    stopIndex = to.index, fraction = ((nowEpochSec - start).toDouble() / span).coerceIn(0.0, 1.0),
                    passedCount = passedCount, beforeStart = false, finished = false,
                    nextStopName = to.value.name,
                    secondsToNextStop = (end - nowEpochSec).toInt(),
                )
            }
        }
        return null
    }

    /** The run's drawn path when the feed sent one, else the stop chain, labeled as such. */
    fun geometryOf(run: TransitLineRun): Pair<List<LatLng>, String> =
        if (run.shape.size >= 2) run.shape to SHAPE_FEED
        else run.stops.map { LatLng(it.latitude, it.longitude) } to SHAPE_STOPS

    const val SHAPE_FEED = "feed"
    const val SHAPE_STOPS = "stops"
}
