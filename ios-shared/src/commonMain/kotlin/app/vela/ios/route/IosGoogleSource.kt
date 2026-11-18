package app.vela.ios.route

import app.vela.core.config.CalibrationStore
import app.vela.core.config.JsTransforms
import app.vela.core.data.google.GoogleIdentity
import app.vela.core.data.google.GoogleMapsSource
import app.vela.core.data.google.GoogleSession
import app.vela.core.diag.DiagSink
import app.vela.core.model.LatLng
import app.vela.core.model.Route
import app.vela.core.model.TravelMode
import app.vela.core.platform.CoreGraph
import kotlinx.coroutines.delay

/**
 * The iOS source: the common [GoogleMapsSource] with Google's walk. Android walks on the open
 * foot router and asks Google only to compare (SPEC 4.3); the open router moves to common with
 * C-5, so until then a walk is Google's own, asked the way the comparison asks it.
 */
class IosGoogleSource(
    graph: CoreGraph,
    session: GoogleSession,
    calibration: CalibrationStore,
    transforms: JsTransforms,
    identity: GoogleIdentity,
) : GoogleMapsSource(
    graph = graph,
    largeReplyHttp = graph.http,
    session = session,
    calibration = calibration,
    jsTransforms = transforms,
    diag = DiagSink.NONE,
    identity = identity,
) {
    override suspend fun directions(
        origin: LatLng,
        destination: LatLng,
        mode: TravelMode,
        waypoints: List<LatLng>,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
        urgent: Boolean,
        departBearingDeg: Double?,
        budgetMs: Long?,
    ): List<Route> {
        if (mode != TravelMode.WALK) {
            return super.directions(origin, destination, mode, waypoints, avoidTolls, avoidHighways, avoidFerries, urgent, departBearingDeg, budgetMs)
        }
        return io {
            var routes: List<Route> = emptyList()
            for (attempt in 0 until WALK_TRIES) {
                if (attempt > 0) delay(300L * attempt)
                routes = runCatching {
                    googleDirections(origin, destination, mode, waypoints = waypoints, walkCompare = true)
                }.getOrElse { if (it is app.vela.core.data.CalibrationNeededException) throw it else emptyList() }
                if (routes.isNotEmpty()) break
            }
            routes
        }
    }

    private companion object {
        const val WALK_TRIES = 3
    }
}
