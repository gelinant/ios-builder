package app.vela.ios.nav

import app.vela.core.data.OsmMaxspeed
import app.vela.core.data.OverpassEndpoints
import app.vela.core.model.LatLng
import app.vela.core.platform.VelaHttp
import app.vela.core.util.decodeFromBytes
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlinx.datetime.LocalDateTime
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.time.Instant

/**
 * The road under a free-driving car, read from OSM: its name, its route number and the posted
 * `maxspeed`. Free driving has no route to project onto, so the only honest source is the road
 * around the current fix. A point farther than [SNAP_M] from every drivable way answers null,
 * and a way without a parsable `maxspeed` keeps its name but reports no limit; nothing is
 * guessed from the road class or the country.
 */
data class FreeDriveRoad(
    val name: String?,
    val ref: String?,
    val limitKmh: Double?,
    val highway: String,
)

/** Reads the nearest drivable OSM way around a fix from Overpass. */
class FreeDriveRoadLookup(
    private val http: VelaHttp,
    private val nowMillis: () -> Long = { kotlin.time.Clock.System.now().toEpochMilliseconds() },
) {
    suspend fun roadAt(lat: Double, lng: Double): FreeDriveRoad? =
        OverpassEndpoints.run(http, FreeDriveRoads.query(lat, lng), TIMEOUT_MS) { body ->
            FreeDriveRoads.parse(
                body,
                lat,
                lng,
                Instant.fromEpochMilliseconds(nowMillis())
                    .toLocalDateTime(TimeZone.currentSystemDefault()),
            )
        }

    private companion object {
        const val TIMEOUT_MS = 8_000L
    }
}

/** The pure half of [FreeDriveRoadLookup]: query text and Overpass reply parsing. */
object FreeDriveRoads {
    /** A car more than this far from a road is not on it (Android's speed-limit snap is 20 m). */
    const val SNAP_M = 20.0
    private const val CORRIDOR_M = 60
    private const val MAX_WAYS = 120

    /** Ways a car may drive on. Footways, paths, cycleways and tracks never answer, so a footpath
     *  beside the road cannot lend its name or limit to the car. */
    private val DRIVABLE = setOf(
        "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
        "residential", "living_street", "service",
        "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link",
        "road",
    )

    /** The way with a `maxspeed` first, then every highway around the point, so an untagged street
     *  still answers its name. */
    fun query(lat: Double, lng: Double): String {
        val point = "$lat,$lng"
        val around = "(around:$CORRIDOR_M,$point)"
        return "[out:json][timeout:8];(" +
            "way[\"highway\"][\"maxspeed\"]$around;" +
            "way[\"highway\"]$around;" +
            ");out tags geom $MAX_WAYS;"
    }

    /** The nearest drivable way within [SNAP_M], or null when the reply has no such road. */
    fun parse(body: ByteArray, lat: Double, lng: Double, at: LocalDateTime): FreeDriveRoad? {
        val reply = runCatching { roadsJson.decodeFromBytes<RoadsResponse>(body) }.getOrNull() ?: return null
        val metersPerLng = 111_320.0 * cos(lat * PI / 180.0)
        var best: FreeDriveRoad? = null
        var bestDistance = SNAP_M
        var bestRank = Int.MAX_VALUE
        for (way in reply.elements) {
            val tags = way.tags.orEmpty()
            val highway = tags["highway"].orEmpty()
            if (highway !in DRIVABLE) continue
            val distance = distanceToWay(way.geometry.orEmpty(), lat, lng, metersPerLng) ?: continue
            val rank = classRank(highway)
            if (distance > bestDistance || (distance == bestDistance && rank >= bestRank)) continue
            bestDistance = distance
            bestRank = rank
            best = FreeDriveRoad(
                name = tags["name"]?.takeIf { it.isNotBlank() },
                ref = tags["ref"]?.takeIf { it.isNotBlank() },
                limitKmh = OsmMaxspeed.fromTags(
                    tags["maxspeed"],
                    tags["maxspeed:forward"],
                    tags["maxspeed:backward"],
                    tags["maxspeed:conditional"],
                    at,
                ),
                highway = highway,
            )
        }
        return best
    }

    /** Meters from the point to the closest segment of the way, or null with fewer than two points. */
    private fun distanceToWay(
        points: List<RoadPoint>,
        lat: Double,
        lng: Double,
        metersPerLng: Double,
    ): Double? {
        if (points.size < 2) return null
        var best = Double.MAX_VALUE
        for (index in 0 until points.size - 1) {
            val aLat = points[index].lat ?: continue
            val aLng = points[index].lon ?: continue
            val bLat = points[index + 1].lat ?: continue
            val bLng = points[index + 1].lon ?: continue
            val ax = (aLng - lng) * metersPerLng
            val ay = (aLat - lat) * METERS_PER_LAT
            val bx = (bLng - lng) * metersPerLng
            val by = (bLat - lat) * METERS_PER_LAT
            if (!ax.isFinite() || !ay.isFinite() || !bx.isFinite() || !by.isFinite()) continue
            val dx = bx - ax
            val dy = by - ay
            val length2 = dx * dx + dy * dy
            val t = if (length2 == 0.0) 0.0 else (-(ax * dx + ay * dy) / length2).coerceIn(0.0, 1.0)
            best = minOf(best, hypot(ax + t * dx, ay + t * dy))
        }
        return best.takeIf { it != Double.MAX_VALUE }
    }

    /** Bigger roads win an exact tie at the same distance; the order is only a tie-break. */
    private fun classRank(highway: String): Int = when (highway) {
        "motorway" -> 0
        "trunk" -> 1
        "primary" -> 2
        "secondary" -> 3
        "tertiary" -> 4
        "unclassified", "road" -> 5
        "residential" -> 6
        "living_street" -> 7
        "service" -> 8
        else -> 9 // links
    }

    private const val METERS_PER_LAT = 111_320.0
    private val roadsJson = Json { ignoreUnknownKeys = true }
}

@Serializable
private data class RoadsResponse(val elements: List<RoadWay> = emptyList())

@Serializable
private data class RoadWay(
    val tags: Map<String, String>? = null,
    val geometry: List<RoadPoint>? = null,
)

@Serializable
private data class RoadPoint(val lat: Double? = null, val lon: Double? = null)
