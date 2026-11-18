package app.vela.ios.nav

import app.vela.core.data.AlprCamera
import app.vela.core.data.BridgeAlerts
import app.vela.core.data.NdwBridgeOpenings
import app.vela.core.data.OverpassAlprCameras
import app.vela.core.data.OverpassEndpoints
import app.vela.core.data.OverpassSpeedCameras
import app.vela.core.data.OsmMaxspeed
import app.vela.core.data.SpeedCamera
import app.vela.core.model.LatLng
import app.vela.core.model.Route
import app.vela.core.nav.CameraAlerts
import app.vela.core.nav.RouteProjection
import app.vela.core.platform.VelaHttp
import app.vela.core.util.Fmt
import app.vela.core.util.decodeFromBytes
import app.vela.core.util.mathRound
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlin.time.Instant
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The kind of road alert shown by the navigation chrome and spoken through the nav voice. */
enum class NavRoadAlertKind { SPEED_CAMERA, ALPR_CAMERA, SPEEDING, BRIDGE_OPEN, BRIDGE_PLANNED }

/** One group of cameras at the same approach point on a route. */
data class NavCameraGroup(
    val kind: NavRoadAlertKind,
    val atMeters: Double,
    val count: Int,
)

/** A posted limit covering a contiguous part of the route. */
data class NavSpeedLimitSpan(
    val startMeters: Double,
    val endMeters: Double,
    val limitKmh: Double,
)

/** All road data loaded for one route. Empty lists mean unavailable or no known data. */
data class NavRouteData(
    val cameraGroups: List<NavCameraGroup> = emptyList(),
    val speedLimits: List<NavSpeedLimitSpan> = emptyList(),
    /** Movable bridges on the line with their NDW openings; empty outside the Netherlands. */
    val bridges: List<BridgeAlerts.OnRoute> = emptyList(),
) {
    fun speedLimitAt(traveledMeters: Double): Double? = speedLimits
        .filter { traveledMeters >= it.startMeters - 1.0 && traveledMeters <= it.endMeters + 1.0 }
        .minByOrNull { it.endMeters - it.startMeters }
        ?.limitKmh
}

/** A tagged road geometry before it is projected onto the driven route. */
data class NavSpeedLimitRoad(val points: List<LatLng>, val limitKmh: Double)

/** Loads camera and posted-limit data once for a route. */
interface NavAlertProvider {
    suspend fun load(route: Route): NavRouteData

    companion object {
        val EMPTY: NavAlertProvider = object : NavAlertProvider {
            override suspend fun load(route: Route) = NavRouteData()
        }
    }
}

/** Pure projection and grouping shared by the production provider and deterministic tests. */
object NavRouteDataBuilder {
    fun build(
        route: Route,
        speedCameras: List<SpeedCamera> = emptyList(),
        alprCameras: List<AlprCamera> = emptyList(),
        speedLimitRoads: List<NavSpeedLimitRoad> = emptyList(),
        bridges: List<BridgeAlerts.OnRoute> = emptyList(),
    ): NavRouteData {
        val polyline = route.polyline
        if (polyline.size < 2) return NavRouteData()
        val cumulative = RouteProjection.cumulative(polyline)
        val speedMeters = speedCameras.distinctBy { cameraKey(it.loc) }.mapNotNull {
            RouteProjection.alongMeters(polyline, cumulative, it.loc)
        }.sorted()
        val alprMeters = alprCameras.distinctBy { cameraKey(it.loc) }.mapNotNull {
            RouteProjection.alongMeters(polyline, cumulative, it.loc, ALPR_ON_ROUTE_M)
        }.sorted()
        val cameras = CameraAlerts.group(speedMeters).map {
            NavCameraGroup(NavRoadAlertKind.SPEED_CAMERA, it.atM, it.count)
        } + CameraAlerts.group(alprMeters).map {
            NavCameraGroup(NavRoadAlertKind.ALPR_CAMERA, it.atM, it.count)
        }
        val limits = ArrayList<NavSpeedLimitSpan>()
        for (road in speedLimitRoads) {
            for (index in 0 until road.points.size - 1) {
                val first = RouteProjection.alongMeters(polyline, cumulative, road.points[index], LIMIT_ON_ROUTE_M)
                val second = RouteProjection.alongMeters(polyline, cumulative, road.points[index + 1], LIMIT_ON_ROUTE_M)
                if (first == null || second == null || abs(first - second) > MAX_LIMIT_SPAN_M) continue
                val start = minOf(first, second)
                val end = maxOf(first, second)
                if (end - start >= 0.5) limits += NavSpeedLimitSpan(start, end, road.limitKmh)
            }
        }
        return NavRouteData(
            cameraGroups = cameras.sortedBy { it.atMeters },
            speedLimits = limits.sortedWith(compareBy({ it.startMeters }, { it.endMeters })),
            bridges = bridges.sortedBy { it.atM },
        )
    }

    private fun cameraKey(point: LatLng): Pair<Int, Int> =
        (point.lat * 100_000.0).roundToInt() to (point.lng * 100_000.0).roundToInt()

    private const val ALPR_ON_ROUTE_M = 45.0
    private const val LIMIT_ON_ROUTE_M = 45.0
    private const val MAX_LIMIT_SPAN_M = 2_000.0
}

/** Overpass-only route data. The Android bundled DeFlock file is not currently shipped on iOS. */
class OverpassNavAlertProvider(
    private val http: VelaHttp,
    private val nowMillis: () -> Long = { kotlin.time.Clock.System.now().toEpochMilliseconds() },
) : NavAlertProvider {
    override suspend fun load(route: Route): NavRouteData = coroutineScope {
        val speed = async { bestEffort { OverpassSpeedCameras.fetchAlongCorridor(http, route.polyline) } }
        val alpr = async { bestEffort { OverpassAlprCameras.fetchAlong(http, route.polyline) } }
        val limits = async { bestEffort { fetchSpeedLimits(route.polyline) } }
        val bridges = async { bestEffort { fetchBridges(route.polyline) } }
        withContext(Dispatchers.Default) {
            NavRouteDataBuilder.build(
                route = route,
                speedCameras = speed.await().orEmpty(),
                alprCameras = alpr.await().orEmpty(),
                speedLimitRoads = limits.await().orEmpty(),
                bridges = bridges.await().orEmpty(),
            )
        }
    }

    private suspend fun <T> bestEffort(call: suspend () -> T): T? = try {
        call()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        null
    }

    /** Movable bridges on the line from NDW. A route that does not enter the Netherlands never
     *  asks the feed, so an ordinary trip pays nothing for this. */
    private suspend fun fetchBridges(polyline: List<LatLng>): List<BridgeAlerts.OnRoute>? {
        if (polyline.size < 2 || polyline.none { NdwBridgeOpenings.inNetherlands(it) }) return emptyList()
        val all = NdwBridgeOpenings.fetch(http) ?: return null
        val cumulative = withContext(Dispatchers.Default) { RouteProjection.cumulative(polyline) }
        return all.groupBy { it.loc }.mapNotNull { (loc, openings) ->
            RouteProjection.alongMeters(polyline, cumulative, loc, BRIDGE_ON_ROUTE_M)
                ?.let { BridgeAlerts.OnRoute(it, openings) }
        }
    }

    private suspend fun fetchSpeedLimits(polyline: List<LatLng>): List<NavSpeedLimitRoad>? {
        if (polyline.size < 2) return emptyList()
        val points = if (polyline.size <= MAX_ROUTE_POINTS) polyline else {
            val stride = (polyline.size - 1).toDouble() / (MAX_ROUTE_POINTS - 1)
            (0 until MAX_ROUTE_POINTS).map {
                polyline[(it * stride).mathRound().toInt().coerceAtMost(polyline.size - 1)]
            }
        }
        val coordinates = points.joinToString(",") { Fmt.fixed(it.lat, 5) + "," + Fmt.fixed(it.lng, 5) }
        val around = "(around:$LIMIT_CORRIDOR_M,$coordinates)"
        val query = "[out:json][timeout:25];(" +
            "way[\"maxspeed\"]$around;" +
            "way[\"maxspeed:forward\"]$around;" +
            "way[\"maxspeed:backward\"]$around;" +
            "way[\"maxspeed:conditional\"]$around;" +
            ");out geom $MAX_WAYS;"
        val at = Instant.fromEpochMilliseconds(nowMillis()).toLocalDateTime(TimeZone.currentSystemDefault())
        return OverpassEndpoints.run(http, query, OverpassAlprCameras.CALL_TIMEOUT_MS) { body ->
            speedLimitJson.decodeFromBytes<SpeedLimitResponse>(body).elements.mapNotNull { way ->
                val tags = way.tags.orEmpty()
                val limit = OsmMaxspeed.fromTags(
                    tags["maxspeed"], tags["maxspeed:forward"], tags["maxspeed:backward"],
                    tags["maxspeed:conditional"], at,
                ) ?: return@mapNotNull null
                val pointsOnRoad = way.geometry.orEmpty().mapNotNull { point ->
                    val lat = point.lat ?: return@mapNotNull null
                    val lng = point.lon ?: return@mapNotNull null
                    LatLng(lat, lng)
                }
                if (pointsOnRoad.size >= 2) NavSpeedLimitRoad(pointsOnRoad, limit) else null
            }
        }
    }

    private companion object {
        const val MAX_ROUTE_POINTS = 250
        const val LIMIT_CORRIDOR_M = 100
        const val MAX_WAYS = 2_000
        /** Android projects NDW bridges onto the line with the same 30 m corridor. */
        const val BRIDGE_ON_ROUTE_M = 30.0
        val speedLimitJson = Json { ignoreUnknownKeys = true }
    }
}

@Serializable
private data class SpeedLimitResponse(val elements: List<SpeedLimitWay> = emptyList())

@Serializable
private data class SpeedLimitWay(
    val tags: Map<String, String>? = null,
    val geometry: List<SpeedLimitPoint>? = null,
)

@Serializable
private data class SpeedLimitPoint(val lat: Double? = null, val lon: Double? = null)
