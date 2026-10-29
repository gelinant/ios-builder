package app.vela.ios.nav

import app.vela.core.model.LatLng
import app.vela.core.model.Lane
import app.vela.core.model.Maneuver
import app.vela.core.model.Route
import app.vela.core.nav.RouteRender

/** One drawn piece: [level] is -1 travelled, 0 free flow, 1..3 congestion. */
data class NavRenderPiece(val level: Int, val points: DoubleArray)

/** One manoeuvre arrow, at the point the banner names; [role] is `next` or `then`. */
data class NavRenderArrow(
    val role: String,
    val kind: String,
    val latitude: Double,
    val longitude: Double,
    val rotation: Double,
)

/** One lane glyph placed across the approach, left lane first. */
data class NavRenderLane(
    val indications: List<String>,
    val valid: Boolean,
    val latitude: Double,
    val longitude: Double,
    val rotation: Double,
)

/** What the navigation map draws for one live route, already reduced to plain numbers. */
data class NavRenderFrame(
    val traveledM: Double,
    val pieces: List<NavRenderPiece>,
    val arrows: List<NavRenderArrow>,
    val lanes: List<NavRenderLane>,
)

/**
 * Builds the Swift-facing frame from the shared route and the live step. It adds no data of its
 * own: every colour, arrow and lane comes from the route's traffic spans and manoeuvres.
 */
object NavMapRender {

    fun build(
        route: Route,
        traveledM: Double,
        stepIndex: Int,
        distanceToNext: Double,
        speedMps: Double?,
        previewIndex: Int?,
        previewManeuver: NavManeuver?,
    ): NavRenderFrame {
        val pieces = RouteRender.segments(route.polyline, traveledM, route.trafficSpans)
            .map { segment -> NavRenderPiece(segment.level, flat(segment.points)) }
        val arrows = RouteRender.aheadArrows(
            route.polyline, route.maneuvers, previewIndex ?: stepIndex)
            .map { arrow ->
                NavRenderArrow(
                    role = arrow.role,
                    kind = arrow.kind,
                    latitude = arrow.location.lat,
                    longitude = arrow.location.lng,
                    rotation = arrow.rotation,
                )
            }
        val live = route.maneuvers.getOrNull(stepIndex)
        val laneManeuver: Maneuver? = if (previewIndex != null) {
            val preview = route.maneuvers.getOrNull(previewIndex)
            preview ?: previewManeuver?.let {
                Maneuver(
                    type = app.vela.core.model.ManeuverType.UNKNOWN,
                    instruction = it.instruction,
                    location = LatLng(it.latitude, it.longitude),
                    distanceMeters = it.distanceMeters,
                    durationSeconds = 0.0,
                    lanes = it.lanes.map { lane -> Lane(lane.indications, lane.valid) },
                )
            }
        } else {
            live?.takeIf { RouteRender.lanesVisible(it.lanes, distanceToNext, speedMps) }
        }
        val lanes = if (laneManeuver == null) {
            emptyList()
        } else {
            RouteRender.laneGlyphs(route.polyline, laneManeuver.location, laneManeuver.lanes)
                .map { glyph ->
                    NavRenderLane(
                        indications = glyph.indications,
                        valid = glyph.valid,
                        latitude = glyph.location.lat,
                        longitude = glyph.location.lng,
                        rotation = glyph.rotation,
                    )
                }
        }
        return NavRenderFrame(traveledM, pieces, arrows, lanes)
    }

    private fun flat(points: List<LatLng>): DoubleArray {
        val out = DoubleArray(points.size * 2)
        for (index in points.indices) {
            out[index * 2] = points[index].lat
            out[index * 2 + 1] = points[index].lng
        }
        return out
    }
}
