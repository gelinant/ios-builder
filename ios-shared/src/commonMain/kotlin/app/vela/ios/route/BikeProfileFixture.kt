package app.vela.ios.route

import app.vela.core.model.LatLng
import app.vela.core.model.Maneuver
import app.vela.core.model.ManeuverType
import app.vela.core.model.Route
import app.vela.core.model.RouteLeg
import app.vela.core.model.RouteSource

/**
 * Deterministic bicycle routes for the UI scenario, inert unless the debug launch argument
 * `-VelaBikeProfileFixture YES` flips [enabled]. The CI runner cannot rely on the safety-weighted
 * and fastest profiles returning different roads for the one trip it plans, so this answers the
 * two profiles with two clearly different lines and times. The settings and the request itself
 * stay real: only the router's answer is replaced. It is not a production source and never
 * appears unless the argument asks for it.
 */
object BikeProfileFixture {
    var enabled: Boolean = false

    /** The safety-weighted profile's answer: longer, along the cycleway. */
    const val SAFE_SECONDS = 900.0
    const val SAFE_METERS = 4200.0

    /** The fastest profile's answer: shorter, down the direct road. */
    const val FAST_SECONDS = 600.0
    const val FAST_METERS = 2600.0

    /** One bicycle route for [origin] to [destination], shaped by [bikeSafe]. */
    fun routes(origin: LatLng, destination: LatLng, bikeSafe: Boolean): List<Route> {
        if (!enabled) return emptyList()
        val middle = LatLng(
            (origin.lat + destination.lat) / 2.0 + (if (bikeSafe) BIKE_SAFE_OFFSET_DEG else 0.0),
            (origin.lng + destination.lng) / 2.0 + (if (bikeSafe) BIKE_SAFE_OFFSET_DEG else 0.0),
        )
        val points = listOf(origin, middle, destination)
        val seconds = if (bikeSafe) SAFE_SECONDS else FAST_SECONDS
        val meters = if (bikeSafe) SAFE_METERS else FAST_METERS
        val maneuvers = listOf(
            Maneuver(
                type = ManeuverType.DEPART,
                instruction = if (bikeSafe) "Bike along the cycleway" else "Bike down the direct road",
                location = origin,
                distanceMeters = meters,
                durationSeconds = seconds,
            ),
            Maneuver(
                type = ManeuverType.ARRIVE,
                instruction = "Arrive",
                location = destination,
                distanceMeters = 0.0,
                durationSeconds = 0.0,
            ),
        )
        return listOf(
            Route(
                polyline = points,
                legs = listOf(RouteLeg(meters, seconds, null, maneuvers)),
                distanceMeters = meters,
                durationSeconds = seconds,
                durationInTrafficSeconds = null,
                summary = if (bikeSafe) "Cycleway" else "Direct road",
                source = if (bikeSafe) RouteSource.VALHALLA else RouteSource.OSRM,
            )
        )
    }

    /** A clear sideways shift, about 1.5 km at San Francisco's latitude. */
    private const val BIKE_SAFE_OFFSET_DEG = 0.015
}
