package app.vela.core.data

import app.vela.core.model.LatLng
import app.vela.core.platform.VelaHttp
import app.vela.core.util.Fmt
import app.vela.core.util.decodeFromBytes
import app.vela.core.util.mathRound
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** A fixed speed-enforcement camera at [loc] (OSM `highway=speed_camera`). */
data class SpeedCamera(val loc: LatLng)

@Serializable
private data class SpeedCamResp(val elements: List<SpeedCamNode> = emptyList())

@Serializable
private data class SpeedCamNode(val lat: Double? = null, val lon: Double? = null)

/**
 * Fixed radar/speed cameras from Overpass (issue #229) - the third sibling of
 * [OverpassTrafficSignals] and [OverpassAlprCameras]: keyless, per padded viewport, area-cached by
 * the caller, failover across mirrors, stream-parsed. Fixed installations only; mobile speed traps
 * need a live crowd service, which the keyless model has no source for. Coverage is OSM's - dense
 * in Europe where fixed cameras are common, sparse in US states that ban them.
 */
object OverpassSpeedCameras {
    private val json = Json { ignoreUnknownKeys = true }

    // Same bounded failover rationale as OverpassAlprCameras: a 15 s call per endpoint (and on
    // Android an 8 s connect, 15 s read client, `OpenServicesHttp.overpass`) so a dead mirror is
    // abandoned fast enough to reach a live one. [http] is that client.

    /** Speed-camera nodes in a bounding box. Null on FAILURE, a (possibly empty) list on a
     *  successful parse - the caller area-caches success only, so failures retry. */
    suspend fun fetchInBox(
        http: VelaHttp,
        south: Double, west: Double, north: Double, east: Double,
        limit: Int = 4000,
    ): List<SpeedCamera>? {
        val box = "($south,$west,$north,$east)"
        // `out body`, never `out tags` - `out tags` omits a node's lat/lon (the empty-layer trap
        // the ALPR fetcher hit).
        val query = "[out:json][timeout:25];node[\"highway\"=\"speed_camera\"]$box;out body $limit;"
        return OverpassEndpoints.run(http, query, OverpassAlprCameras.CALL_TIMEOUT_MS) { body ->
            val parsed = json.decodeFromBytes<SpeedCamResp>(body)
            parsed.elements.mapNotNull { n ->
                val lat = n.lat ?: return@mapNotNull null
                val lng = n.lon ?: return@mapNotNull null
                SpeedCamera(LatLng(lat, lng))
            }
        }
    }

    /**
     * Speed cameras within a corridor around a driven route (issue #229, the spoken approach
     * warning). Sibling of `OverpassTrafficSignals.fetchControlsAlongCorridor` and fetched the same
     * way: ONE query per route rather than per viewport, because during a drive the moving camera
     * crosses a cached box constantly and refetches against sometimes-dead mirrors.
     *
     * [radiusM] is wider than the controls corridor (a camera can sit on a gantry or a verge set
     * back from the centerline, and a missed warning is the failure that matters here); the caller
     * still projects each hit onto the route and drops anything not genuinely on it.
     */
    suspend fun fetchAlongCorridor(
        http: VelaHttp,
        polyline: List<LatLng>,
        radiusM: Int = 150,
        maxPts: Int = 250,
        limit: Int = 2000,
    ): List<SpeedCamera>? {
        if (polyline.size < 2) return emptyList()
        // Sampled to bound the GET URL - an unsampled polyline makes a URL the mirrors reject.
        val pts = if (polyline.size <= maxPts) polyline else {
            val stride = (polyline.size - 1).toDouble() / (maxPts - 1)
            (0 until maxPts).map { polyline[(it * stride).mathRound().toInt().coerceAtMost(polyline.size - 1)] }
        }
        val coords = pts.joinToString(",") { Fmt.fixed(it.lat, 5) + "," + Fmt.fixed(it.lng, 5) }
        val around = "(around:$radiusM,$coords)"
        val query = "[out:json][timeout:25];node[\"highway\"=\"speed_camera\"]$around;out body $limit;"
        return OverpassEndpoints.run(http, query, OverpassAlprCameras.CALL_TIMEOUT_MS) { body ->
            json.decodeFromBytes<SpeedCamResp>(body).elements.mapNotNull { n ->
                val lat = n.lat ?: return@mapNotNull null
                val lng = n.lon ?: return@mapNotNull null
                SpeedCamera(LatLng(lat, lng))
            }
        }
    }
}
