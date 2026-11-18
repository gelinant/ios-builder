package app.vela.ios.layers

import app.vela.core.data.OverpassEndpoints
import app.vela.core.platform.VelaHttp
import app.vela.core.util.decodeFromBytes
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sinh
import kotlin.math.sqrt

/** One OSM tree (`node[natural=tree]`).
 *
 *  [heightM] and [crownM] are 0 when the source carries no usable value. A 0 crown means the
 *  renderer uses a fixed visual disc, never a guessed "tall tree": missing data stays missing.
 */
data class TreePoint(
    val lat: Double,
    val lng: Double,
    val heightM: Double = 0.0,
    val crownM: Double = 0.0,
)

/** A fetch and cache area. [TreeBox.contains] is inclusive on every edge. */
data class TreeBox(
    val south: Double,
    val west: Double,
    val north: Double,
    val east: Double,
) {
    val centerLat: Double get() = (south + north) / 2
    val centerLng: Double get() = (west + east) / 2

    fun contains(s: Double, w: Double, n: Double, e: Double): Boolean =
        s >= south && w >= west && n <= north && e <= east
}

/**
 * The tree layer's policy, kept apart from the picking store so it is testable without a network
 * or a map: the Overpass query and parser, the z14 tile-sized cache box, the 30 minute cache, the
 * z17 gate and the per-screen cap. Nothing here draws.
 */
object Trees {
    /** Shared with Swift through `LayersStore`; Android has no key for this layer. */
    const val KEY = "trees_canopy_on"

    /** Isolated trees are unreadable below this zoom and would be confetti. */
    const val MIN_ZOOM = 17.0

    /** Absolute ceiling for one viewport. */
    const val CAP = 500

    /** The per-screen density floor and slope: a small view still gets a legible scatter. */
    const val MIN_PER_SCREEN = 120
    const val PER_KM2 = 320.0

    /** A successful answer is reused for half an hour per tile-sized box. */
    const val CACHE_MS = 30L * 60 * 1000

    /** The cache holds a handful of neighbouring tiles; older entries fall out. */
    const val CACHE_ENTRIES = 8

    /** z14 keeps one cache box near two kilometres wide at mid latitude. */
    const val TILE_ZOOM = 14

    /** Ask for more than the cap so the nearest 500 survive; the towers bound the response. */
    const val QUERY_LIMIT = 1200

    /** Each Overpass mirror gets the same deadline as the camera query: a dead one is skipped. */
    const val CALL_TIMEOUT_MS = 15_000L

    private val json = Json { ignoreUnknownKeys = true }

    fun visible(zoom: Double): Boolean = zoom + 0.001 >= MIN_ZOOM

    /**
     * The box fetched and cached for a view center: the z14 slippy tile around [lat]/[lng],
     * padded by a quarter of its span on each side. At z17 the viewport fits inside it, so a
     * small pan does not start a new request.
     */
    fun boxFor(lat: Double, lng: Double): TreeBox {
        val n = 1 shl TILE_ZOOM
        val clampedLng = lng.coerceIn(-180.0, 179.999999)
        val clampedLat = lat.coerceIn(-85.05112878, 85.05112878)
        val x = floor((clampedLng + 180.0) / 360.0 * n).toInt().coerceIn(0, n - 1)
        val rad = clampedLat * PI / 180.0
        val y = floor((1.0 - ln(kotlin.math.tan(rad) + 1.0 / cos(rad)) / PI) / 2.0 * n)
            .toInt().coerceIn(0, n - 1)
        val west = x.toDouble() / n * 360.0 - 180.0
        val east = (x + 1).toDouble() / n * 360.0 - 180.0
        val north = tileLat(y.toDouble(), n)
        val south = tileLat((y + 1).toDouble(), n)
        val padLat = (north - south) * 0.25
        val padLng = (east - west) * 0.25
        return TreeBox(
            south = (south - padLat).coerceAtLeast(-85.05112878),
            west = (west - padLng).coerceAtLeast(-180.0),
            north = (north + padLat).coerceAtMost(85.05112878),
            east = (east + padLng).coerceAtMost(180.0),
        )
    }

    /** The z/x/y cell a box belongs to, used as the cache key. */
    fun tileKey(lat: Double, lng: Double): String {
        val n = 1 shl TILE_ZOOM
        val clampedLng = lng.coerceIn(-180.0, 179.999999)
        val clampedLat = lat.coerceIn(-85.05112878, 85.05112878)
        val x = floor((clampedLng + 180.0) / 360.0 * n).toInt().coerceIn(0, n - 1)
        val rad = clampedLat * PI / 180.0
        val y = floor((1.0 - ln(kotlin.math.tan(rad) + 1.0 / cos(rad)) / PI) / 2.0 * n)
            .toInt().coerceIn(0, n - 1)
        return "$TILE_ZOOM/$x/$y"
    }

    /** The tile's north edge in degrees for a slippy y index. */
    private fun tileLat(y: Double, n: Int): Double =
        atan(sinh(PI * (1.0 - 2.0 * y / n))) * 180.0 / PI

    /**
     * The Overpass answer for [box], or null on failure. Mirrors are tried in order with the same
     * failover and deadline as the camera fetches. A successful parse may return zero trees, which
     * is a valid, cacheable answer; a failure never is.
     */
    suspend fun fetch(http: VelaHttp, box: TreeBox): List<TreePoint>? {
        val query = "[out:json][timeout:25];" +
            "node[\"natural\"=\"tree\"](${fmt(box.south)},${fmt(box.west)}," +
            "${fmt(box.north)},${fmt(box.east)});out body $QUERY_LIMIT;"
        val parsed = OverpassEndpoints.run(http, query, CALL_TIMEOUT_MS) { body -> parse(body) }
            ?: return null
        return capNearest(parsed, box.centerLat, box.centerLng, CAP)
    }

    /** Parses an Overpass JSON body. Invalid coordinates are dropped, unknown tags ignored. */
    fun parse(body: ByteArray): List<TreePoint> {
        val response = try {
            json.decodeFromBytes<TreeResponse>(body)
        } catch (_: Exception) {
            return emptyList()
        }
        val out = ArrayList<TreePoint>(response.elements.size)
        for (node in response.elements) {
            val lat = node.lat ?: continue
            val lng = node.lon ?: continue
            if (!lat.isFinite() || !lng.isFinite()) continue
            if (lat !in -90.0..90.0 || lng !in -180.0..180.0) continue
            val tags = node.tags.orEmpty()
            val height = number(tags["height"])
            val taggedCrown = number(tags["diameter_crown"])
            // A tagged crown is a measurement. Height alone gives a documented estimate, half the
            // height. Neither tag means 0 and the renderer keeps its neutral visual size.
            val crown = when {
                taggedCrown > 0 -> taggedCrown.coerceIn(1.0, 40.0)
                height > 0 -> (height * 0.5).coerceIn(1.5, 20.0)
                else -> 0.0
            }
            out += TreePoint(lat, lng, height, crown)
        }
        return out
    }

    /**
     * The trees to draw for this viewport. Below z17 nothing is returned, so a caller that forgot
     * the map-side gate still cannot produce confetti. The per-screen ceiling follows the view
     * area, and the nearest trees to the center win at the cap.
     */
    fun limit(
        points: List<TreePoint>,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        zoom: Double,
    ): List<TreePoint> {
        if (!visible(zoom)) return emptyList()
        val inside = points.filter { it.lat in south..north && it.lng in west..east }
        val areaKm2 = areaKm2(south, west, north, east)
        val allowed = min(CAP, max(MIN_PER_SCREEN, (areaKm2 * PER_KM2).roundToInt()))
        if (inside.size <= allowed) return inside
        val centerLat = (south + north) / 2
        val centerLng = (west + east) / 2
        return capNearest(inside, centerLat, centerLng, allowed)
    }

    /** The deterministic Debug answer for a UI scenario: no network, eight tagged and untagged trees. */
    fun fixture(box: TreeBox): List<TreePoint> {
        val lat = box.centerLat
        val lng = box.centerLng
        val offsets = listOf(
            0.0 to 0.0, 0.00035 to 0.0002, -0.0003 to 0.00045, 0.0002 to -0.0004,
            -0.00045 to -0.0003, 0.00055 to -0.0001, -0.0001 to 0.0006, 0.0004 to 0.00055,
        )
        val crowns = listOf(9.0, 0.0, 14.0, 6.0, 0.0, 11.0, 7.0, 18.0)
        return offsets.mapIndexed { index, (dLat, dLng) ->
            val crown = crowns[index]
            TreePoint(
                lat = lat + dLat,
                lng = lng + dLng,
                heightM = if (crown > 0) crown * 1.7 else 0.0,
                crownM = crown,
            )
        }
    }

    /** Cumulative box area in square kilometres at the box's mean latitude. */
    fun areaKm2(south: Double, west: Double, north: Double, east: Double): Double {
        val mid = ((south + north) / 2) * PI / 180.0
        val height = abs(north - south) * 111.32
        val width = abs(east - west) * 111.32 * cos(mid)
        return height * width
    }

    private fun capNearest(
        items: List<TreePoint>,
        centerLat: Double,
        centerLng: Double,
        cap: Int,
    ): List<TreePoint> {
        if (items.size <= cap) return items
        // Keep by index, not by value: identical coordinates are legitimate duplicates in OSM.
        val keep = items.indices
            .sortedBy { distanceM(centerLat, centerLng, items[it].lat, items[it].lng) }
            .take(cap)
            .toHashSet()
        return items.filterIndexed { index, _ -> index in keep }
    }

    private fun distanceM(lat1: Double, lng1: Double, lat2: Double, lng2: Double): Double {
        val dLat = (lat1 - lat2) * 111_320.0
        val dLng = (lng1 - lng2) * 111_320.0 * cos(((lat1 + lat2) / 2) * PI / 180.0)
        return sqrt(dLat * dLat + dLng * dLng)
    }

    /** First positive number in an OSM value (`12`, `12.5 m`, `12,5`), 0 otherwise. */
    private fun number(raw: String?): Double {
        if (raw.isNullOrBlank()) return 0.0
        val match = NUMBER.find(raw) ?: return 0.0
        val value = match.value.replace(',', '.').toDoubleOrNull() ?: return 0.0
        return if (value.isFinite() && value > 0) value else 0.0
    }

    private val NUMBER = Regex("-?\\d+(?:[.,]\\d+)?")

    private fun fmt(value: Double): String {
        val rounded = (value * 1_000_000).roundToInt() / 1_000_000.0
        return rounded.toString()
    }

    @Serializable
    private data class TreeResponse(val elements: List<TreeNode> = emptyList())

    @Serializable
    private data class TreeNode(
        val lat: Double? = null,
        val lon: Double? = null,
        val tags: Map<String, String>? = null,
    )
}

/**
 * A 30 minute, per-tile cache of successful tree answers. [get] only answers when a fresh entry
 * contains the requested box, so a view that moved outside the box starts a new request instead
 * of drawing trees from the wrong place.
 */
class TreeCache(
    private val ttlMs: Long = Trees.CACHE_MS,
    private val maxEntries: Int = Trees.CACHE_ENTRIES,
) {
    private data class Entry(
        val box: TreeBox,
        val points: List<TreePoint>,
        val atMs: Long,
    )

    private val entries = LinkedHashMap<String, Entry>()

    fun get(south: Double, west: Double, north: Double, east: Double, nowMs: Long): List<TreePoint>? {
        val key = Trees.tileKey((south + north) / 2, (west + east) / 2)
        val entry = entries[key] ?: return null
        if (nowMs - entry.atMs !in 0 until ttlMs) {
            entries.remove(key)
            return null
        }
        if (!entry.box.contains(south, west, north, east)) return null
        return entry.points
    }

    fun put(box: TreeBox, points: List<TreePoint>, nowMs: Long) {
        val key = Trees.tileKey(box.centerLat, box.centerLng)
        entries.remove(key)
        entries[key] = Entry(box, points, nowMs)
        while (entries.size > maxEntries) {
            val oldest = entries.keys.firstOrNull() ?: break
            entries.remove(oldest)
        }
    }

    fun clear() = entries.clear()

    val size: Int get() = entries.size
}
