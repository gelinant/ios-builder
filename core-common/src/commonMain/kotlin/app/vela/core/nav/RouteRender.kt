package app.vela.core.nav

import app.vela.core.model.Lane
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.TrafficSpan
import app.vela.core.model.distanceTo
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * The geometry the navigation map draws above the route line: the travelled and remaining pieces
 * coloured by congestion, the arrows on the road ahead and the lane glyphs at an approach.
 *
 * Pure on purpose. A screenshot can show that SOMETHING is drawn; it cannot show that the gray
 * ends exactly at the car, that a jam the driver already left is not still red, or that the first
 * arrow is the manoeuvre the banner names. Those are the failures pinned by `RouteRenderTest`.
 */
object RouteRender {

    /** A piece behind the car. Every other level is Google's congestion grade, 0 free flow. */
    const val TRAVELED = -1
    const val FREE = 0

    /** Lanes are drawn only at the approach, with the banner's same two thresholds. */
    const val LANE_MIN_M = 800.0
    const val LANE_SPEED_SECONDS = 30.0

    /** One continuous stretch of the route with the colour level its midpoint carries. */
    data class Segment(val level: Int, val points: List<LatLng>)

    /** One manoeuvre arrow at the point the banner names. [role] is `next` or `then`. */
    data class Arrow(
        val index: Int,
        val role: String,
        val kind: String,
        val location: LatLng,
        val rotation: Double,
    )

    /** One lane glyph placed across the approach, left lane first. */
    data class LaneGlyph(
        val indications: List<String>,
        val valid: Boolean,
        val location: LatLng,
        val rotation: Double,
    )

    /**
     * Split [poly] at the travelled point and at every congestion span boundary. A piece behind
     * the car is always [TRAVELED], even where a span is still listed: the drive is over there.
     * Spans are measured along the polyline, not along the router's distance figure.
     */
    fun segments(
        poly: List<LatLng>,
        traveledM: Double,
        spans: List<TrafficSpan>,
        totalM: Double? = null,
    ): List<Segment> {
        if (poly.size < 2) return emptyList()
        val cum = RouteProjection.cumulative(poly)
        val total = (totalM?.takeIf { it > 0.0 } ?: cum.last()).coerceAtLeast(0.0)
        if (total < 1.0) return emptyList()
        val traveled = traveledM.coerceIn(0.0, total)
        // A sorted, de-duplicated cut list keeps every piece in route order and removes the
        // duplicate cuts where two spans touch.
        val breaks = mutableListOf(0.0, total)
        if (traveled > 0.25 && traveled < total - 0.25) breaks.add(traveled)
        for (span in spans) {
            val from = span.startMeters.coerceIn(0.0, total)
            val to = (span.startMeters + span.lengthMeters).coerceIn(0.0, total)
            if (to - from > 0.5) {
                breaks.add(from)
                breaks.add(to)
            }
        }
        val ordered = breaks.sorted().distinct()
        val out = ArrayList<Segment>(ordered.size)
        for (i in 0 until ordered.size - 1) {
            val from = ordered[i]
            val to = ordered[i + 1]
            if (to - from < 0.5) continue
            val mid = (from + to) / 2.0
            val level = if (mid <= traveled + 0.01) {
                TRAVELED
            } else {
                spans
                    .filter { mid >= it.startMeters && mid < it.startMeters + it.lengthMeters }
                    .maxOfOrNull { it.level } ?: FREE
            }
            val points = slice(poly, cum, from, to)
            if (points.size >= 2) out.add(Segment(level, points))
        }
        // A span boundary that does not change the colour (two jams of one grade, or a span that
        // starts inside the driven gray) must not become a second geometry piece.
        val merged = ArrayList<Segment>(out.size)
        for (segment in out) {
            val previous = merged.lastOrNull()
            if (previous != null && previous.level == segment.level) {
                merged[merged.size - 1] = Segment(
                    previous.level, previous.points + segment.points.drop(1))
            } else {
                merged.add(segment)
            }
        }
        return merged
    }

    /**
     * The next manoeuvre and the one after it, starting at [stepIndex]. That index is the one the
     * banner reads, so the first arrow is always the banner's own kind and never a neighbour's.
     * DEPART is skipped: a start marker is not a turn ahead. The same point is not drawn twice.
     */
    fun aheadArrows(
        poly: List<LatLng>,
        maneuvers: List<Maneuver>,
        stepIndex: Int,
        limit: Int = 2,
    ): List<Arrow> {
        if (stepIndex < 0 || limit <= 0) return emptyList()
        val cum = if (poly.size >= 2) RouteProjection.cumulative(poly) else null
        val out = ArrayList<Arrow>(limit)
        var index = stepIndex
        while (index < maneuvers.size && out.size < limit) {
            val maneuver = maneuvers[index]
            index += 1
            if (maneuver.type == ManeuverType.DEPART) continue
            val previous = out.lastOrNull()?.location
            if (previous != null && previous.distanceTo(maneuver.location) < 1.0) continue
            val rotation = if (cum != null) {
                val along = RouteProjection.alongMeters(poly, cum, maneuver.location, 30.0)
                RouteProjection.bearingAt(poly, cum, along ?: 0.0)
            } else {
                0.0
            }
            out.add(
                Arrow(
                    index = index - 1,
                    role = if (out.isEmpty()) "next" else "then",
                    kind = maneuver.type.name,
                    location = maneuver.location,
                    rotation = rotation,
                )
            )
        }
        return out
    }

    /** The banner's own approach gate, shared so the map never shows lanes the card hides. */
    fun lanesVisible(lanes: List<Lane>, distanceM: Double, speedMps: Double?): Boolean {
        if (lanes.isEmpty()) return false
        val showMeters = max(LANE_MIN_M, (speedMps ?: 0.0) * LANE_SPEED_SECONDS)
        return distanceM <= showMeters
    }

    /**
     * Place one glyph per lane across the approach, left lane first, centred on the manoeuvre
     * point. The row is perpendicular to the last [leadM] meters so it lies across the road, and
     * [LaneGlyph.rotation] is the approach bearing every glyph points along.
     */
    fun laneGlyphs(
        poly: List<LatLng>,
        location: LatLng,
        lanes: List<Lane>,
        spacingM: Double = 3.2,
        leadM: Double = 22.0,
    ): List<LaneGlyph> {
        if (lanes.isEmpty()) return emptyList()
        val bearing = if (poly.size >= 2) {
            val cum = RouteProjection.cumulative(poly)
            val along = RouteProjection.alongMeters(poly, cum, location, 30.0)
            RouteProjection.bearingAt(poly, cum, max(0.0, (along ?: 0.0) - leadM))
        } else {
            0.0
        }
        val center = (lanes.size - 1) / 2.0
        return lanes.mapIndexed { index, lane ->
            val offset = (index - center) * spacingM
            LaneGlyph(
                indications = lane.indications,
                valid = lane.valid,
                location = move(location, bearing + 90.0, offset),
                rotation = bearing,
            )
        }
    }

    /** The part of [poly] between two distances, with both cut ends exactly on the line. */
    private fun slice(poly: List<LatLng>, cum: DoubleArray, from: Double, to: Double): List<LatLng> {
        val out = ArrayList<LatLng>()
        out.add(RouteProjection.pointAt(poly, cum, from))
        for (i in poly.indices) {
            val at = cum[i]
            if (at > from + 0.5 && at < to - 0.5) out.add(poly[i])
        }
        out.add(RouteProjection.pointAt(poly, cum, to))
        var write = 1
        for (read in 1 until out.size) {
            if (out[read].distanceTo(out[write - 1]) > 0.01) {
                out[write] = out[read]
                write += 1
            }
        }
        while (out.size > write) out.removeAt(out.size - 1)
        return out
    }

    /** A point [meters] from [from] on the bearing, in degrees clockwise from north. */
    private fun move(from: LatLng, bearingDeg: Double, meters: Double): LatLng {
        if (meters == 0.0) return from
        val radians = bearingDeg * PI / 180.0
        val dLat = meters * cos(radians) / 111_320.0
        val dLng = meters * sin(radians) /
            (111_320.0 * max(0.2, cos(from.lat * PI / 180.0)))
        return LatLng(from.lat + dLat, from.lng + dLng)
    }
}
