package app.vela.ios.offline

import app.vela.core.data.OfflineAddressStore
import app.vela.core.data.OverpassEndpoints
import app.vela.core.platform.VelaHttp
import app.vela.core.util.ioDispatcher
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The keyless Overpass fetches an area download runs after its map pieces: an address index for a
 * readable radius around the frame. Android runs the same queries from `OverpassPois` in `:core`;
 * that file depends on OkHttp, so this is the iOS port over [VelaHttp]. A failed mirror returns
 * null, never an empty list, so "no answer" is not written as "no address here".
 */
internal object OfflineAreaData {
    private val json = Json { ignoreUnknownKeys = true }

    @Serializable
    private data class OvPoint(val lat: Double? = null, val lon: Double? = null)

    @Serializable
    private data class OvElement(
        val id: Long? = null,
        val lat: Double? = null,
        val lon: Double? = null,
        val center: OvPoint? = null,
        val tags: Map<String, String> = emptyMap(),
        val geometry: List<OvPoint> = emptyList(),
    )

    @Serializable
    private data class OvResp(val elements: List<OvElement> = emptyList())

    private const val ADDRESS_LIMIT = 20_000
    private const val STREET_LIMIT = 30_000
    private const val TIMEOUT_MS = 120_000L
    private const val SAMPLE_M = 120.0

    /** Every `addr:housenumber` point or building center in the box, or null when no mirror answered. */
    suspend fun addresses(http: VelaHttp, bounds: OfflineAreaBounds): List<OfflineAddressStore.Addr>? =
        withContext(ioDispatcher) {
            val bbox = "${bounds.south},${bounds.west},${bounds.north},${bounds.east}"
            val query = "[out:json][timeout:120];" +
                "(node[\"addr:housenumber\"]($bbox);way[\"addr:housenumber\"]($bbox););" +
                "out center $ADDRESS_LIMIT;"
            OverpassEndpoints.run(http, query, timeoutMillis = TIMEOUT_MS) { body ->
                json.decodeFromString<OvResp>(body.decodeToString()).elements.mapNotNull(::toAddr)
            }
        }

    /** One point every ~120 m on named vehicle roads, the fallback where houses are unmapped. */
    suspend fun streets(http: VelaHttp, bounds: OfflineAreaBounds): List<OfflineAddressStore.StreetPt>? =
        withContext(ioDispatcher) {
            val bbox = "${bounds.south},${bounds.west},${bounds.north},${bounds.east}"
            val query = "[out:json][timeout:120];" +
                "way[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|unclassified|" +
                "residential|living_street|service|road)(_link)?$\"][\"name\"]($bbox);" +
                "out geom $STREET_LIMIT;"
            OverpassEndpoints.run(http, query, timeoutMillis = TIMEOUT_MS) { body ->
                json.decodeFromString<OvResp>(body.decodeToString()).elements.flatMap(::toStreetPoints)
            }
        }

    private fun toAddr(el: OvElement): OfflineAddressStore.Addr? {
        val number = el.tags["addr:housenumber"] ?: return null
        val street = el.tags["addr:street"] ?: return null
        val lat = el.lat ?: el.center?.lat ?: return null
        val lng = el.lon ?: el.center?.lon ?: return null
        return OfflineAddressStore.Addr(
            id = "addr:${el.id ?: "$lat,$lng"}",
            housenumber = number,
            street = street,
            city = el.tags["addr:city"],
            lat = lat,
            lng = lng,
        )
    }

    private fun toStreetPoints(el: OvElement): List<OfflineAddressStore.StreetPt> {
        val name = el.tags["name"] ?: return emptyList()
        val points = el.geometry.mapNotNull { point ->
            val lat = point.lat
            val lng = point.lon
            if (lat != null && lng != null) lat to lng else null
        }
        if (points.isEmpty()) return emptyList()
        val out = ArrayList<OfflineAddressStore.StreetPt>()
        var lastLat = Double.NaN
        var lastLng = Double.NaN
        for ((index, point) in points.withIndex()) {
            val keep = index == 0 || index == points.lastIndex || lastLat.isNaN() ||
                distanceMeters(lastLat, lastLng, point.first, point.second) >= SAMPLE_M
            if (keep) {
                out += OfflineAddressStore.StreetPt(name, point.first, point.second)
                lastLat = point.first
                lastLng = point.second
            }
        }
        return out
    }

    private fun distanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val radius = 6_371_000.0
        val dLat = (lat2 - lat1) * kotlin.math.PI / 180
        val dLng = (lng2 - lng1) * kotlin.math.PI / 180
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * kotlin.math.PI / 180) * cos(lat2 * kotlin.math.PI / 180) *
            sin(dLng / 2) * sin(dLng / 2)
        return 2 * radius * asin(minOf(1.0, sqrt(a)))
    }
}
