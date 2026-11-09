package app.vela.ios.route

import app.vela.core.data.AlprCamera
import app.vela.core.model.LatLng
import app.vela.core.nav.CameraDetour
import app.vela.core.nav.RouteProjection

/**
 * Deterministic plate cameras for the UI scenario, inert unless the debug launch argument
 * `-VelaRouteCameraFixture YES` flips [enabled]. The CI runner cannot rely on DeFlock coverage on
 * the one route it drives, so this places two untagged cameras on the FIRST route of a trip and
 * none on any other line. That gives the camera pass a real comparison: a router that answers with
 * the same road keeps both cameras and is rejected by [CameraDetour.sameRoute], one that finds a
 * side street comes back with none and can be offered honestly. It is not a production source and
 * never appears unless the argument asks for it.
 */
object RouteCameraFixture {
    var enabled: Boolean = false

    private var base: List<LatLng>? = null

    /** The cameras on [polyline]: two on the first route of the trip, none on any other. */
    fun cameras(polyline: List<LatLng>): List<AlprCamera> {
        if (!enabled || polyline.size < 2) return emptyList()
        val current = base
        // A new trip starts far from the previous base; its first route becomes the new reference.
        if (current == null || distanceM(current.first(), polyline.first()) > NEW_TRIP_M ||
            distanceM(current.last(), polyline.last()) > NEW_TRIP_M
        ) {
            base = polyline
        }
        val reference = base ?: return emptyList()
        if (!CameraDetour.sameRoute(reference, polyline)) return emptyList()
        val cumulative = RouteProjection.cumulative(reference)
        val total = cumulative.last()
        if (total <= 0.0) return emptyList()
        return listOf(0.35, 0.65).map { fraction ->
            AlprCamera(RouteProjection.pointAt(reference, cumulative, total * fraction))
        }
    }

    /** Forgets the reference route; the next camera pass starts a new trip. */
    fun reset() {
        base = null
    }

    private fun distanceM(a: LatLng, b: LatLng): Double {
        val k = 111_320.0 * kotlin.math.cos(a.lat * kotlin.math.PI / 180.0)
        return kotlin.math.hypot((a.lng - b.lng) * k, (a.lat - b.lat) * 111_320.0)
    }

    private const val NEW_TRIP_M = 500.0
}
