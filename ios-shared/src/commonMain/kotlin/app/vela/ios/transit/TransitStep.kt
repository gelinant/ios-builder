package app.vela.ios.transit

/** One place in the step sequence that GO and the transit Live Activity walk through: a walk, the
 *  wait before a ride ([boarded] false), the ride ([boarded] true), then [arrived]. [passedStops]
 *  only counts on a boarded ride. Positions compare in trip order. */
data class TransitStepPosition(
    val legIndex: Int,
    val boarded: Boolean = false,
    val passedStops: Int = 0,
    val arrived: Boolean = false,
) : Comparable<TransitStepPosition> {
    override fun compareTo(other: TransitStepPosition): Int = compareValuesBy(
        this, other, { it.arrived }, { it.legIndex }, { it.boarded }, { it.passedStops })
}

/** Manual Previous and Next over one itinerary. [rides] has one entry per leg, true for a ride.
 *  Next is the old "Skip this step": walk to the next leg, wait to ride, ride to the next leg, last
 *  leg to arrival. Previous is its reverse; it enters an earlier ride at its first stop. */
object TransitStepSequence {
    fun next(rides: List<Boolean>, at: TransitStepPosition): TransitStepPosition? {
        if (at.arrived || rides.isEmpty()) return null
        val ride = rides.getOrElse(at.legIndex) { false }
        return when {
            ride && !at.boarded -> TransitStepPosition(at.legIndex, boarded = true)
            at.legIndex >= rides.lastIndex -> TransitStepPosition(rides.lastIndex, arrived = true)
            else -> TransitStepPosition(at.legIndex + 1)
        }
    }

    fun previous(rides: List<Boolean>, at: TransitStepPosition): TransitStepPosition? {
        if (rides.isEmpty()) return null
        if (at.arrived) return lastStepOf(rides, rides.lastIndex)
        val index = at.legIndex.coerceIn(0, rides.lastIndex)
        return when {
            rides[index] && at.boarded -> TransitStepPosition(index)
            index == 0 -> null
            else -> lastStepOf(rides, index - 1)
        }
    }

    private fun lastStepOf(rides: List<Boolean>, index: Int) =
        TransitStepPosition(index, boarded = rides[index])
}

/**
 * The manual override rule. A manual Previous records the furthest position reached so far, the
 * mark. While the mark exists, automatic progress (a location fix, or a session report pushed to
 * GO) that does not go beyond it is dropped: a stale index or a fix at the stop just left cannot
 * undo the user's choice. The hold ends when automatic progress goes beyond the mark, or when Next
 * brings the manual position back to it.
 */
class TransitStepHold {
    var mark: TransitStepPosition? = null
        private set

    val held: Boolean get() = mark != null

    fun hold(reached: TransitStepPosition) {
        val current = mark
        mark = if (current == null || reached > current) reached else current
    }

    /** True when an automatic move to [candidate] may apply; a move beyond the mark ends the hold. */
    fun allows(candidate: TransitStepPosition): Boolean {
        val current = mark ?: return true
        if (candidate > current) {
            mark = null
            return true
        }
        return false
    }

    /** A manual Next that reaches the marked step ends the hold, at any stop of that ride, so the
     *  next fix along the ride applies again. */
    fun reached(position: TransitStepPosition) {
        val current = mark ?: return
        if (position.copy(passedStops = 0) >= current.copy(passedStops = 0)) mark = null
    }

    fun clear() {
        mark = null
    }
}
