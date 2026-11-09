package app.vela.ios.transit

import app.vela.core.i18n.NavStringsRegistry
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import app.vela.core.model.distanceTo
import app.vela.ios.route.RouteStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

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
    /** Turn-by-turn for the walking leg being walked, or an inactive state on a ride. */
    val walk: TransitWalkState = TransitWalkState(),
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
class TransitSession(
    /** Hosts the optional walk-router request; null keeps the geometry plan only. */
    private val scope: CoroutineScope? = null,
    /** Named walking maneuvers for a leg (the app's walking router). Null or empty answers keep
     *  the plan derived from the leg's own geometry. */
    private val walkDirections: (suspend (LatLng, LatLng) -> List<Maneuver>?)? = null,
    private val imperial: () -> Boolean = { false },
) {
    private val _state = MutableStateFlow(TransitState())
    val state: StateFlow<TransitState> = _state.asStateFlow()

    private var itinerary: TransitItinerary? = null
    private var nextSessionId = 0
    private val walkPlans = HashMap<Int, WalkPlan>()
    private var walkGuide: WalkGuide? = null
    private var walkJob: Job? = null
    private var walkAlong = 0.0
    private var promptSeq = 0

    /** Starts the itinerary picked in the transit chooser. False leaves the previous state alone. */
    fun start(trip: TransitItinerary, destinationName: String): Boolean {
        if (trip.steps.isEmpty() || trip.steps.none { it.line != null }) return false
        itinerary = trip
        nextSessionId += 1
        walkJob?.cancel()
        walkJob = null
        walkPlans.clear()
        walkGuide = null
        walkAlong = 0.0
        promptSeq = 0
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
        rebuildWalk(0, speak = true)
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
            walkGuide?.let { guide ->
                val along = guide.alongOf(fix)
                // A fix off the line keeps the last along-distance: a bad projection must not
                // rewind the walker to the start or skip a turn.
                if (along != null && along >= walkAlong - WALK_BACKTRACK_M) walkAlong = along
                publishWalkState(guide.view(walkAlong), guide.takePrompt(walkAlong))
            }
            val target = step.walkTo ?: return
            if (fix.distanceTo(target) <= STOP_RADIUS_M) {
                walkGuide?.markArrived()
                advanceLeg()
            }
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
        walkJob?.cancel()
        walkJob = null
        walkPlans.clear()
        walkGuide = null
        _state.value = TransitState(sessionId = nextSessionId)
    }

    /** The selected itinerary's drawn path, retained only while the session exists. */
    fun line(): DoubleArray = RouteStore.transitLineOf(itinerary)

    private fun advanceLeg() {
        val s = _state.value
        if (s.legIndex >= s.legs.lastIndex) {
            walkJob?.cancel()
            walkJob = null
            walkGuide = null
            _state.value = s.copy(
                arrived = true, stopsRemaining = -1, nextStop = null, progress = 1.0,
                walk = TransitWalkState(),
            )
        } else {
            _state.value = s.copy(legIndex = s.legIndex + 1, passedStops = 0, boarded = false)
            rebuildWalk(s.legIndex + 1, speak = true)
        }
        publishProgress()
    }

    /**
     * Builds the guidance of one walking leg: the leg's own geometry first, so a plan exists before
     * any network answer, then the walk router's named maneuvers when it answers for this leg.
     */
    private fun rebuildWalk(legIndex: Int, speak: Boolean) {
        walkJob?.cancel()
        walkJob = null
        walkGuide = null
        walkAlong = 0.0
        val trip = itinerary
        val step = trip?.steps?.getOrNull(legIndex)
        if (step == null || step.mode != TransitMode.WALK) {
            if (_state.value.walk != TransitWalkState()) _state.value = _state.value.copy(walk = TransitWalkState())
            return
        }
        val target = walkTargetName(legIndex)
        val plan = walkPlans[legIndex]
            ?: WalkingDirections.fromGeometry(step.path, step.walkFrom, step.walkTo, target, NavStringsRegistry.current())
                ?.also { walkPlans[legIndex] = it }
        if (plan == null) {
            publishWalkState(TransitWalkState(active = true, targetName = target.orEmpty()), null)
            return
        }
        val guide = WalkGuide(plan, NavStringsRegistry.current(), imperial())
        walkGuide = guide
        publishWalkState(guide.view(0.0), if (speak) guide.takePrompt(0.0) else null)
        requestNamedWalk(legIndex, step, target)
    }

    /** Asks the walk router for real street names; its answer replaces the bearing plan only if
     *  it still describes the leg being walked. */
    private fun requestNamedWalk(legIndex: Int, step: TransitStep, target: String?) {
        val source = walkDirections ?: return
        val host = scope ?: return
        val from = step.walkFrom ?: return
        val to = step.walkTo ?: return
        if (from.distanceTo(to) < MIN_ROUTER_WALK_M) return
        val sessionId = _state.value.sessionId
        val path = step.path
        walkJob = host.launch {
            val maneuvers = runCatching { source(from, to) }.getOrNull().orEmpty()
            if (maneuvers.isEmpty()) return@launch
            val current = _state.value
            if (current.sessionId != sessionId || !current.active || current.legIndex != legIndex) return@launch
            val named = WalkingDirections.fromManeuvers(maneuvers, path, target) ?: return@launch
            walkPlans[legIndex] = named
            val guide = WalkGuide(named, NavStringsRegistry.current(), imperial())
            walkGuide = guide
            walkAlong = 0.0
            // The start of the leg was already announced from the geometry plan; the named plan
            // only refines the banner, so its first instruction is not repeated.
            publishWalkState(guide.view(0.0), null)
        }
    }

    private fun walkTargetName(legIndex: Int): String? {
        val trip = itinerary ?: return null
        val ride = trip.steps.drop((legIndex + 1).coerceAtLeast(0)).firstOrNull { it.line != null }
        return ride?.boardStop?.name ?: _state.value.destinationName.ifBlank { null }
    }

    private fun publishWalkState(state: TransitWalkState, prompt: String?) {
        val seq = if (prompt != null) ++promptSeq else promptSeq
        _state.value = _state.value.copy(walk = state.copy(prompt = prompt, promptSeq = seq))
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
        /** A projection this far behind the last one is a fix artifact, not walking backwards. */
        const val WALK_BACKTRACK_M = 20.0
        /** Shorter transfer walks keep their geometry plan; a router call adds nothing. */
        const val MIN_ROUTER_WALK_M = 20.0
    }
}
