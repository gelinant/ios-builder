package app.vela.ios.route

import app.vela.core.model.Lane
import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.model.RouteSource
import app.vela.core.model.TrafficSpan

/**
 * Deterministic driving routes for the route-order accessibility audit, inert unless the debug
 * launch argument `-VelaRouteOrderFixture YES` flips [enabled]. The CI runner's router answers a
 * real query in anywhere from two seconds to over a minute, which made `QualityUITests`' order
 * scenario fail with "no route" while the sheet itself was fine. Only the router's answer is
 * replaced: the destination, the mode chips, the avoid switches, Start and Steps stay the real
 * UI. Two routes give the chooser its rows, and the maneuvers carry lanes so the steps sheet has
 * lane guidance to label. Release builds never reach this object.
 */
object RouteOrderFixture {
    var enabled: Boolean = false

    /** The preferred route: faster, with three steps and a lane diagram on the turn. */
    const val FAST_SECONDS = 600.0
    const val FAST_METERS = 3400.0

    /** The alternate: eight minutes slower, so the chooser ranks them. */
    const val SLOW_SECONDS = 1080.0
    const val SLOW_METERS = 4200.0

    /** Both routes from [origin] to [destination], fastest first. */
    fun routes(origin: LatLng, destination: LatLng): List<Route> {
        if (!enabled) return emptyList()
        val fast = route(origin, destination, summary = "Market Street", seconds = FAST_SECONDS, meters = FAST_METERS)
        val slow = route(
            origin, destination, summary = "Van Ness Avenue",
            seconds = SLOW_SECONDS, meters = SLOW_METERS,
            offsetDeg = 0.004,
        )
        return listOf(fast, slow)
    }

    private fun route(
        origin: LatLng,
        destination: LatLng,
        summary: String,
        seconds: Double,
        meters: Double,
        offsetDeg: Double = 0.0,
    ): Route {
        val third = LatLng(
            origin.lat + (destination.lat - origin.lat) / 3.0 + offsetDeg,
            origin.lng + (destination.lng - origin.lng) / 3.0 + offsetDeg,
        )
        val twoThirds = LatLng(
            origin.lat + 2.0 * (destination.lat - origin.lat) / 3.0 + offsetDeg,
            origin.lng + 2.0 * (destination.lng - origin.lng) / 3.0 + offsetDeg,
        )
        val maneuvers = listOf(
            Maneuver(
                type = ManeuverType.DEPART,
                instruction = "Head north on Market Street",
                location = origin,
                distanceMeters = meters / 3.0,
                durationSeconds = seconds / 3.0,
                road = "Market Street",
            ),
            Maneuver(
                type = ManeuverType.TURN_RIGHT,
                instruction = "Turn right onto Van Ness Avenue",
                location = third,
                distanceMeters = meters / 3.0,
                durationSeconds = seconds / 3.0,
                road = "Van Ness Avenue",
                lanes = listOf(
                    Lane(indications = listOf("left"), valid = false),
                    Lane(indications = listOf("straight"), valid = true),
                    Lane(indications = listOf("right"), valid = true),
                ),
            ),
            Maneuver(
                type = ManeuverType.ARRIVE,
                instruction = "Arrive at your destination",
                location = destination,
                distanceMeters = 0.0,
                durationSeconds = 0.0,
                side = "right",
            ),
        )
        return Route(
            polyline = listOf(origin, third, twoThirds, destination),
            legs = listOf(RouteLeg(meters, seconds, null, maneuvers)),
            distanceMeters = meters,
            durationSeconds = seconds,
            durationInTrafficSeconds = seconds * 1.2,
            summary = summary,
            trafficSpans = listOf(TrafficSpan(level = 1, startMeters = meters / 3.0, lengthMeters = meters / 6.0)),
            source = RouteSource.OSRM,
        )
    }
}
