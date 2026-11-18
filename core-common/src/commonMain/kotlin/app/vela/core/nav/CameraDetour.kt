package app.vela.core.nav

import app.vela.core.data.AlprCamera
import app.vela.core.model.LatLng
import app.vela.core.util.toRadians

/**
 * Where to try a side street around the plate cameras on a route (issue #600).
 *
 * The reporter's own workaround, automated: for each cluster of cameras the leading route passes,
 * try a point a little way to either side of the road at the cluster and route THROUGH it. The
 * router's own snap does the graph work: a point that lands on the same road folds back into the
 * same route (the camera count does not drop, so the caller rejects it), a point that lands on a
 * parallel street is a real detour. Nothing here knows about roads; it only says where to ask.
 *
 * Bounded on purpose: at most [MAX_CLUSTERS] clusters per route, nearest first, at most
 * [MAX_REQUESTS_PER_ROUTE] route requests for one candidate route and [MAX_REQUESTS] for the whole
 * trip, because each one is a full route request to a fair-use community router plus Google.
 * The pass runs over every candidate route that passes cameras, not only the one that leads
 * after the re-rank: the two disagree when a route's cameras sit on an arterial with a parallel
 * street while the leader's one camera sits on a bridge. Routes share arterials, so a cluster
 * already tried on another route is skipped ([untried]); that is what keeps the trip budget at
 * six requests instead of six per route.
 */
object CameraDetour {

    /** How far off the road a candidate point sits. Far enough to reach the next street over in a
     *  city block, near enough that a rural road with nothing beside it snaps straight back. */
    const val OFFSET_M = 150.0
    const val MAX_CLUSTERS = 3
    const val MAX_REQUESTS = 6
    const val MAX_REQUESTS_PER_ROUTE = 4
    /** A cluster within this distance of one already tried on another route is the same corner. */
    const val SAME_CLUSTER_M = 60.0

    /**
     * A camera counts against a route when it sits this close to its line. Android's
     * `FlockCameras.along` threshold (issue #527): a camera a block over is not on the way.
     */
    const val ON_ROUTE_M = 45.0

    /** The camera preference never adds more than this share of the fastest route's time... */
    const val MAX_DETOUR_FRACTION = 0.25
    /** ...nor more than this many seconds, both as Android's re-rank caps it. */
    const val MAX_DETOUR_S = 600.0

    /** A camera cluster on the route ([atM] along it, [count] heads, [at] its point) and the two
     *  points to try. */
    data class Candidate(val atM: Double, val count: Int, val left: LatLng, val right: LatLng, val at: LatLng)

    /** A route as the camera choice sees it: how many cameras it passes and its shown time. */
    data class Option(val cameras: Int, val etaS: Double)

    /** A camera the route passes: how far along it, and the camera. */
    data class OnRoute(val atM: Double, val camera: AlprCamera)

    /**
     * The cameras in [cameras] that can read traffic on [poly]: within [ON_ROUTE_M] of its line and,
     * when their facing is known, aimed along that road rather than across it
     * ([CameraFacing]). The one counting rule, mirroring Android's `FlockCameras.along`, so the
     * two apps badge and choose on the same numbers.
     */
    fun onRoute(poly: List<LatLng>, cameras: List<AlprCamera>): List<OnRoute> {
        if (poly.size < 2) return emptyList()
        val cum = RouteProjection.cumulative(poly)
        return cameras.mapNotNull { camera ->
            val near = CameraFacing.nearestSegment(poly, camera.loc) ?: return@mapNotNull null
            if (near.distanceM > ON_ROUTE_M) return@mapNotNull null
            if (!CameraFacing.seesRoad(CameraFacing.parse(camera.direction), near.bearingDeg)) {
                return@mapNotNull null
            }
            val at = RouteProjection.alongMeters(poly, cum, camera.loc, ON_ROUTE_M) ?: return@mapNotNull null
            OnRoute(at, camera)
        }
    }

    /** How many cameras [poly] passes, by [onRoute]'s rule. */
    fun count(poly: List<LatLng>, cameras: List<AlprCamera>): Int = onRoute(poly, cameras).size

    /** The most the camera preference may add to the fastest route, in seconds. */
    fun cap(eta0: Double): Double = minOf(eta0 * MAX_DETOUR_FRACTION, MAX_DETOUR_S)

    /** [list] with [index] first and the rest in their original order (Android's re-rank order). */
    fun <T> lead(list: List<T>, index: Int): List<T> {
        if (index !in list.indices) return list
        return listOf(list[index]) + list.filterIndexed { i, _ -> i != index }
    }

    /**
     * True when [b] runs the same line as [a], within 50 m of length and 20 m at five points along
     * it. A router that answers a detour with the road it was already on (the via snapped back)
     * returns the same route here, so the caller never claims an avoidance it did not make.
     */
    fun sameRoute(a: List<LatLng>, b: List<LatLng>): Boolean {
        if (a.size < 2 || b.size < 2) return a.size == b.size
        val ca = RouteProjection.cumulative(a)
        val cb = RouteProjection.cumulative(b)
        val la = ca.last()
        val lb = cb.last()
        if (kotlin.math.abs(la - lb) > 50.0) return false
        for (f in listOf(0.0, 0.25, 0.5, 0.75, 1.0)) {
            val p = RouteProjection.pointAt(a, ca, la * f)
            val q = RouteProjection.pointAt(b, cb, lb * f)
            if (distM(p, q) > 20.0) return false
        }
        return true
    }

    /**
     * The one rule for leading with a camera-lighter route, shared by the re-rank over the routers'
     * own alternates and the pick over the side-street results: the index of the option with the
     * fewest cameras (ties to the faster) when it passes fewer cameras than option 0 and costs at
     * most [cap] seconds over [eta0]; null when option 0 stays. Option 0 is the route that leads
     * now, [eta0] the fastest route's time (the cap is measured from the fastest, not the leader).
     */
    fun choose(options: List<Option>, eta0: Double, cap: Double): Int? {
        if (options.isEmpty()) return null
        val best = options.indices.minByOrNull { options[it].cameras * 1_000_000L + options[it].etaS.toLong() } ?: return null
        if (best == 0) return null
        val o = options[best]
        return if (o.cameras < options[0].cameras && o.etaS - eta0 <= cap) best else null
    }

    /** [cands] minus every cluster within [withinM] of a point in [tried]: the same corner reached
     *  from another route gets the same side streets, so asking again spends requests for nothing. */
    fun untried(cands: List<Candidate>, tried: List<LatLng>, withinM: Double = SAME_CLUSTER_M): List<Candidate> =
        cands.filter { c -> tried.none { t -> distM(c.at, t) <= withinM } }

    private fun distM(a: LatLng, b: LatLng): Double {
        val k = 111_320.0 * kotlin.math.cos(a.lat.toRadians())
        return kotlin.math.hypot((a.lng - b.lng) * k, (a.lat - b.lat) * 111_320.0)
    }

    /** Candidates for the clusters of [cameraAlongM] (distances along [poly], any order), nearest
     *  first, at most [maxClusters]. Left is the driver's left at the route's bearing there. */
    fun candidates(
        poly: List<LatLng>,
        cameraAlongM: List<Double>,
        offsetM: Double = OFFSET_M,
        maxClusters: Int = MAX_CLUSTERS,
    ): List<Candidate> {
        if (poly.size < 2 || cameraAlongM.isEmpty()) return emptyList()
        val cum = RouteProjection.cumulative(poly)
        return CameraAlerts.group(cameraAlongM.sorted()).take(maxClusters).map { g ->
            val p = RouteProjection.pointAt(poly, cum, g.atM)
            val brg = RouteProjection.bearingAt(poly, cum, g.atM)
            Candidate(g.atM, g.count, offset(p, brg - 90.0, offsetM), offset(p, brg + 90.0, offsetM), p)
        }
    }

    /** [p] moved [meters] along compass [bearingDeg]. Planar; exact to centimeters at this range. */
    fun offset(p: LatLng, bearingDeg: Double, meters: Double): LatLng {
        val b = bearingDeg.toRadians()
        val dLat = meters * kotlin.math.cos(b) / 111_320.0
        val dLng = meters * kotlin.math.sin(b) / (111_320.0 * kotlin.math.cos(p.lat.toRadians()))
        return LatLng(p.lat + dLat, p.lng + dLng)
    }

    /** The user's stops and the detour points merged into ONE travel-ordered list by their
     *  position along the route. A stop with no position (not on this line) keeps its place by
     *  index between the ones that have one. */
    fun mergePlan(stops: List<Pair<Double?, LatLng>>, vias: List<Pair<Double, LatLng>>): List<LatLng> =
        mergeOrdered(stops, vias)

    /** [mergePlan] over anything: stops in list order with a position where known, vias with a
     *  position, out as one list ordered along the route. A stop with no position is placed
     *  halfway to the next positioned stop, else just past the previous one. Used by the nav
     *  session too, to keep the silent detour vias in place when the visible stops are edited. */
    fun <T> mergeOrdered(stops: List<Pair<Double?, T>>, vias: List<Pair<Double, T>>): List<T> {
        val filled = ArrayList<Pair<Double, T>>(stops.size)
        var last = 0.0
        for ((i, s) in stops.withIndex()) {
            val at = s.first ?: (stops.drop(i + 1).firstNotNullOfOrNull { it.first }?.let { (last + it) / 2 } ?: (last + 1.0))
            filled += at to s.second
            last = at
        }
        return (filled + vias).sortedBy { it.first }.map { it.second }
    }
}
