package app.vela.ios.transit

import app.vela.core.model.TransitMode

/**
 * What the Transitous planner (`/api/v1/plan`) accepts for one transit search. It is the only
 * source on iOS, so these are the real limits:
 *
 * - [timeMode]: 0 leaves now, 1 departs at [timeEpochSec], 2 arrives by [timeEpochSec]. The
 *   endpoint has no "last available" value; Android treats it as arrive-by, iOS does not expose it.
 * - [prefer]: the planner's own vehicle filter, written as `transitModes`. Its public instance
 *   knows BUS, SUBWAY, RAIL and TRAM. FERRY has no planner mode, so a ferry-only choice is not
 *   offered; every other [TransitMode] is ignored rather than guessed.
 * - [routePref]: 0 best, 2 fewer transfers, 3 less walking. The endpoint has no such parameter;
 *   [app.vela.core.data.transit.TransitOrder.byPreference] reorders the returned trips instead.
 *   It never asks for a trip that was not returned.
 */
data class TransitPlanQuery(
    val timeMode: Int = TIME_NOW,
    val timeEpochSec: Long? = null,
    val prefer: Set<Int> = emptySet(),
    val routePref: Int = ROUTE_BEST,
) {
    /** The query with a meaningless mode or clock dropped, so a stale picker cannot break a search. */
    fun normalized(): TransitPlanQuery {
        val mode = if (timeMode in TIME_NOW..TIME_ARRIVE_BY) timeMode else TIME_NOW
        val epoch = timeEpochSec?.takeIf { it > 0 && mode != TIME_NOW }
        return copy(timeMode = if (epoch == null) TIME_NOW else mode, timeEpochSec = epoch)
    }

    /** The planner mode names this query asks for, in its own order; empty means every mode. */
    fun modeNames(): List<String> = modeNamesFor(prefer)

    /** A debug/test view of the request that does not depend on the clock. */
    fun summary(): String = "time=${normalized().timeMode} epoch=${normalized().timeEpochSec ?: 0}" +
        " modes=${modeNames().joinToString(",").ifEmpty { "all" }} pref=$routePref"

    companion object {
        const val TIME_NOW = 0
        const val TIME_DEPART_AT = 1
        const val TIME_ARRIVE_BY = 2
        const val ROUTE_BEST = 0
        const val ROUTE_FEWER_TRANSFERS = 2
        const val ROUTE_LESS_WALKING = 3

        /** Transitous' vehicle numbering, the same one Android's chooser sends. */
        private val PLAN_MODES = listOf("BUS", "SUBWAY", "RAIL", "TRAM")

        fun modeIndex(mode: TransitMode): Int? = when (mode) {
            TransitMode.BUS -> 0
            TransitMode.SUBWAY -> 1
            TransitMode.TRAIN -> 2
            TransitMode.TRAM -> 3
            else -> null
        }

        fun modeNamesFor(prefer: Set<Int>): List<String> =
            prefer.sorted().mapNotNull { PLAN_MODES.getOrNull(it) }

        /** The four flags the options sheet shows, as the set the planner takes. */
        fun flags(bus: Boolean, subway: Boolean, train: Boolean, tram: Boolean): Set<Int> = buildSet {
            if (bus) add(0)
            if (subway) add(1)
            if (train) add(2)
            if (tram) add(3)
        }

        fun acceptsRoutePreference(pref: Int): Boolean =
            pref == ROUTE_BEST || pref == ROUTE_FEWER_TRANSFERS || pref == ROUTE_LESS_WALKING
    }
}
