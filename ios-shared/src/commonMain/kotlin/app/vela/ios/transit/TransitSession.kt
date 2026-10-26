package app.vela.ios.transit

import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import app.vela.core.model.distanceTo
import app.vela.ios.route.RouteStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** One walk or ride in a transit guidance session. Times are scheduled unless an estimated field
 *  is present. A delay is present only when Transitous supplied both live and timetable times. */
data class TransitLegState(
    val kind: String,
    val line: String?,
    val color: String?,
    val textColor: String?,
    val direction: String?,
    val boardStop: String?,
    val alightStop: String?,
    val durationText: String?,
    val scheduledDeparture: String?,
    val estimatedDeparture: String?,
    val scheduledArrival: String?,
    val estimatedArrival: String?,
    val delayMinutes: Int?,
    val stopCount: Int,
)

/** The process-owned transit guidance state. [legIndex] and [passedStops] are zero based;
 *  [stopsRemaining] and [nextStop] describe the current ride, or are -1/null during a walk. */
data class TransitState(
    val active: Boolean = false,
    val arrived: Boolean = false,
    val destinationName: String = "",
    val sessionId: Int = 0,
    val revision: Int = 0,
    val legs: List<TransitLegState> = emptyList(),
    val legIndex: Int = -1,
    val passedStops: Int = 0,
    val boarded: Boolean = false,
    val stopsRemaining: Int = -1,
    val nextStop: String? = null,
    val walkTarget: String? = null,
    val overallArrivalText: String? = null,
    /** Epoch seconds, or -1 when the planner did not supply an overall arrival time. */
    val overallArrivalEpochSec: Long = -1,
    val overallArrivalIsEstimate: Boolean = false,
    val progress: Double = 0.0,
) {
    fun current(): TransitLegState? = if (active) legs.getOrNull(legIndex) else null

    /** The ride being ridden now, or the next ride to board during a walking leg. */
    fun displayRide(): TransitLegState? {
        if (!active) return null
        current()?.let { if (it.kind != TransitMode.WALK.name) return it }
        return nextRide()
    }

    /** The next ride strictly after the current leg, or after the walking leg being shown. */
    fun nextRide(): TransitLegState? {
        if (!active) return null
        val current = current()
        val from = if (current != null && current.kind != TransitMode.WALK.name) legIndex + 1 else legIndex
        return legs.drop(from.coerceAtLeast(0)).firstOrNull { it.kind != TransitMode.WALK.name }
    }
}

/**
 * Ordered Transitous legs with location and preview progression. This class does not poll a
 * planner and does not infer delays. It only maps times already present on the selected itinerary.
 * All methods are called on the main thread on iOS; construction itself has no side effects.
 */
class TransitSession {
    private val _state = MutableStateFlow(TransitState())
    val state: StateFlow<TransitState> = _state.asStateFlow()

    private var itinerary: TransitItinerary? = null
    private var nextSessionId = 0

    /** Starts the itinerary picked in the transit chooser. False leaves the previous state alone. */
    fun start(trip: TransitItinerary, destinationName: String): Boolean {
        if (trip.steps.isEmpty() || trip.steps.none { it.line != null }) return false
        itinerary = trip
        nextSessionId += 1
        val legs = trip.steps.map(::legState)
        _state.value = TransitState(
            active = true,
            destinationName = destinationName,
            sessionId = nextSessionId,
            legs = legs,
            legIndex = 0,
            overallArrivalText = trip.arrivalText,
            overallArrivalEpochSec = trip.arrivalEpochSec ?: -1,
            overallArrivalIsEstimate = legs.lastOrNull { it.kind != TransitMode.WALK.name }?.estimatedArrival != null,
        )
        publishProgress()
        return true
    }

    /** Advances only from a usable fix. Walking finishes near its endpoint; a ride advances one
     *  stop at a time and moves to the next leg at its alighting stop. */
    fun onLocation(lat: Double, lng: Double, accuracyM: Double) {
        val s = _state.value
        val trip = itinerary ?: return
        if (!s.active || s.arrived || lat !in -90.0..90.0 || lng !in -180.0..180.0) return
        if (!accuracyM.isFinite() || accuracyM < 0 || accuracyM > MAX_FIX_ACCURACY_M) return
        val fix = LatLng(lat, lng)
        val step = trip.steps.getOrNull(s.legIndex) ?: return
        if (step.mode == TransitMode.WALK) {
            val target = step.walkTo ?: return
            if (fix.distanceTo(target) <= STOP_RADIUS_M) advanceLeg()
            return
        }

        val stops = rideStops(step)
        val next = stops.getOrNull(s.passedStops + 1)
        if (next?.location != null && fix.distanceTo(next.location!!) <= STOP_RADIUS_M) {
            if (s.passedStops + 1 == stops.lastIndex) {
                advanceLeg()
            } else {
                _state.value = s.copy(passedStops = s.passedStops + 1, boarded = true)
                publishProgress()
            }
            return
        }

        // A ride without intermediate stop details still leaves its boarding state after departure.
        if (!s.boarded) {
            val board = step.boardStop?.location
            val alight = step.alightStop?.location
            if (board != null && alight != null && fix.distanceTo(board) > BOARDING_EXIT_M &&
                fix.distanceTo(alight) < board.distanceTo(alight)
            ) {
                _state.value = s.copy(boarded = true)
                publishProgress()
            }
        }
    }

    /** The debug/preview control. Production UI does not expose manual leg advancement. */
    fun advanceForPreview() {
        val s = _state.value
        if (s.active && !s.arrived) advanceLeg()
    }

    /** End is final: the state, route and later location fixes are all detached from the session. */
    fun end() {
        itinerary = null
        _state.value = TransitState(sessionId = nextSessionId)
    }

    /** The selected itinerary's drawn path, retained only while the session exists. */
    fun line(): DoubleArray = RouteStore.transitLineOf(itinerary)

    private fun advanceLeg() {
        val s = _state.value
        if (s.legIndex >= s.legs.lastIndex) {
            _state.value = s.copy(arrived = true, stopsRemaining = -1, nextStop = null, progress = 1.0)
        } else {
            _state.value = s.copy(legIndex = s.legIndex + 1, passedStops = 0, boarded = false)
        }
        publishProgress()
    }

    private fun publishProgress() {
        val s = _state.value
        val trip = itinerary ?: return
        if (!s.active) return
        if (s.arrived) {
            _state.value = s.copy(
                revision = s.revision + 1,
                stopsRemaining = -1,
                nextStop = null,
                walkTarget = null,
                progress = 1.0,
            )
            return
        }
        val step = trip.steps.getOrNull(s.legIndex)
        val ride = step?.takeIf { it.mode != TransitMode.WALK }
        val stops = ride?.let(::rideStops).orEmpty()
        val total = ride?.let(::stopCount) ?: -1
        val legFraction = if (ride != null && total > 0) {
            (s.passedStops.toDouble() / total).coerceIn(0.0, 1.0)
        } else {
            0.0
        }
        val nextRide = trip.steps.drop((s.legIndex + 1).coerceAtLeast(0)).firstOrNull { it.line != null }
        val walkTarget = if (step?.mode == TransitMode.WALK) {
            nextRide?.boardStop?.name ?: s.destinationName.ifBlank { null }
        } else {
            null
        }
        _state.value = s.copy(
            revision = s.revision + 1,
            stopsRemaining = if (ride != null && total >= 0) (total - s.passedStops).coerceAtLeast(0) else -1,
            nextStop = stops.getOrNull(s.passedStops + 1)?.name,
            walkTarget = walkTarget,
            progress = if (s.arrived) 1.0 else ((s.legIndex + legFraction) / s.legs.size).coerceIn(0.0, 1.0),
        )
    }

    private fun legState(step: TransitStep): TransitLegState {
        val board = step.boardStop
        val alight = step.alightStop
        val departure = timePair(step.departText, board)
        val arrival = timePair(step.arriveText, alight)
        return TransitLegState(
            kind = step.mode.name,
            line = step.line?.name,
            color = step.line?.colorHex,
            textColor = step.line?.textColorHex,
            direction = step.headsign,
            boardStop = board?.name,
            alightStop = alight?.name,
            durationText = step.durationText,
            scheduledDeparture = departure.first,
            estimatedDeparture = departure.second,
            scheduledArrival = arrival.first,
            estimatedArrival = arrival.second,
            delayMinutes = board?.delayMin ?: alight?.delayMin,
            stopCount = stopCount(step),
        )
    }

    private fun timePair(fallback: String?, stop: TransitStopTime?): Pair<String?, String?> {
        val shown = stop?.timeText ?: fallback
        val live = stop != null && (stop.delayMin != null || stop.scheduledText != null)
        return if (live) {
            stop.scheduledText to shown
        } else {
            shown to null
        }
    }

    private fun stopCount(step: TransitStep): Int = step.numStops
        ?: (step.intermediateStops.size + 1).takeIf { step.boardStop != null && step.alightStop != null }
        ?: -1

    private fun rideStops(step: TransitStep): List<TransitStopTime> =
        listOfNotNull(step.boardStop) + step.intermediateStops + listOfNotNull(step.alightStop)

    companion object {
        const val STOP_RADIUS_M = 80.0
        const val MAX_FIX_ACCURACY_M = 100.0
        const val BOARDING_EXIT_M = 150.0
    }
}
