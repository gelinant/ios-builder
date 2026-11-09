package app.vela.ios.saved

import app.vela.core.data.MapDataSource
import app.vela.core.data.google.PolylineCodec
import app.vela.core.model.LatLng
import app.vela.core.model.Place
import app.vela.core.model.Route
import app.vela.core.model.SavedRoute
import app.vela.core.model.SearchResult
import app.vela.core.model.TravelMode
import app.vela.core.model.distanceTo
import app.vela.core.nav.SavedRoutes
import kotlinx.coroutines.CancellationException

/**
 * Adds the user's stored lines to the planning source without changing the navigation source.
 * The common store has no steps or duration, so a saved line has no live traffic and its negative
 * duration is an internal unknown marker. SavedRoutePickerSheet never presents that marker as an
 * ETA and disables Start and Steps for the line-only choice.
 *
 * Route instances are cached by the complete saved value. Reopening an unchanged route therefore
 * reuses the same object, as RouteStore and NavSession require; renaming or replacing the stored
 * line deliberately creates a new value and a new Route.
 */
class SavedRouteDirections(
    private val delegate: MapDataSource,
    private val savedRoutes: () -> List<SavedRoute>,
) : MapDataSource {
    private val lineCache = mutableMapOf<String, Pair<SavedRoute, Route>>()
    private var requestedId: String? = null

    /** A route explicitly reopened from Saved is offered even when the phone is at a new start. */
    fun request(id: String) {
        requestedId = id
    }

    /** Ordinary place directions stop forcing the previously reopened line. */
    fun clearRequest() {
        requestedId = null
    }

    override suspend fun search(
        query: String,
        near: LatLng?,
        spanMeters: Double?,
        rankFrom: LatLng?,
        lang: String?,
    ): SearchResult = delegate.search(query, near, spanMeters, rankFrom, lang)

    override suspend fun placeDetails(id: String): Place = delegate.placeDetails(id)

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
        if (waypoints.isNotEmpty() || urgent) {
            return delegate.directions(
                origin, destination, mode, waypoints, avoidTolls, avoidHighways, avoidFerries,
                urgent, departBearingDeg, budgetMs,
            )
        }
        val requested = requestedId
        val matching = savedRoutes().filter { saved ->
            SavedRoutes.matches(saved, origin, destination, mode) ||
                (saved.id == requested && !saved.isRun && saved.mode == mode.name &&
                    saved.dest.distanceTo(destination) <= SavedRoutes.DEST_M)
        }
        val computed = try {
            delegate.directions(
                origin, destination, mode, waypoints, avoidTolls, avoidHighways, avoidFerries,
                urgent, departBearingDeg, budgetMs,
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (matching.isEmpty()) throw e
            emptyList()
        }
        return matching.map(::savedLine) + computed
    }

    override suspend fun nameRoute(
        route: Route,
        origin: LatLng,
        destination: LatLng,
        mode: TravelMode,
        avoidTolls: Boolean,
        avoidHighways: Boolean,
        avoidFerries: Boolean,
    ): Route = delegate.nameRoute(
        route, origin, destination, mode, avoidTolls, avoidHighways, avoidFerries,
    )

    private fun savedLine(saved: SavedRoute): Route {
        lineCache[saved.id]?.let { cached -> if (cached.first == saved) return cached.second }
        val points = PolylineCodec.decode(saved.polyline)
        var meters = 0.0
        for (i in 1 until points.size) meters += points[i - 1].distanceTo(points[i])
        val route = Route(
            polyline = points,
            legs = emptyList(),
            distanceMeters = meters,
            durationSeconds = UNKNOWN_DURATION,
            durationInTrafficSeconds = null,
            summary = saved.name,
            savedName = saved.name,
        )
        lineCache[saved.id] = saved to route
        return route
    }

    private companion object {
        const val UNKNOWN_DURATION = -1.0
    }
}
