package app.vela.ios.place

import app.vela.core.data.ClosingTime
import app.vela.core.data.FuelGb
import app.vela.core.data.FuelGbStations
import app.vela.core.model.LatLng
import app.vela.core.model.distanceTo

/**
 * The route and navigation seams PLC-FUEL adds (BACKLOG L116). The stores that own a drive
 * (`RouteStore`, `NavStore`) stay with their own lots; these pure helpers give them the two
 * decisions so the hook is one call rather than a second copy of the rules:
 *
 *  - [closingWarning] at Start, for the destination or a stop, with the same 60-minute window as
 *    Android's `NavController.closingMessage`;
 *  - [fuelDetour] for a cheap forecourt a short way off the planned line.
 *
 * The exact stores' hooks are reported in `docs/ios/PLACE.md` because editing those files would
 * collide with their lots.
 */
object PlaceTravelHints {
    /** A forecourt close to the line whose petrol beats every other one near it. */
    data class FuelDetour(
        val brand: String?,
        val price: String,
        /** Hundredths of a penny per litre for the grade in [price]. */
        val pence: Int,
        /** Straight-line distance from the nearest point of the route, meters. */
        val offRouteMeters: Double,
        val at: LatLng,
    )

    /** A cheap forecourt within [maxOffRouteM] of [route], or null when the file is stale, the
     *  route is too short, or no forecourt sells fuel close enough. */
    fun fuelDetour(
        route: List<LatLng>,
        data: FuelGbStations,
        nowSec: Long,
        maxOffRouteM: Double = 500.0,
    ): FuelDetour? {
        if (route.size < 2 || !FuelGb.fresh(data, nowSec) || data.size == 0) return null
        // Sample the line instead of testing every vertex: a 10 km route has thousands of points
        // and the hint only needs forecourt-scale accuracy.
        val step = (route.size / 400).coerceAtLeast(1)
        val samples = ArrayList<LatLng>(route.size / step + 1)
        var i = 0
        while (i < route.size) {
            samples += route[i]
            i += step
        }
        if (samples.last() != route.last()) samples += route.last()

        val padLat = maxOffRouteM / 111_320.0
        val padLng = maxOffRouteM / (111_320.0 * 0.5)
        val south = route.minOf { it.lat } - padLat
        val north = route.maxOf { it.lat } + padLat
        val west = route.minOf { it.lng } - padLng
        val east = route.maxOf { it.lng } + padLng
        var best = -1
        var bestPence = Int.MAX_VALUE
        var bestOff = 0.0
        for (k in 0 until data.size) {
            val at = LatLng(data.lat[k], data.lng[k])
            if (at.lat !in south..north || at.lng !in west..east) continue
            var off = Double.MAX_VALUE
            for (p in samples) {
                val d = at.distanceTo(p)
                if (d < off) off = d
            }
            if (off > maxOffRouteM) continue
            val pence = petrolPence(data, k) ?: continue
            if (pence >= bestPence) continue
            if (FuelGb.label(data, k, nowSec) == null) continue
            best = k
            bestPence = pence
            bestOff = off
        }
        if (best < 0) return null
        val price = FuelGb.label(data, best, nowSec) ?: return null
        val brand = data.brand[best].takeIf { it.isNotBlank() && !it.equals("none", ignoreCase = true) }
        return FuelDetour(brand, price, bestPence, bestOff, LatLng(data.lat[best], data.lng[best]))
    }

    /** The Start-time warning for a destination or stop. [arrivalEpochSec] and [nowEpochSec] are
     *  unix seconds; the minute arithmetic happens in [zoneId], so a midnight crossing stays
     *  correct. */
    fun closingWarning(
        name: String,
        statusText: String?,
        openNow: Int,
        arrivalEpochSec: Long,
        nowEpochSec: Long,
        zoneId: String,
    ): ClosingTime.ArrivalWarning? = ClosingTime.arrivalWarning(
        name = name,
        statusText = statusText,
        openNow = openNow,
        arrivalInSeconds = (arrivalEpochSec - nowEpochSec).toDouble(),
        nowEpochSec = nowEpochSec,
        zoneId = zoneId,
    )

    private fun petrolPence(data: FuelGbStations, i: Int): Int? = when {
        data.e10[i] > 0 -> data.e10[i]
        data.e5[i] > 0 -> data.e5[i]
        data.b7s[i] > 0 -> data.b7s[i]
        else -> null
    }
}
