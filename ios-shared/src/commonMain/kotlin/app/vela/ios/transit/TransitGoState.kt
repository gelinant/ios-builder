package app.vela.ios.transit

import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime
import app.vela.core.model.defaultColorHex
import kotlin.time.Instant
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toInstant
import kotlinx.datetime.toLocalDateTime

/** One stop of a GO ride, with the timetable and the live time kept apart. Epoch 0 means the feed
 *  gave no time for this stop; a zero is never replaced by a guess. */
data class TransitGoStop(
    val name: String,
    val scheduledEpochSec: Long = 0,
    val estimatedEpochSec: Long = 0,
)

/** One walk or ride as the GO screen consumes it. [timed] is true only when the feed supplied at
 *  least one clock time for the leg, so a leg without times can stay silent instead of pretending. */
data class TransitGoLeg(
    val kind: String,
    val line: String = "",
    val colorHex: String = "",
    val textColorHex: String = "",
    val direction: String = "",
    val fromName: String = "",
    val toName: String = "",
    val durationMinutes: Int = 0,
    val scheduledDepartureEpochSec: Long = 0,
    val estimatedDepartureEpochSec: Long = 0,
    val scheduledArrivalEpochSec: Long = 0,
    val estimatedArrivalEpochSec: Long = 0,
    val stops: List<TransitGoStop> = emptyList(),
    val stopCount: Int = 0,
    val timed: Boolean = false,
    /** The printed departure the board would list for this run, used only to match its anchor. */
    val departureClockText: String = "",
)

/** One departure the stop board lists, as GO reads it when a later departure is requested. */
data class TransitGoBoardDeparture(
    val line: String,
    val headsign: String = "",
    val clockText: String = "",
    val epochSec: Long = 0,
)

/** Where a GO leave-later request starts. [source] is "board" for the line's own departure at
 *  the stop, or "now" for the now-plus-minutes fallback the screen has to state. */
data class TransitGoAnchor(
    val epochSec: Long,
    val source: String,
    val stopName: String,
)

/** The trip screen's anchor rule, applied to GO: only the line's own departure at the stop from
 *  the board may anchor a later departure. Anything else falls back to now plus the requested
 *  minutes, and the caller says so instead of presenting the fallback as a board time. */
object TransitGoAnchorSelector {
    const val SOURCE_BOARD = "board"
    const val SOURCE_NOW = "now"

    fun select(
        leg: TransitGoLeg?,
        boardStopName: String,
        boardDepartures: List<TransitGoBoardDeparture>,
        nowEpochSec: Long,
        deltaMinutes: Int,
    ): TransitGoAnchor {
        val delta = deltaMinutes.toLong() * 60L
        val ride = leg?.takeIf { it.kind == TransitGoMachine.KIND_RIDE }
        val stop = ride?.fromName.orEmpty()
        val match = if (ride == null || !sameStop(stop, boardStopName)) {
            null
        } else {
            boardDepartures.firstOrNull { departure ->
                departure.epochSec > 0 &&
                    departure.clockText.isNotBlank() &&
                    departure.clockText == ride.departureClockText &&
                    sameText(departure.line, ride.line) &&
                    sameDirection(departure.headsign, ride.direction)
            }
        }
        if (match != null) {
            return TransitGoAnchor(match.epochSec + delta, SOURCE_BOARD, stop)
        }
        return TransitGoAnchor(nowEpochSec + delta, SOURCE_NOW, stop)
    }

    private fun sameStop(a: String, b: String): Boolean =
        a.isNotBlank() && b.isNotBlank() && sameText(a, b)

    private fun sameText(a: String, b: String): Boolean =
        a.trim().equals(b.trim(), ignoreCase = true)

    /** An absent headsign on either side cannot disprove the match; two present ones must agree. */
    private fun sameDirection(a: String, b: String): Boolean =
        a.isBlank() || b.isBlank() || sameText(a, b)
}

/** The GO itinerary. [liveData] says the selected itinerary carried real-time fields when it was
 *  chosen; [fetchedAtEpochSec] anchors the stale check. Nothing here triggers a request. */
data class TransitGoPlan(
    val destinationName: String,
    val legs: List<TransitGoLeg>,
    val liveData: Boolean,
    val fetchedAtEpochSec: Long,
    val scheduledArrivalEpochSec: Long = 0,
)

/** The immutable view the Swift screen renders. [step] is the reported four-value machine state:
 *  walk, ride, transfer or done. [cue] is "two_before", "stop" or empty. */
data class TransitGoState(
    val active: Boolean,
    val destinationName: String,
    val step: String,
    val phase: String,
    val legIndex: Int,
    val action: String,
    val detail: String,
    val line: String,
    val colorHex: String,
    val textColorHex: String,
    val direction: String,
    val targetName: String,
    val stopIndex: Int,
    val stopsRemaining: Int,
    val stops: List<TransitGoStop>,
    val countdownEpochSec: Long,
    val countdownKind: String,
    val scheduledOnly: Boolean,
    val estimated: Boolean,
    val stale: Boolean,
    val offline: Boolean,
    val fetchedAtEpochSec: Long,
    val cue: String,
    val cueText: String,
    val cueSerial: Int,
    val canBoard: Boolean,
    val canSkip: Boolean,
    val canAdvanceStop: Boolean,
    val progress: Double,
    val estimatedFraction: Double,
    val estimatedFromStop: String,
    val estimatedToStop: String,
    val overallArrivalEpochSec: Long,
) {
    /** The countdown is computed from the target epoch and the caller's clock. No request, no
     *  recomputation of the timetable, and the wording never implies a measurement. */
    fun countdownText(nowEpochSec: Long): String {
        // At the alight stop the position is the fact; a feed arrival still five minutes away
        // must not contradict the get-off action.
        if (stopsRemaining == 0 && countdownKind == "arrival") return "now"
        if (countdownEpochSec <= 0) return "No time"
        val diff = countdownEpochSec - nowEpochSec
        val prefix = if (countdownKind == "arrival") "arriving" else "departing"
        return when {
            diff in -30..30 -> "now"
            diff < 0 -> if (countdownKind == "arrival") "arrival time passed" else "departure time passed"
            diff < 60 -> "$prefix in <1 min"
            else -> "$prefix in ${(diff + 59) / 60} min"
        }
    }

    /** "Live" only when the displayed target is the feed's estimate. Stale, offline and
     *  timetable-only states say "Scheduled"; a leg without any time says "No time". */
    val timeLabel: String
        get() = when {
            countdownEpochSec <= 0 -> "No time"
            estimated -> "Live"
            else -> "Scheduled"
        }

    val positionLabel: String
        get() = if (estimatedFraction >= 0) "Estimated" else ""

    val debugLine: String
        get() = "go_step=$step go_estimated=${if (estimated) 1 else 0}" +
            " go_cue=${if (cue.isEmpty()) "none" else "stop"} go_cue_at=${cue.ifEmpty { "none" }}" +
            " go_stale=${if (stale) 1 else 0} go_offline=${if (offline) 1 else 0}" +
            " go_live=${if (estimated || !scheduledOnly) 1 else 0}" +
            " go_stops=$stopsRemaining go_cue_serial=$cueSerial"
}

/**
 * The GO step machine. It owns only the sequence of walk, wait, ride and done; locations and the
 * ride's stop index may be pushed from the shared TransitSession, and every control stays usable
 * without that session. It never invents a time: a ride without feed times keeps countdown 0 and
 * the get-off cue stays silent.
 */
class TransitGoMachine(
    private val plan: TransitGoPlan,
    private var networkAvailable: Boolean = true,
) {
    private var legIndex = 0
    private var phase = initialPhase()
    private var stopIndex = 0
    private var ended = false
    private var twoBeforeCued = false
    private var stopCued = false
    private var cueSerial = 0
    private var activeCue = ""

    init {
        resetCues()
    }

    /** The shared session's leg/stop position. It may only move forward. */
    fun sync(legIndex: Int, passedStops: Int, boarded: Boolean, arrived: Boolean) {
        if (ended || plan.legs.isEmpty()) return
        if (arrived) {
            ended = true
            phase = PHASE_DONE
            activeCue = ""
            return
        }
        val external = legIndex.coerceIn(0, plan.legs.lastIndex)
        if (external > this.legIndex) {
            this.legIndex = external
            phase = phaseOf(external)
            stopIndex = 0
            resetCues()
        }
        if (external < this.legIndex) return
        if (phase == PHASE_WAIT && boarded) {
            phase = PHASE_RIDE
            stopIndex = 0
        }
        if (phase == PHASE_RIDE) {
            val last = rideStops().lastIndex
            if (last >= 0 && passedStops > stopIndex) stopIndex = passedStops.coerceAtMost(last)
        }
    }

    fun board() {
        if (ended || phase != PHASE_WAIT) return
        phase = PHASE_RIDE
        stopIndex = 0
        resetCues()
    }

    /** Debug and VoiceOver action: one stop forward without a location fix. */
    fun advanceStop() {
        if (ended || phase != PHASE_RIDE) return
        val last = rideStops().lastIndex
        if (last < 0 || stopIndex >= last) {
            enterLeg(legIndex + 1)
        } else {
            stopIndex += 1
        }
    }

    /** Skips the current walk or wait, or leaves the current ride at its next step. */
    fun skipStep() {
        if (ended) return
        when (phase) {
            PHASE_WALK -> enterLeg(legIndex + 1)
            PHASE_WAIT -> board()
            PHASE_RIDE -> enterLeg(legIndex + 1)
        }
    }

    fun end() {
        ended = true
        activeCue = ""
    }

    fun setNetworkAvailable(available: Boolean) {
        networkAvailable = available
    }

    fun snapshot(nowEpochSec: Long): TransitGoState {
        if (ended || plan.legs.isEmpty()) {
            return TransitGoState(
                active = false,
                destinationName = plan.destinationName,
                step = "done",
                phase = PHASE_DONE,
                legIndex = if (plan.legs.isEmpty()) -1 else legIndex,
                action = if (plan.destinationName.isBlank()) "Trip complete"
                else "You have arrived at ${plan.destinationName}",
                detail = "",
                line = "", colorHex = "", textColorHex = "", direction = "", targetName = "",
                stopIndex = -1, stopsRemaining = -1, stops = emptyList(),
                countdownEpochSec = 0, countdownKind = "", scheduledOnly = true,
                estimated = false, stale = false, offline = !networkAvailable,
                fetchedAtEpochSec = plan.fetchedAtEpochSec, cue = "", cueText = "",
                cueSerial = cueSerial, canBoard = false, canSkip = false, canAdvanceStop = false,
                progress = 1.0, estimatedFraction = -1.0,
                estimatedFromStop = "", estimatedToStop = "",
                overallArrivalEpochSec = plan.scheduledArrivalEpochSec,
            )
        }
        val leg = plan.legs[legIndex]
        val stale = isStale(nowEpochSec)
        val liveAllowed = plan.liveData && !stale && networkAvailable
        val stops = if (phase == PHASE_RIDE) leg.stops else emptyList()
        val lastStop = leg.stops.lastIndex
        val remaining = if (phase == PHASE_RIDE && lastStop >= 0) lastStop - stopIndex else -1
        evaluateCue(leg, remaining, stale)
        val countdown = countdown(leg, phase, liveAllowed)
        val position = estimatedPosition(leg, nowEpochSec, liveAllowed)
        val step = reportedStep()
        val action = actionText(leg, phase, remaining)
        return TransitGoState(
            active = true,
            destinationName = plan.destinationName,
            step = step,
            phase = phase,
            legIndex = legIndex,
            action = action.first,
            detail = action.second,
            line = if (leg.kind == KIND_RIDE) leg.line else "",
            colorHex = if (leg.kind == KIND_RIDE) leg.colorHex else "",
            textColorHex = if (leg.kind == KIND_RIDE) leg.textColorHex else "",
            direction = if (leg.kind == KIND_RIDE) leg.direction else "",
            targetName = leg.toName,
            stopIndex = if (phase == PHASE_RIDE) stopIndex else -1,
            stopsRemaining = remaining,
            stops = stops,
            countdownEpochSec = countdown.first,
            countdownKind = countdown.second,
            scheduledOnly = !liveAllowed,
            estimated = countdown.third,
            stale = stale,
            offline = !networkAvailable,
            fetchedAtEpochSec = plan.fetchedAtEpochSec,
            cue = if (stale) "" else activeCue,
            cueText = if (stale) "" else cueText(leg, remaining),
            cueSerial = cueSerial,
            canBoard = phase == PHASE_WAIT,
            canSkip = phase == PHASE_WALK || phase == PHASE_WAIT || phase == PHASE_RIDE,
            canAdvanceStop = phase == PHASE_RIDE,
            progress = progress(),
            estimatedFraction = position.first,
            estimatedFromStop = position.second,
            estimatedToStop = position.third,
            overallArrivalEpochSec = plan.scheduledArrivalEpochSec,
        )
    }

    private fun initialPhase(): String = phaseOf(0)

    private fun phaseOf(index: Int): String {
        val leg = plan.legs.getOrNull(index) ?: return PHASE_DONE
        return if (leg.kind == KIND_RIDE) PHASE_WAIT else PHASE_WALK
    }

    private fun rideStops(): List<TransitGoStop> =
        plan.legs.getOrNull(legIndex)?.takeIf { it.kind == KIND_RIDE }?.stops.orEmpty()

    private fun enterLeg(index: Int) {
        if (index > plan.legs.lastIndex) {
            ended = true
            phase = PHASE_DONE
            activeCue = ""
            return
        }
        legIndex = index
        phase = phaseOf(index)
        stopIndex = 0
        resetCues()
    }

    private fun resetCues() {
        twoBeforeCued = false
        stopCued = false
        activeCue = ""
    }

    private fun reportedStep(): String = when (phase) {
        PHASE_DONE -> "done"
        PHASE_RIDE -> "ride"
        else -> if (rideBefore(legIndex)) "transfer" else "walk"
    }

    private fun rideBefore(index: Int): Boolean =
        plan.legs.take(index).any { it.kind == KIND_RIDE }

    private fun isStale(nowEpochSec: Long): Boolean {
        if (plan.fetchedAtEpochSec > 0 && nowEpochSec - plan.fetchedAtEpochSec > STALE_AFTER_SEC) {
            return true
        }
        val end = plan.legs.lastOrNull()?.scheduledArrivalEpochSec ?: 0
        return end > 0 && nowEpochSec > end + STALE_END_GRACE_SEC && phase != PHASE_DONE
    }

    /** Estimated only from the feed's own adjacent live times; null outside that window. */
    private fun estimatedPosition(
        leg: TransitGoLeg,
        nowEpochSec: Long,
        liveAllowed: Boolean,
    ): Triple<Double, String, String> {
        if (!liveAllowed || phase != PHASE_RIDE || leg.stops.size < 2) return Triple(-1.0, "", "")
        for (index in leg.stops.indices) {
            val from = leg.stops[index]
            val to = leg.stops.getOrNull(index + 1) ?: continue
            if (index < stopIndex) continue
            if (from.estimatedEpochSec <= 0 || to.estimatedEpochSec <= 0) continue
            if (nowEpochSec in from.estimatedEpochSec..to.estimatedEpochSec) {
                val span = to.estimatedEpochSec - from.estimatedEpochSec
                val fraction = if (span <= 0) 0.0
                else (nowEpochSec - from.estimatedEpochSec).toDouble() / span
                return Triple(fraction.coerceIn(0.0, 1.0), from.name, to.name)
            }
        }
        return Triple(-1.0, "", "")
    }

    private fun countdown(
        leg: TransitGoLeg,
        phase: String,
        liveAllowed: Boolean,
    ): Triple<Long, String, Boolean> {
        if (phase == PHASE_WALK || phase == PHASE_DONE) return Triple(0, "", false)
        val scheduled: Long
        val estimated: Long
        val kind: String
        if (phase == PHASE_WAIT) {
            scheduled = leg.scheduledDepartureEpochSec
            estimated = leg.estimatedDepartureEpochSec
            kind = "departure"
        } else {
            scheduled = leg.scheduledArrivalEpochSec
            estimated = leg.estimatedArrivalEpochSec
            kind = "arrival"
        }
        if (liveAllowed && estimated > 0) return Triple(estimated, kind, true)
        if (scheduled > 0) return Triple(scheduled, kind, false)
        return Triple(0, kind, false)
    }

    /** One cue at two stops before the alight, one at the alight. A leg the feed left without
     *  times stays silent, and a stale itinerary cannot announce a stop it no longer knows. */
    private fun evaluateCue(leg: TransitGoLeg, remaining: Int, stale: Boolean) {
        if (phase != PHASE_RIDE || stale || !leg.timed || leg.stops.size < 2) {
            if (phase != PHASE_RIDE) activeCue = ""
            return
        }
        if (remaining == 2 && !twoBeforeCued) {
            twoBeforeCued = true
            activeCue = "two_before"
            cueSerial += 1
        } else if (remaining == 0 && !stopCued) {
            stopCued = true
            activeCue = "stop"
            cueSerial += 1
        }
    }

    private fun cueText(leg: TransitGoLeg, remaining: Int): String = when (activeCue) {
        "two_before" -> if (remaining <= 1) {
            "Get off at the next stop at ${leg.toName}"
        } else {
            "Get off in two stops at ${leg.toName}"
        }
        "stop" -> "Get off now at ${leg.toName}"
        else -> ""
    }

    private fun actionText(leg: TransitGoLeg, phase: String, remaining: Int): Pair<String, String> {
        if (phase == PHASE_WALK) {
            val target = if (leg.toName.isBlank() || leg.toName == plan.destinationName) "the destination"
            else leg.toName
            val walk = if (leg.durationMinutes > 0) "Walk ${leg.durationMinutes} min to $target"
            else "Walk to $target"
            val transfer = rideBefore(legIndex)
            return (if (transfer) "Transfer: ${walk.replaceFirstChar { it.lowercase() }}" else walk) to ""
        }
        if (phase == PHASE_WAIT) {
            val line = leg.line.ifBlank { "the next service" }
            val action = if (leg.direction.isBlank()) "Take $line"
            else "Take $line towards ${leg.direction}"
            return action to if (leg.fromName.isBlank()) "" else "at ${leg.fromName}"
        }
        if (phase == PHASE_RIDE) {
            val alight = leg.toName.ifBlank { "your stop" }
            val action = when {
                remaining <= 0 -> "Get off now at $alight"
                remaining == 1 -> "Get off at $alight at the next stop"
                else -> "Get off at $alight in $remaining stops"
            }
            val detail = if (leg.direction.isBlank()) "" else "towards ${leg.direction}"
            return action to detail
        }
        return "Trip complete" to ""
    }

    private fun progress(): Double {
        if (ended) return 1.0
        if (plan.legs.isEmpty()) return 1.0
        val leg = plan.legs.getOrNull(legIndex)
        val fraction = if (leg != null && leg.kind == KIND_RIDE && leg.stops.size > 1) {
            stopIndex.toDouble() / leg.stops.lastIndex
        } else {
            0.0
        }
        return ((legIndex + fraction) / plan.legs.size).coerceIn(0.0, 1.0)
    }

    companion object {
        const val KIND_WALK = "WALK"
        const val KIND_RIDE = "RIDE"
        const val PHASE_WALK = "WALK"
        const val PHASE_WAIT = "WAIT"
        const val PHASE_RIDE = "RIDE"
        const val PHASE_DONE = "DONE"
        /** A plan older than this is kept but loses every live claim. */
        const val STALE_AFTER_SEC = 2 * 60 * 60L
        /** A plan whose last arrival is this far behind is stale even inside the age window. */
        const val STALE_END_GRACE_SEC = 30 * 60L
    }
}

/** Builds a GO plan from the selected itinerary. Stops and times come only from its own fields;
 *  duration text supplies the walk minutes, and an unreadable clock time becomes 0. */
object TransitGoPlanBuilder {
    fun fromItinerary(
        trip: TransitItinerary,
        destinationName: String,
        fetchedAtEpochSec: Long,
        liveData: Boolean,
    ): TransitGoPlan {
        val zone = TimeZone.currentSystemDefault()
        val anchor = trip.departureEpochSec ?: fetchedAtEpochSec
        var lastEpoch = anchor
        val legs = trip.steps.mapIndexed { index, step ->
            if (step.mode == TransitMode.WALK) {
                val nextRide = trip.steps.drop(index + 1).firstOrNull { it.line != null }
                val previousRide = trip.steps.take(index).lastOrNull { it.line != null }
                val to = nextRide?.boardStop?.name ?: destinationName
                TransitGoLeg(
                    kind = TransitGoMachine.KIND_WALK,
                    fromName = previousRide?.alightStop?.name ?: "",
                    toName = to,
                    durationMinutes = minutes(step.durationText),
                )
            } else {
                val board = step.boardStop
                val alight = step.alightStop
                val stopList = listOfNotNull(board) + step.intermediateStops + listOfNotNull(alight)
                val stops = stopList.map { stop ->
                    val scheduled = clockEpoch(stop.scheduledText ?: stop.timeText, anchor, zone)
                    val estimated = if (stop.delayMin != null || stop.scheduledText != null) {
                        clockEpoch(stop.timeText, anchor, zone)
                    } else {
                        0
                    }
                    TransitGoStop(stop.name, scheduled, estimated)
                }
                val departureText = board?.scheduledText ?: board?.timeText ?: step.departText
                val scheduledDeparture = clockEpoch(
                    board?.scheduledText ?: board?.timeText ?: step.departText, anchor, zone)
                val estimatedDeparture = if (board?.delayMin != null || board?.scheduledText != null) {
                    clockEpoch(board?.timeText ?: step.departText, anchor, zone)
                } else {
                    0
                }
                val scheduledArrival = clockEpoch(
                    alight?.scheduledText ?: alight?.timeText ?: step.arriveText, anchor, zone)
                val estimatedArrival = if (alight?.delayMin != null || alight?.scheduledText != null) {
                    clockEpoch(alight?.timeText ?: step.arriveText, anchor, zone)
                } else {
                    0
                }
                if (scheduledDeparture > 0) lastEpoch = maxOf(lastEpoch, scheduledDeparture)
                TransitGoLeg(
                    kind = TransitGoMachine.KIND_RIDE,
                    line = step.line?.name.orEmpty(),
                    colorHex = step.line?.colorHex ?: step.mode.defaultColorHex,
                    textColorHex = step.line?.textColorHex.orEmpty(),
                    direction = step.headsign.orEmpty(),
                    fromName = board?.name.orEmpty(),
                    toName = alight?.name.orEmpty(),
                    durationMinutes = minutes(step.durationText),
                    scheduledDepartureEpochSec = scheduledDeparture,
                    estimatedDepartureEpochSec = estimatedDeparture,
                    scheduledArrivalEpochSec = scheduledArrival,
                    estimatedArrivalEpochSec = estimatedArrival,
                    stops = stops,
                    stopCount = step.numStops ?: stops.size,
                    timed = stops.any { it.scheduledEpochSec > 0 || it.estimatedEpochSec > 0 } ||
                        scheduledDeparture > 0 || scheduledArrival > 0,
                    departureClockText = departureText.orEmpty(),
                )
            }
        }
        return TransitGoPlan(
            destinationName = destinationName,
            legs = legs,
            liveData = liveData,
            fetchedAtEpochSec = fetchedAtEpochSec,
            scheduledArrivalEpochSec = trip.arrivalEpochSec ?: lastEpoch,
        )
    }

    private fun minutes(text: String?): Int {
        if (text.isNullOrBlank()) return 0
        val value = Regex("""(\d+)""").find(text)?.groupValues?.get(1)?.toIntOrNull() ?: return 0
        return value.coerceIn(0, 24 * 60)
    }

    /** A printed clock time anchored to the itinerary's day in the device zone. Out-of-order
     *  hours across midnight are shifted by a day rather than treated as a negative countdown. */
    private fun clockEpoch(text: String?, anchorEpochSec: Long, zone: TimeZone): Long {
        if (text.isNullOrBlank() || anchorEpochSec <= 0) return 0
        val match = Regex("""(\d{1,2}):(\d{2})\s*([AaPp][Mm])?""").find(text) ?: return 0
        var hour = match.groupValues[1].toIntOrNull() ?: return 0
        val minute = match.groupValues[2].toIntOrNull() ?: return 0
        if (minute !in 0..59) return 0
        val suffix = match.groupValues[3].uppercase()
        if (suffix == "PM" && hour < 12) hour += 12
        if (suffix == "AM" && hour == 12) hour = 0
        if (hour !in 0..23) return 0
        val day = Instant.fromEpochSeconds(anchorEpochSec).toLocalDateTime(zone).date
        var epoch = LocalDateTime(day.year, day.month, day.day, hour, minute)
            .toInstant(zone).epochSeconds
        if (epoch - anchorEpochSec > 12 * 60 * 60) epoch -= 24 * 60 * 60
        if (anchorEpochSec - epoch > 12 * 60 * 60) epoch += 24 * 60 * 60
        return epoch
    }
}

/**
 * Deterministic GO fixture used by the Debug UI scenario. The stops and line are the M2 eastbound
 * ones; every epoch is relative to the launch clock, so the countdown and the estimated position
 * exercise the real path without a network request. Times are still marked live only because the
 * fixture sets live fields, exactly as a live plan would.
 */
object TransitGoFixtures {
    fun paris(nowEpochSec: Long, live: Boolean = true, fetchedAtEpochSec: Long = nowEpochSec): TransitGoPlan {
        val board = nowEpochSec - 300
        val first = nowEpochSec - 60
        val alight = nowEpochSec + 300
        val walkToStop = TransitGoLeg(
            kind = TransitGoMachine.KIND_WALK,
            toName = "République",
            durationMinutes = 4,
        )
        val ride = TransitGoLeg(
            kind = TransitGoMachine.KIND_RIDE,
            line = "M2",
            colorHex = "#1f6fb2",
            textColorHex = "#FFFFFF",
            direction = "Nation",
            fromName = "République",
            toName = "Belleville",
            durationMinutes = 6,
            scheduledDepartureEpochSec = if (live) board - 120 else board,
            estimatedDepartureEpochSec = if (live) board else 0,
            scheduledArrivalEpochSec = if (live) alight - 120 else alight,
            estimatedArrivalEpochSec = if (live) alight else 0,
            stops = listOf(
                TransitGoStop("République", board - 120, if (live) board else 0),
                TransitGoStop("Colonel Fabien", first - 120, if (live) first else 0),
                TransitGoStop("Belleville", alight - 120, if (live) alight else 0),
            ),
            stopCount = 2,
            timed = true,
            // Only the anchor match reads this text; the fixture's countdown still comes from the
            // relative epochs above.
            departureClockText = "10:15",
        )
        val walkToDestination = TransitGoLeg(
            kind = TransitGoMachine.KIND_WALK,
            toName = "the destination",
            durationMinutes = 2,
        )
        return TransitGoPlan(
            destinationName = "Belleville",
            legs = listOf(walkToStop, ride, walkToDestination),
            liveData = live,
            fetchedAtEpochSec = fetchedAtEpochSec,
            scheduledArrivalEpochSec = alight + 120,
        )
    }
}
