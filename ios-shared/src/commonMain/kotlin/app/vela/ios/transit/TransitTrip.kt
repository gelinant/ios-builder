package app.vela.ios.transit

import app.vela.core.model.StopDeparture
import app.vela.core.model.StopDepartureLine
import app.vela.core.model.StopDepartures
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.TransitStopTime

/** The ride card kind, shared by [TransitTripSegment] and the [TransitTrip] constants below. */
private const val RIDE_KIND = "RIDE"

/**
 * One card of the trip screen: a walk, a wait, a ride or a transfer. Every field comes from the
 * selected Transitous itinerary. A ride is [live] only when the feed carried a realtime field for
 * one of its stops; nothing here is inferred.
 */
data class TransitTripSegment(
    val index: Int,
    /** The index of the itinerary step this card describes; two cards can share one step (a wait). */
    val stepIndex: Int,
    val kind: String,
    val lineLabel: String?,
    val lineColor: String?,
    val lineTextColor: String?,
    val mode: String,
    val direction: String?,
    val boardName: String?,
    val alightName: String?,
    val boardCode: String?,
    val alightCode: String?,
    val scheduledDeparture: String?,
    val estimatedDeparture: String?,
    val scheduledArrival: String?,
    val estimatedArrival: String?,
    val delayMinutes: Int?,
    val durationText: String?,
    val distanceText: String?,
    val stopCount: Int,
    val boardLat: Double?,
    val boardLng: Double?,
    val alightLat: Double?,
    val alightLng: Double?,
    /** The departure a wait card counts down to, as the feed wrote it. */
    val waitUntil: String?,
    /** The planner's own mode name for a ride ("REGIONAL_RAIL", "COACH"...), null when it gave none. */
    val modeName: String? = null,
    /** The leg's own operator when the planner named one per leg, so a transfer reads "RER B". */
    val agencyName: String? = null,
    /** On a wait card, the planned minutes between the previous arrival and this departure. */
    val waitMinutes: Int? = null,
) {
    /** A ride is live only when a stop carried the realtime pair Transitous supplies. */
    val live: Boolean get() = estimatedDeparture != null || estimatedArrival != null

    /** Only a ride can be let pass; a walk and a wait have no run of their own. */
    val skippable: Boolean get() = kind == RIDE_KIND

    /** The time the feed shows at the boarding stop, if it supplied one. */
    val shownDeparture: String? get() = estimatedDeparture ?: scheduledDeparture

    /** Whether the feed gave the boarding stop's coordinate, so a board can be asked for it. */
    val hasBoardPoint: Boolean get() = boardLat != null && boardLng != null
}

/** One departure in the header above the cards. [minutes] is a snapshot; Swift recounts it. */
data class TransitTripDeparture(
    val clockText: String?,
    val epochSec: Long,
    val realtime: Boolean,
    val minutes: Int,
    val tripId: String?,
)

/** The next departures of the selected ride's line at its boarding stop. */
data class TransitTripHeader(
    val stopName: String?,
    val lineLabel: String?,
    val direction: String?,
    val departures: List<TransitTripDeparture> = emptyList(),
    /** False when the feed did not answer for that stop; an empty list with true means no run. */
    val available: Boolean = false,
    /** The line's own fill color from Transitous, for its badge. */
    val lineColor: String? = null,
)

/** One line of the nearby tab; [departures] is already filtered to runs still ahead. */
data class TransitNearbyLine(
    val label: String?,
    val mode: String,
    val headsign: String?,
    val color: String?,
    val headwayText: String?,
    val departures: List<TransitTripDeparture>,
)

/** One trip of a new option set returned by the planner after a time change. */
data class TransitTripOption(
    val index: Int,
    val departureText: String?,
    val arrivalText: String?,
    val durationText: String?,
    val lines: List<String>,
    val live: Boolean,
    /** The whole trip's mode names in travel order, walks included, for the row's glyph sequence. */
    val modeNames: List<String> = emptyList(),
)

/** Where a segment time change starts from, and the query it asks the planner. */
data class TransitTripShift(
    val segmentIndex: Int,
    val stepIndex: Int,
    val timeMode: Int,
    val epochSec: Long,
    val anchorEpochSec: Long,
    /** `board` (the stop's own departure), `trip_start` or `trip_end`. */
    val anchorSource: String,
    val lineLabel: String?,
    val stopName: String?,
)

/** The next run of the same line after the one being let pass. */
data class TransitTripSkip(
    val segmentIndex: Int,
    val lineLabel: String,
    val epochSec: Long,
    val clockText: String?,
    val realtime: Boolean,
    val minutes: Int,
    /** The run that was let pass, so the header can start at the next one. */
    val passedEpochSec: Long,
)

/**
 * The trip screen's mapping, pure so it runs in JVM tests and cannot drift from the board. It reads
 * only what Transitous returned: no line, time or delay is constructed when the feed lacks it.
 */
object TransitTrip {
    const val KIND_WALK = "WALK"
    const val KIND_WAIT = "WAIT"
    const val KIND_RIDE = RIDE_KIND
    const val KIND_TRANSFER = "TRANSFER"

    /** Same numbering as [TransitPlanQuery]: depart at a time, arrive by a time. */
    const val SHIFT_DEPART_AT = 1
    const val SHIFT_ARRIVE_BY = 2

    private const val HEADER_DEPARTURES = 4
    private const val NEARBY_DEPARTURES = 3
    private const val PAST_GRACE_SEC = 60L

    /**
     * The itinerary as cards, in travel order. A wait card sits before every ride but the first
     * step, and a walk between two rides is a transfer. Intermediate stops stay on the ride's own
     * stop list in the detail sheet.
     */
    fun segmentsOf(trip: TransitItinerary): List<TransitTripSegment> {
        val out = ArrayList<TransitTripSegment>()
        var ridesSeen = 0
        trip.steps.forEachIndexed { stepIndex, step ->
            if (step.mode == TransitMode.WALK) {
                val ride = nextRide(trip.steps, stepIndex)
                val kind = if (ridesSeen > 0 && ride != null) KIND_TRANSFER else KIND_WALK
                out += walkSegment(out.size, stepIndex, kind, step, ride)
            } else {
                val board = step.boardStop
                val shown = times(step.departText, board).second ?: times(step.departText, board).first
                if (out.isNotEmpty()) {
                    val previous = trip.steps.getOrNull(stepIndex - 1)
                    val departure = step.departEpochSec
                    val arrival = previous?.arriveEpochSec
                    val minutes = if (departure != null && arrival != null) {
                        ((departure - arrival) / 60).toInt().coerceAtLeast(0)
                    } else {
                        null
                    }
                    out += waitSegment(out.size, stepIndex, board, shown, minutes)
                }
                out += rideSegment(out.size, stepIndex, step)
                ridesSeen += 1
            }
        }
        return out
    }

    /**
     * Next departures of [segment]'s own line at its boarding stop. [board] is the feed's answer for
     * that stop, or null when it did not answer. A line the feed does not serve stays absent: an
     * unmatched line returns an empty list, never a guessed time.
     */
    fun header(board: StopDepartures?, segment: TransitTripSegment?, nowSec: Long): TransitTripHeader {
        if (segment == null) {
            return TransitTripHeader(stopName = null, lineLabel = null, direction = null)
        }
        if (board == null) {
            return TransitTripHeader(
                stopName = segment.boardName,
                lineLabel = segment.lineLabel,
                direction = segment.direction,
            )
        }
        val line = pickLine(board.lines, segment)
        return TransitTripHeader(
            stopName = board.stationName ?: segment.boardName,
            lineLabel = line?.label ?: segment.lineLabel,
            direction = line?.headsign ?: segment.direction,
            departures = line?.let { rows(it, nowSec, HEADER_DEPARTURES) }.orEmpty(),
            available = true,
            lineColor = line?.colorHex ?: segment.lineColor,
        )
    }

    /** The same header with the passed run removed, so the next departure of the line shows. */
    fun withoutDeparture(header: TransitTripHeader, epochSec: Long): TransitTripHeader =
        header.copy(departures = header.departures.filter { it.epochSec > epochSec })

    /** Every line the feed lists at this stop, with the runs still ahead. Lines without one stay out. */
    fun nearby(board: StopDepartures?, nowSec: Long): List<TransitNearbyLine> = board?.lines.orEmpty()
        .mapNotNull { line ->
            val departures = rows(line, nowSec, NEARBY_DEPARTURES)
            if (departures.isEmpty()) {
                null
            } else {
                TransitNearbyLine(
                    label = line.label?.takeIf { it.isNotBlank() },
                    mode = line.mode.name,
                    headsign = line.headsign?.takeIf { it.isNotBlank() },
                    color = line.colorHex,
                    headwayText = line.headwayText?.takeIf { it.isNotBlank() },
                    departures = departures,
                )
            }
        }

    /**
     * The planner query for a time change on [segment].
     *
     * - Leave later on a ride anchors on the departure the feed lists for that line at that stop,
     *   matched by its clock text. A first segment falls back to the itinerary's own start; any
     *   other segment without a match returns null rather than guess an hour.
     * - Arrive by is only expressible at the destination (`/api/v1/plan` has no per-stop arrival
     *   constraint), so only the last segment accepts it, anchored on the itinerary's arrival.
     */
    fun shift(
        trip: TransitItinerary,
        segment: TransitTripSegment,
        header: TransitTripHeader,
        mode: Int,
        deltaMinutes: Int,
    ): TransitTripShift? {
        if (mode != SHIFT_DEPART_AT && mode != SHIFT_ARRIVE_BY) return null
        val last = segment.stepIndex == trip.steps.lastIndex
        val delta = deltaMinutes.toLong() * 60L
        if (mode == SHIFT_ARRIVE_BY) {
            val arrival = trip.arrivalEpochSec ?: return null
            if (!last) return null
            return TransitTripShift(
                segmentIndex = segment.index, stepIndex = segment.stepIndex,
                timeMode = SHIFT_ARRIVE_BY, epochSec = arrival + delta,
                anchorEpochSec = arrival, anchorSource = "trip_end",
                lineLabel = segment.lineLabel, stopName = segment.alightName,
            )
        }
        val shown = segment.shownDeparture
        val match = header.departures.firstOrNull { shown != null && it.clockText == shown }
        val anchor = match?.epochSec ?: trip.departureEpochSec?.takeIf { segment.stepIndex == 0 }
        val source = if (match != null) "board" else "trip_start"
        if (anchor == null) return null
        return TransitTripShift(
            segmentIndex = segment.index, stepIndex = segment.stepIndex,
            timeMode = SHIFT_DEPART_AT, epochSec = anchor + delta,
            anchorEpochSec = anchor, anchorSource = source,
            lineLabel = segment.lineLabel, stopName = segment.boardName,
        )
    }

    /** The run after the one [segment] rides, same line, from the header's own departures. */
    fun skip(header: TransitTripHeader, segment: TransitTripSegment): TransitTripSkip? {
        if (!segment.skippable) return null
        val shown = segment.shownDeparture
        val current = header.departures.firstOrNull { shown != null && it.clockText == shown }
            ?: header.departures.firstOrNull()
            ?: return null
        val next = header.departures.firstOrNull { it.epochSec > current.epochSec } ?: return null
        return TransitTripSkip(
            segmentIndex = segment.index,
            lineLabel = segment.lineLabel.orEmpty(),
            epochSec = next.epochSec,
            clockText = next.clockText,
            realtime = next.realtime,
            minutes = next.minutes,
            passedEpochSec = current.epochSec,
        )
    }

    /**
     * The same header built from the store's mapped board, which is what production observes. The
     * store already dropped past runs; this only keeps the trip's own line and direction.
     */
    fun header(state: TransitBoardState, segment: TransitTripSegment?): TransitTripHeader {
        if (segment == null) {
            return TransitTripHeader(stopName = null, lineLabel = null, direction = null)
        }
        val line = pickMappedLine(state.lines, segment)
        return TransitTripHeader(
            stopName = state.stopName.takeIf { it.isNotBlank() } ?: segment.boardName,
            lineLabel = line?.label ?: segment.lineLabel,
            direction = line?.headsign ?: segment.direction,
            departures = line?.departures.orEmpty().map(::mappedDeparture).take(HEADER_DEPARTURES),
            available = true,
            lineColor = line?.color ?: segment.lineColor,
        )
    }

    /** The nearby tab built from the store's mapped board; empty lines stay out. */
    fun nearby(state: TransitBoardState): List<TransitNearbyLine> = state.lines.mapNotNull { line ->
        val departures = line.departures.map(::mappedDeparture).take(NEARBY_DEPARTURES)
        if (departures.isEmpty()) {
            null
        } else {
            TransitNearbyLine(
                label = line.label,
                mode = line.mode,
                headsign = line.headsign,
                color = line.color,
                headwayText = null,
                departures = departures,
            )
        }
    }

    /** A departure query anchored on the run the user chose to take after letting one pass. */
    fun shiftTo(trip: TransitItinerary, segment: TransitTripSegment, epochSec: Long): TransitTripShift =
        TransitTripShift(
            segmentIndex = segment.index, stepIndex = segment.stepIndex,
            timeMode = SHIFT_DEPART_AT, epochSec = epochSec,
            anchorEpochSec = epochSec, anchorSource = "skip",
            lineLabel = segment.lineLabel, stopName = segment.boardName,
        )

    /** A new option set as rows. The current trip is never rewritten from these. */
    fun options(trips: List<TransitItinerary>): List<TransitTripOption> = trips.take(5).mapIndexed { index, trip ->
        TransitTripOption(
            index = index,
            departureText = trip.departureText,
            arrivalText = trip.arrivalText,
            durationText = trip.durationText,
            lines = trip.lines.mapNotNull { it.name.takeIf { name -> name.isNotBlank() } },
            live = trip.steps.any { step ->
                step.boardStop?.let { it.delayMin != null || it.scheduledText != null } == true ||
                    step.alightStop?.let { it.delayMin != null || it.scheduledText != null } == true
            },
            // The whole trip in travel order, so a row shows "Walk · M1 · RER A · Walk".
            modeNames = trip.steps.map { it.mode.name },
        )
    }

    private fun walkSegment(
        index: Int,
        stepIndex: Int,
        kind: String,
        step: TransitStep,
        ride: TransitStep?,
    ): TransitTripSegment = TransitTripSegment(
        index = index, stepIndex = stepIndex, kind = kind,
        lineLabel = null, lineColor = null, lineTextColor = null,
        mode = TransitMode.WALK.name, direction = null,
        boardName = null, alightName = ride?.boardStop?.name,
        boardCode = null, alightCode = ride?.boardStop?.code,
        scheduledDeparture = null, estimatedDeparture = null,
        scheduledArrival = null, estimatedArrival = null,
        delayMinutes = null,
        durationText = step.durationText, distanceText = step.distanceText,
        stopCount = -1,
        boardLat = step.walkFrom?.lat, boardLng = step.walkFrom?.lng,
        alightLat = step.walkTo?.lat, alightLng = step.walkTo?.lng,
        waitUntil = null, modeName = step.modeName,
    )

    private fun waitSegment(
        index: Int,
        stepIndex: Int,
        board: TransitStopTime?,
        until: String?,
        waitMinutes: Int?,
    ): TransitTripSegment = TransitTripSegment(
        index = index, stepIndex = stepIndex, kind = KIND_WAIT,
        lineLabel = null, lineColor = null, lineTextColor = null,
        mode = KIND_WAIT, direction = null,
        boardName = board?.name, alightName = board?.name,
        boardCode = board?.code, alightCode = board?.code,
        scheduledDeparture = until, estimatedDeparture = null,
        scheduledArrival = null, estimatedArrival = null,
        delayMinutes = null, durationText = null, distanceText = null, stopCount = -1,
        boardLat = board?.location?.lat, boardLng = board?.location?.lng,
        alightLat = board?.location?.lat, alightLng = board?.location?.lng,
        waitUntil = until, waitMinutes = waitMinutes,
    )

    private fun rideSegment(index: Int, stepIndex: Int, step: TransitStep): TransitTripSegment {
        val board = step.boardStop
        val alight = step.alightStop
        val departure = times(step.departText, board)
        val arrival = times(step.arriveText, alight)
        return TransitTripSegment(
            index = index, stepIndex = stepIndex, kind = KIND_RIDE,
            lineLabel = step.line?.name?.takeIf { it.isNotBlank() },
            lineColor = step.line?.colorHex,
            lineTextColor = step.line?.textColorHex,
            mode = step.line?.mode?.name ?: step.mode.name,
            direction = step.headsign?.takeIf { it.isNotBlank() },
            boardName = board?.name, alightName = alight?.name,
            boardCode = board?.code, alightCode = alight?.code,
            scheduledDeparture = departure.first, estimatedDeparture = departure.second,
            scheduledArrival = arrival.first, estimatedArrival = arrival.second,
            delayMinutes = board?.delayMin ?: alight?.delayMin,
            durationText = step.durationText, distanceText = null,
            stopCount = step.numStops ?: -1,
            boardLat = board?.location?.lat, boardLng = board?.location?.lng,
            alightLat = alight?.location?.lat, alightLng = alight?.location?.lng,
            waitUntil = null, modeName = step.modeName ?: step.line?.mode?.name,
            agencyName = step.agencyName,
        )
    }

    /** The timetable and the live time kept apart, exactly like the detail sheet and X-3. */
    private fun times(fallback: String?, stop: TransitStopTime?): Pair<String?, String?> {
        if (stop == null) return fallback to null
        val shown = stop.timeText ?: fallback
        val live = stop.delayMin != null || stop.scheduledText != null
        return if (live) (stop.scheduledText ?: fallback) to shown else shown to null
    }

    private fun nextRide(steps: List<TransitStep>, after: Int): TransitStep? =
        steps.drop(after + 1).firstOrNull { it.line != null }

    /** The board line of the trip's own direction; a direction-less board keeps its first match. */
    private fun pickLine(lines: List<StopDepartureLine>, segment: TransitTripSegment): StopDepartureLine? {
        val label = segment.lineLabel ?: return null
        val sameLine = lines.filter { it.label?.equals(label, ignoreCase = true) == true }
        if (sameLine.isEmpty()) return null
        val direction = segment.direction
        if (direction != null) {
            sameLine.firstOrNull { it.headsign?.equals(direction, ignoreCase = true) == true }
                ?.let { return it }
            sameLine.firstOrNull { it.headsign?.contains(direction, ignoreCase = true) == true }
                ?.let { return it }
            sameLine.firstOrNull { it.headsign?.let { heads -> direction.contains(heads, ignoreCase = true) } == true }
                ?.let { return it }
        }
        return sameLine.firstOrNull { it.headsign == null } ?: sameLine.first()
    }

    private fun mappedDeparture(departure: TransitBoardDeparture): TransitTripDeparture =
        TransitTripDeparture(
            clockText = departure.clockText,
            epochSec = departure.epochSec,
            realtime = departure.realtime,
            minutes = departure.minutes,
            tripId = departure.tripId,
        )

    private fun pickMappedLine(lines: List<TransitBoardLine>, segment: TransitTripSegment): TransitBoardLine? {
        val label = segment.lineLabel ?: return null
        val sameLine = lines.filter { it.label?.equals(label, ignoreCase = true) == true }
        if (sameLine.isEmpty()) return null
        val direction = segment.direction
        if (direction != null) {
            sameLine.firstOrNull { it.headsign?.equals(direction, ignoreCase = true) == true }
                ?.let { return it }
            sameLine.firstOrNull { it.headsign?.contains(direction, ignoreCase = true) == true }
                ?.let { return it }
        }
        return sameLine.first()
    }

    private fun rows(line: StopDepartureLine, nowSec: Long, limit: Int): List<TransitTripDeparture> =
        line.upcoming.mapNotNull { departure -> row(departure, nowSec) }
            .distinctBy { it.epochSec }
            .sortedBy { it.epochSec }
            .take(limit)

    private fun row(departure: StopDeparture, nowSec: Long): TransitTripDeparture? {
        val epoch = departure.epochSec ?: return null
        val seconds = epoch - nowSec
        if (seconds < -PAST_GRACE_SEC) return null
        return TransitTripDeparture(
            clockText = departure.clockText,
            epochSec = epoch,
            realtime = departure.realtime,
            minutes = if (seconds <= 0) 0 else ((seconds + 59) / 60).toInt(),
            tripId = departure.tripId,
        )
    }
}
