package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary
import app.vela.core.model.TransitMode
import app.vela.core.model.TransitStep
import app.vela.core.model.defaultColorHex
import app.vela.core.model.distanceTo

/** A latitude and longitude box. It never crosses the antimeridian: GO frames a city trip. */
data class TransitGoMapBox(val south: Double, val west: Double, val north: Double, val east: Double) {
    fun contains(point: LatLng): Boolean =
        point.lat in south..north && point.lng in west..east

    /** The same box shrunk by [fraction] of its span on each side: the safe area of a view. */
    fun inset(fraction: Double): TransitGoMapBox {
        val dLat = (north - south) * fraction
        val dLng = (east - west) * fraction
        return TransitGoMapBox(south + dLat, west + dLng, north - dLat, east - dLng)
    }

    /** The same box grown by [degrees] on each side. */
    fun grown(degrees: Double): TransitGoMapBox =
        TransitGoMapBox(south - degrees, west - degrees, north + degrees, east + degrees)

    companion object {
        fun around(points: List<LatLng>): TransitGoMapBox? {
            if (points.isEmpty()) return null
            return TransitGoMapBox(
                south = points.minOf { it.lat },
                west = points.minOf { it.lng },
                north = points.maxOf { it.lat },
                east = points.maxOf { it.lng },
            )
        }
    }
}

/**
 * What GO's map shows for one step. [target] is where the step ends: the walk's end, the
 * boarding stop, the alighting stop or the destination, named by [targetKind]. [leg] is the
 * current leg's polyline between the user and the target. [box] holds the user when
 * [usesUser], the target and [leg]; it is null when the itinerary has no coordinate at all.
 */
data class TransitGoMapFrame(
    val target: LatLng?,
    val targetKind: String,
    val leg: List<LatLng>,
    val box: TransitGoMapBox?,
    val usesUser: Boolean,
)

/** The line GO draws: the ride being ridden or waited for, or the next one when its boarding
 *  stop is close to the user. [path] is the feed's shape, else the chain of stops. */
data class TransitGoMapLine(
    val legIndex: Int,
    val label: String,
    val colorHex: String,
    val path: List<LatLng>,
    val boardStop: LatLng?,
)

/**
 * GO's map rules, kept pure so they are tested on the JVM. The machine's leg index matches the
 * itinerary's step index one to one (`TransitGoPlanBuilder`), so every coordinate comes from the
 * selected itinerary and none is invented.
 */
object TransitGoMap {
    const val KIND_WALK = "walk"
    const val KIND_BOARD = "board"
    const val KIND_ALIGHT = "alight"
    const val KIND_DESTINATION = "destination"
    const val KIND_NONE = "none"

    /** A boarding stop this close to the user brings its line and vehicles onto the map. */
    const val NEAR_LINE_METERS = 500.0

    /** A point closer than this share of the visible span to an edge triggers a refit. */
    const val SAFE_INSET = 0.08

    /** The smallest box side, about 300 m, so a target next to the user is not framed at z22. */
    const val MIN_SPAN_DEGREES = 0.003

    /** The margin around the line and the user for the vehicle request. */
    const val REQUEST_MARGIN_DEGREES = 0.005

    /** The step's end point and its kind. A walk ends at its `walkTo`, else at its path end. */
    fun target(trip: TransitItinerary, legIndex: Int, phase: String): Pair<LatLng?, String> {
        val steps = trip.steps
        if (phase == TransitGoMachine.PHASE_DONE || legIndex !in steps.indices) {
            return destination(trip) to KIND_DESTINATION
        }
        val step = steps[legIndex]
        if (step.line == null) {
            val last = steps.drop(legIndex + 1).none { it.line != null }
            val end = step.walkTo ?: step.path?.lastOrNull()
                ?: steps.drop(legIndex + 1).firstOrNull { it.line != null }?.boardStop?.location
            return if (last) (end ?: destination(trip)) to KIND_DESTINATION else end to KIND_WALK
        }
        return if (phase == TransitGoMachine.PHASE_RIDE) {
            (step.alightStop?.location ?: step.path?.lastOrNull()) to KIND_ALIGHT
        } else {
            (step.boardStop?.location ?: step.path?.firstOrNull()) to KIND_BOARD
        }
    }

    /** The current leg's polyline: the feed's path, else the walk's two ends or the stops. */
    fun legPath(trip: TransitItinerary, legIndex: Int): List<LatLng> {
        val step = trip.steps.getOrNull(legIndex) ?: return emptyList()
        return pathOf(step)
    }

    /**
     * The box to fit. With a fix it holds the user, the target and the leg between them; the leg
     * is cut at the vertex nearest the user, so the part already behind is not framed. Without a
     * fix it holds the target and the whole leg.
     */
    fun frame(trip: TransitItinerary, legIndex: Int, phase: String, user: LatLng?): TransitGoMapFrame {
        val (target, kind) = target(trip, legIndex, phase)
        val path = if (phase == TransitGoMachine.PHASE_DONE) emptyList() else legPath(trip, legIndex)
        val leg = if (phase == TransitGoMachine.PHASE_WAIT) emptyList() else between(path, user, target)
        val points = listOfNotNull(user, target) + leg
        return TransitGoMapFrame(
            target = target,
            targetKind = if (target == null) KIND_NONE else kind,
            leg = leg,
            box = TransitGoMapBox.around(points)?.let(::atLeastMinimum),
            usesUser = user != null,
        )
    }

    /** The part of [path] between the vertices nearest [user] and [target], in travel order. */
    fun between(path: List<LatLng>, user: LatLng?, target: LatLng?): List<LatLng> {
        if (path.size < 2) return path
        val start = if (user == null) 0 else TransitVehicles.nearestIndex(path, user)
        val end = if (target == null) path.lastIndex else TransitVehicles.nearestIndex(path, target)
        return if (start <= end) path.subList(start, end + 1).toList()
        else path.subList(end, start + 1).reversed()
    }

    /** True when the user or the target sits outside the safe area of the [visible] box. */
    fun needsRefit(visible: TransitGoMapBox, user: LatLng?, target: LatLng?, inset: Double = SAFE_INSET): Boolean {
        val safe = visible.inset(inset)
        return listOfNotNull(user, target).any { !safe.contains(it) }
    }

    /**
     * The line to draw with its vehicles. Riding or waiting at the stop shows the current ride.
     * On foot, the next ride shows once its boarding stop is within [radiusMeters] of the user;
     * without a fix nothing is shown, so no request leaves for a line the user may never reach.
     */
    fun nearLine(
        trip: TransitItinerary,
        legIndex: Int,
        phase: String,
        user: LatLng?,
        radiusMeters: Double = NEAR_LINE_METERS,
    ): TransitGoMapLine? {
        val steps = trip.steps
        if (phase == TransitGoMachine.PHASE_DONE || legIndex !in steps.indices) return null
        if (phase == TransitGoMachine.PHASE_RIDE || phase == TransitGoMachine.PHASE_WAIT) {
            return lineOf(steps[legIndex], legIndex)
        }
        val next = (legIndex + 1..steps.lastIndex).firstOrNull { steps[it].line != null } ?: return null
        val board = steps[next].boardStop?.location ?: return null
        if (user == null || user.distanceTo(board) > radiusMeters) return null
        return lineOf(steps[next], next)
    }

    /** The estimated vehicles of [label], the only ones GO draws. */
    fun vehiclesOn(vehicles: List<TransitVehicle>, label: String): List<TransitVehicle> {
        if (label.isBlank()) return emptyList()
        return vehicles.filter { it.label.trim().equals(label.trim(), ignoreCase = true) }
    }

    /** The vehicle GO's rail follows: the one of the line nearest the user, else nearest [fallback]. */
    fun hintVehicle(vehicles: List<TransitVehicle>, user: LatLng?, fallback: LatLng?): TransitVehicle? {
        val anchor = user ?: fallback ?: return vehicles.firstOrNull()
        return vehicles.minByOrNull { LatLng(it.lat, it.lng).distanceTo(anchor) }
    }

    /** The `map/trips` box for [line]: its shape and the user, with a small margin. */
    fun requestBox(line: TransitGoMapLine, user: LatLng?): TransitGoMapBox? =
        TransitGoMapBox.around(line.path + listOfNotNull(user, line.boardStop))?.grown(REQUEST_MARGIN_DEGREES)

    private fun lineOf(step: TransitStep, index: Int): TransitGoMapLine? {
        val line = step.line ?: return null
        val path = pathOf(step)
        if (path.size < 2) return null
        return TransitGoMapLine(
            legIndex = index,
            label = line.name,
            colorHex = line.colorHex ?: step.mode.defaultColorHex,
            path = path,
            boardStop = step.boardStop?.location,
        )
    }

    private fun pathOf(step: TransitStep): List<LatLng> {
        step.path?.takeIf { it.size >= 2 }?.let { return it }
        if (step.line == null) return listOfNotNull(step.walkFrom, step.walkTo)
        return (listOfNotNull(step.boardStop) + step.intermediateStops + listOfNotNull(step.alightStop))
            .mapNotNull { it.location }
    }

    private fun destination(trip: TransitItinerary): LatLng? {
        val last = trip.steps.lastOrNull() ?: return null
        return last.walkTo ?: last.path?.lastOrNull() ?: last.alightStop?.location
    }

    private fun atLeastMinimum(box: TransitGoMapBox): TransitGoMapBox {
        val padLat = ((MIN_SPAN_DEGREES - (box.north - box.south)) / 2).coerceAtLeast(0.0)
        val padLng = ((MIN_SPAN_DEGREES - (box.east - box.west)) / 2).coerceAtLeast(0.0)
        return TransitGoMapBox(box.south - padLat, box.west - padLng, box.north + padLat, box.east + padLng)
    }
}

/**
 * Debug stretches for GO's map scenario: two live K stretches on the San Francisco preview ride,
 * timed around the launch clock so the real interpolation of `TransitVehicles.markers` places
 * them. They are fixtures, not a feed answer, and they only run behind `-VelaTransitGoTest`.
 */
object TransitGoMapFixtures {
    /** The fixture stretches run through the production interpolation at [nowEpochSec]. */
    fun vehicles(trip: TransitItinerary, nowEpochSec: Long): List<TransitVehicle> =
        TransitVehicles.markers(runs(trip, nowEpochSec), nowEpochSec)

    fun runs(trip: TransitItinerary, nowEpochSec: Long): List<Transitous.MapTripRun> {
        val ride = trip.steps.firstOrNull { it.line != null } ?: return emptyList()
        val stops = (listOfNotNull(ride.boardStop) + ride.intermediateStops + listOfNotNull(ride.alightStop))
            .filter { it.location != null }
        if (stops.size < 4) return emptyList()
        val label = ride.line?.name.orEmpty()
        val color = ride.line?.colorHex
        fun run(id: String, fromIndex: Int, toIndex: Int, departure: Long, arrival: Long) =
            Transitous.MapTripRun(
                tripId = id,
                label = label,
                mode = TransitMode.TRAM,
                colorHex = color,
                from = stops[fromIndex].location!!,
                fromName = stops[fromIndex].name,
                to = stops[toIndex].location!!,
                toName = stops[toIndex].name,
                departureEpochSec = departure,
                arrivalEpochSec = arrival,
                scheduledDepartureEpochSec = departure - 120,
                scheduledArrivalEpochSec = arrival - 120,
                realTime = true,
                path = listOf(stops[fromIndex].location!!, stops[toIndex].location!!),
            )
        return listOf(
            // Outbound, half way between the second and the third stop.
            run("go-fixture-k-out", 1, 2, nowEpochSec - 90, nowEpochSec + 90),
            // Inbound, a third of the way back from the fourth stop.
            run("go-fixture-k-in", 3, 2, nowEpochSec - 40, nowEpochSec + 80),
        )
    }
}
