package app.vela.core.model

import app.vela.core.util.toDegrees
import app.vela.core.util.toRadians
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.serialization.Serializable

/**
 * A WGS84 coordinate. Vela's own type, deliberately free of any MapLibre
 * dependency so `:core` stays UI-agnostic — convert to/from
 * `org.maplibre.android.geometry.LatLng` only at the view boundary.
 */
@Serializable
data class LatLng(val lat: Double, val lng: Double)

/** south/west/north/east, in degrees. */
data class LatLngBounds(
    val south: Double,
    val west: Double,
    val north: Double,
    val east: Double,
) {
    val center: LatLng get() = LatLng((south + north) / 2.0, (west + east) / 2.0)

    companion object {
        /** Rough square bounds of [radiusMeters] around [c]; good enough for a
         *  "search near here" viewport bias. */
        fun around(c: LatLng, radiusMeters: Double): LatLngBounds {
            val dLat = radiusMeters / 111_320.0
            val dLng = radiusMeters /
                (111_320.0 * cos(c.lat.toRadians()).coerceAtLeast(1e-6))
            return LatLngBounds(c.lat - dLat, c.lng - dLng, c.lat + dLat, c.lng + dLng)
        }
    }
}

/** Great-circle distance in meters (haversine). Used for "near me" ranking and
 *  the nav engine's off-route / approaching-maneuver checks. */
fun LatLng.distanceTo(o: LatLng): Double {
    val r = 6_371_000.0
    val dLat = (o.lat - lat).toRadians()
    val dLng = (o.lng - lng).toRadians()
    val a = sin(dLat / 2).pow(2) +
        cos(lat.toRadians()) * cos(o.lat.toRadians()) * sin(dLng / 2).pow(2)
    return 2 * r * asin(min(1.0, sqrt(a)))
}

/** Initial bearing in degrees (0 = N, 90 = E) from this point toward [o]. */
fun LatLng.bearingTo(o: LatLng): Double {
    val dLng = (o.lng - lng).toRadians()
    val y = sin(dLng) * cos(o.lat.toRadians())
    val x = cos(lat.toRadians()) * sin(o.lat.toRadians()) -
        sin(lat.toRadians()) * cos(o.lat.toRadians()) * cos(dLng)
    return (atan2(y, x).toDegrees() + 360.0) % 360.0
}

/** The point [meters] away from this one along [bearingDeg] (0 = N, 90 = E) — great-circle
 *  forward projection. Used to look AHEAD of the nav puck so it sits low in the car map view. */
fun LatLng.destinationPoint(meters: Double, bearingDeg: Double): LatLng {
    val r = 6_371_000.0
    val d = meters / r
    val brng = bearingDeg.toRadians()
    val lat1 = lat.toRadians()
    val lng1 = lng.toRadians()
    val lat2 = asin(min(1.0, sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng)))
    val lng2 = lng1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
    return LatLng(lat2.toDegrees(), lng2.toDegrees())
}
