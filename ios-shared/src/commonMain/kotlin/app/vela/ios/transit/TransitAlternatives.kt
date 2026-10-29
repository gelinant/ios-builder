package app.vela.ios.transit

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
import app.vela.core.model.TransitItinerary

/** One intermediate stop offered for a `via` search. [stopId] is the planner's id when the trip
 *  carried it; otherwise the service resolves the name around ([lat],[lng]) before asking. */
data class TransitViaCandidate(
    val stepIndex: Int,
    val name: String,
    val stopId: String?,
    val lat: Double,
    val lng: Double,
    val clockText: String? = null,
)

/** The plan a via alternative asks for: the trip's own ends, time and the chosen stop. */
data class TransitViaQuery(
    val origin: LatLng,
    val destination: LatLng,
    val viaStopId: String?,
    val viaName: String,
    val timeMode: Int,
    val timeEpochSec: Long?,
    val lineLabel: String?,
)

/** The options a via search returned, with the row mapping of the trip screen. */
data class TransitViaOptions(
    val viaName: String,
    val viaStopId: String,
    val query: String,
    val trips: List<TransitItinerary>,
    val options: List<TransitTripOption>,
)

/**
 * Alternatives inside one trip. A `via` search names an intermediate stop and asks the planner to
 * pass through it; a shifted departure reuses the trip screen's own T-3 query. Selection stays the
 * trip screen's: [selectIndexFor] finds the matching itinerary in the store the detail sheet reads,
 * so picking a via option can call the same `RouteStore.select` as a shifted one.
 */
object TransitAlternatives {
    /** The intermediate stops of the segment's ride, in travel order. A stop without an id is
     *  still offered: the caller resolves it by name first, never invents an id. */
    fun candidates(trip: TransitItinerary, segment: TransitTripSegment): List<TransitViaCandidate> {
        if (segment.kind != TransitTrip.KIND_RIDE) return emptyList()
        val step = trip.steps.getOrNull(segment.stepIndex) ?: return emptyList()
        return step.intermediateStops.mapNotNull { stop ->
            val at = stop.location ?: return@mapNotNull null
            if (stop.name.isBlank()) return@mapNotNull null
            if (at.lat !in -90.0..90.0 || at.lng !in -180.0..180.0) return@mapNotNull null
            TransitViaCandidate(
                stepIndex = segment.stepIndex,
                name = stop.name,
                stopId = stop.stopId,
                lat = at.lat,
                lng = at.lng,
                clockText = stop.timeText,
            )
        }
    }

    /** The trip's two ends: the first walk's start, else the first ride's boarding stop; the same
     *  at the other end. Null when the itinerary gave neither, so no via search is attempted. */
    fun endsOf(trip: TransitItinerary): Pair<LatLng, LatLng>? {
        val first = trip.steps.firstOrNull() ?: return null
        val last = trip.steps.lastOrNull() ?: return null
        val origin = first.walkFrom ?: trip.steps.firstNotNullOfOrNull { it.boardStop?.location } ?: return null
        val destination = last.walkTo ?: trip.steps.asReversed().firstNotNullOfOrNull { it.alightStop?.location } ?: return null
        return origin to destination
    }

    /** The via request: same ends, the trip's departure when it has one, the chosen stop. Without a
     *  departure the query is "leave now"; an id is only a placeholder, the service resolves the
     *  name when the trip gave none. */
    fun query(trip: TransitItinerary, segment: TransitTripSegment, candidate: TransitViaCandidate): TransitViaQuery? {
        val (origin, destination) = endsOf(trip) ?: return null
        val departure = trip.departureEpochSec
        return TransitViaQuery(
            origin = origin,
            destination = destination,
            viaStopId = candidate.stopId,
            viaName = candidate.name,
            timeMode = if (departure != null) TransitTrip.SHIFT_DEPART_AT else 0,
            timeEpochSec = departure,
            lineLabel = segment.lineLabel,
        )
    }

    /** The planner's answer as the trip screen's rows; no option is added from an empty answer. */
    fun options(query: TransitViaQuery, viaStopId: String, trips: List<TransitItinerary>): TransitViaOptions {
        return TransitViaOptions(
            viaName = query.viaName,
            viaStopId = viaStopId,
            query = "Via ${query.viaName}",
            trips = trips,
            options = TransitTrip.options(trips),
        )
    }

    /** A shifted departure is the T-3 query unchanged; this only keeps one entry point for both
     *  kinds of alternative. */
    fun shift(trip: TransitItinerary, segment: TransitTripSegment, header: TransitTripHeader, mode: Int, deltaMinutes: Int): TransitTripShift? =
        TransitTrip.shift(trip, segment, header, mode, deltaMinutes)

    /** The index of [chosen] in the store's own list, compared on the fields the chooser shows.
     *  -1 when it is not there, and the caller must adopt it without `RouteStore.select`. */
    fun selectIndexFor(routeTrips: List<TransitItinerary>, chosen: TransitItinerary): Int {
        val index = routeTrips.indexOfFirst { it.sameOption(chosen) }
        return index
    }

    private fun TransitItinerary.sameOption(other: TransitItinerary): Boolean =
        departureEpochSec == other.departureEpochSec &&
            arrivalEpochSec == other.arrivalEpochSec &&
            lines.map { it.name } == other.lines.map { it.name } &&
            steps.size == other.steps.size

    /** One request for one chosen stop: the service's network half. The id comes from the trip when
     *  it carried one, else from the name lookup around the stop's own coordinate. */
    suspend fun plan(http: TransitousHttp, trip: TransitItinerary, segment: TransitTripSegment, candidate: TransitViaCandidate): TransitViaOptions? {
        val query = query(trip, segment, candidate) ?: return null
        val id = candidate.stopId
            ?: Transitous.resolveStop(http, candidate.name, candidate.lat, candidate.lng)?.stopId
            ?: return null
        val trips = Transitous.planVia(
            http, query.origin, query.destination, id,
            timeMode = query.timeMode, timeEpochSec = query.timeEpochSec,
        )
        if (trips.isEmpty()) return null
        return options(query, id, trips)
    }
}
