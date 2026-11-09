package app.vela.ios.time

import app.vela.core.data.ClockFormat
import kotlinx.datetime.TimeZone

/**
 * The one time choice every surface shares: leave now, depart at, arrive by, a date and the next
 * five minute slot. The three modes keep the numbers the Transitous planner already receives
 * (0 without `time`, 1 with `time`, 2 with `time` and `arriveBy`), so SwiftUI and the route store
 * cannot drift apart.
 *
 * The rules are pure: no clock, no zone and no locale is read here. The caller passes the current
 * epoch and the device zone, which keeps the DST arithmetic in `kotlinx-datetime` and makes the
 * tests independent of the machine.
 */
object TimeChoice {
    /** Leave now: the planner receives no time at all. */
    const val NOW: Int = 0

    /** Depart at: the planner receives `time`. */
    const val DEPART: Int = 1

    /** Arrive by: the planner receives `time` and `arriveBy`. */
    const val ARRIVE: Int = 2

    /** The slot every future choice is rounded to. */
    const val SLOT_SECONDS: Long = 300L

    /** The step of the +15 minutes button. */
    const val STEP_SECONDS: Long = 900L

    /** Any mode outside the three known ones is leave now, never a silent departure. */
    fun normalizedMode(mode: Int): Int = if (mode == DEPART || mode == ARRIVE) mode else NOW

    /** The first five minute slot at or after [nowSec]. A time already on a slot keeps it. */
    fun nextFiveMinuteSlot(nowSec: Long): Long {
        val floor = nowSec.floorDiv(SLOT_SECONDS) * SLOT_SECONDS
        return if (floor == nowSec) nowSec else floor + SLOT_SECONDS
    }

    /**
     * The epoch a mode sends to the planner: null for leave now, so no `time` parameter is built.
     * A future mode with no epoch also returns null and is normalised to leave now by the caller.
     */
    fun queryEpoch(mode: Int, epochSec: Long): Long? =
        if (normalizedMode(mode) == NOW || epochSec <= 0L) null else epochSec

    /**
     * The epoch a choice really holds: leave now stores nothing, and a past departure or arrival
     * moves to the next slot instead of asking the planner for a time that has gone.
     */
    fun normalizedEpoch(mode: Int, epochSec: Long, nowSec: Long): Long =
        if (normalizedMode(mode) == NOW) 0L
        else if (epochSec > nowSec) epochSec
        else nextFiveMinuteSlot(nowSec)

    /** The +15 minutes button, in the same five minute grid. */
    fun plusFifteenMinutes(epochSec: Long): Long = epochSec + STEP_SECONDS

    /** "Leave now", "Depart at 9:05 AM" or "Arrive by 9:00 AM" in [zone] and the clock in use. */
    fun label(mode: Int, epochSec: Long, zone: TimeZone): String = when (normalizedMode(mode)) {
        DEPART -> "Depart at ${ClockFormat.at(epochSec, zone)}"
        ARRIVE -> "Arrive by ${ClockFormat.at(epochSec, zone)}"
        else -> "Leave now"
    }

    /** The same label for Swift, which carries the device zone as its identifier. An unknown
     *  identifier falls back to UTC rather than to the machine's zone, so the text never claims a
     *  zone the caller did not ask for. */
    fun label(mode: Int, epochSec: Long, zoneId: String): String =
        label(mode, epochSec, runCatching { TimeZone.of(zoneId) }.getOrDefault(TimeZone.UTC))
}
