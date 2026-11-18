package app.vela.ios.transit

import app.vela.core.data.transit.TransitOrder
import app.vela.core.data.transit.Transitous
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitStep

/**
 * The chooser's reading of one planner itinerary (transfers, walking, real-time) and the order it
 * lists them in. Pure: every number comes from the planner's own legs and clocks.
 */
object TransitTrips {
    /** The chooser lists at most this many trips. The planner is asked for five
     *  (`numItineraries` is a minimum) and often sends one or two more. */
    const val SHOWN = 5

    /** Rides minus one; a trip with a single ride has none. */
    fun transfers(trip: TransitItinerary): Int = (trip.steps.count { it.line != null } - 1).coerceAtLeast(0)

    /** The walking time of the whole trip in seconds: each walk's own clocks, else its text. */
    fun walkSeconds(trip: TransitItinerary): Long = trip.steps.filter { it.line == null }.sumOf(::legSeconds)

    /** True when the first ride's times are real-time; that ride sets when the user must leave. */
    fun live(trip: TransitItinerary): Boolean = trip.steps.firstOrNull { it.line != null }?.realTime == true

    /**
     * The list order. Leave now and depart at: earliest arrival first. Arrive by: latest departure
     * first, so the trip that lets the user leave last leads. Fewer transfers and less walking
     * sort on that first, then the same arrival rule. Ties keep the planner's order, and a trip
     * without clocks goes after the ones that have them.
     */
    fun order(trips: List<TransitItinerary>, routePref: Int, timeMode: Int): List<TransitItinerary> {
        val byClock: Comparator<TransitItinerary> = if (timeMode == TransitPlanQuery.TIME_ARRIVE_BY) {
            compareBy<TransitItinerary> { it.departureEpochSec == null }.thenByDescending { it.departureEpochSec ?: 0L }
        } else {
            compareBy<TransitItinerary> { it.arrivalEpochSec == null }.thenBy { it.arrivalEpochSec ?: 0L }
        }
        val rule = when (routePref) {
            TransitPlanQuery.ROUTE_FEWER_TRANSFERS -> compareBy<TransitItinerary> { transfers(it) }.then(byClock)
            TransitPlanQuery.ROUTE_LESS_WALKING -> compareBy<TransitItinerary> { walkSeconds(it) }.then(byClock)
            else -> byClock
        }
        return trips.sortedWith(rule)
    }

    /** The chooser's list: [order], then the first [SHOWN]. */
    fun forChooser(trips: List<TransitItinerary>, routePref: Int, timeMode: Int): List<TransitItinerary> =
        order(trips, routePref, timeMode).take(SHOWN)

    private fun legSeconds(step: TransitStep): Long {
        val a = step.departEpochSec
        val b = step.arriveEpochSec
        if (a != null && b != null && b >= a) return b - a
        return TransitOrder.minutesOf(step.durationText) * 60L
    }
}

/**
 * Debug scenarios only: a recorded `/api/v1/plan` reply the chooser lists instead of asking the
 * planner. Swift sets [json] under a launch flag; a release build never does, so it stays null.
 */
object TransitTripsFixture {
    var json: String? = null

    /** The recorded itineraries, or null when no fixture is armed. */
    fun trips(): List<TransitItinerary>? {
        val text = json ?: return null
        return Transitous.parsePlanForFixture(text, 37.7522, -122.4184, 37.7955, -122.3937)
    }
}
