package app.vela.ios.streetview

import app.vela.core.model.StreetViewPano
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.floor
import kotlin.math.tan

/**
 * One level of a panorama's equirectangular pyramid, sized from the pano's OWN level list.
 *
 * Modern car captures are 512 * 2^z wide; pre-2016 captures are 416 * 2^z and sometimes stop
 * early. Sizing a grid from the modern default asked for tiles past an old capture's edge, which
 * arrived blank or failed (live report on Android, 2026-07-16). [columns] and [rows] therefore
 * always come from [width] and [height].
 */
data class StreetViewLevel(
    val zoom: Int,
    val width: Int,
    val height: Int,
    val tileSize: Int,
    val columns: Int,
    val rows: Int,
)

/** One tile of [StreetViewLevel], addressed as the tile endpoint expects. */
data class StreetViewTileRef(val zoom: Int, val x: Int, val y: Int)

/**
 * The tile grid, the keyless tile URL, the cache key and the visible-tile selection of the iOS
 * Street View viewer. Shared by the renderer and the tests; the Android viewer carries the same
 * constants in `app/streetview/StreetViewTiles.kt`.
 *
 * The equirectangular image is 2:1: at zoom z it is `width x height` from the pano's level list,
 * cut into [StreetViewLevel.tileSize] squares. The texture's compass frame is Google's: the
 * capture heading sits at the image center (u = 0.5, v = 0.5). The renderer's yaw 0 looks at
 * u = 0.75, so a compass bearing B maps to yaw `B - panoHeading - 90`. Use [yawForCompass] and
 * [compassForYaw] rather than feeding bearings into a raw yaw.
 */
object StreetViewTiles {
    /** The consumer equirect tile endpoint; keyless, JPEG, referer-gated (SPEC 10.7). */
    const val URL_TEMPLATE =
        "https://streetviewpixels-pa.googleapis.com/v1/tile" +
            "?cb_client=maps_sv.tactile&panoid={PANOID}&x={X}&y={Y}&zoom={ZOOM}&nbt=1&fover=2"

    /** What Android's image loader sends to the tile host: Google's referer, no cookies. */
    const val REFERER = "https://www.google.com/"
    const val ACCEPT = "image/avif,image/webp,image/apng,*/*;q=0.8"

    /** The base sphere's texture: small enough to arrive fast, 2 tiles on a modern pano. */
    const val BASE_MAX_WIDTH = 1024

    /** Detail tiles stay at or below 4096 wide, as on Android: 32 tiles for the whole sphere,
     *  but only the ones around the viewport are fetched. */
    const val DETAIL_MAX_WIDTH = 4096

    private const val MODERN_LEVELS = 6

    fun url(panoId: String, x: Int, y: Int, zoom: Int): String = URL_TEMPLATE
        .replace("{PANOID}", panoId)
        .replace("{X}", x.toString())
        .replace("{Y}", y.toString())
        .replace("{ZOOM}", zoom.toString())

    /** A safe file name, also usable in tests. Pano ids are [A-Za-z0-9_-] as the parser requires. */
    fun cacheKey(panoId: String, zoom: Int, x: Int, y: Int): String =
        "${safe(panoId)}-$zoom-$x-$y"

    /** The level whose width is the largest at or below [maxWidth], else zoom 0. */
    fun level(pano: StreetViewPano, maxWidth: Int): StreetViewLevel {
        val dims = levelsOf(pano)
        var chosen = 0
        for (i in dims.indices) if (dims[i].first <= maxWidth) chosen = i
        val (width, height) = dims[chosen]
        val ts = pano.tileSize.coerceAtLeast(1)
        return StreetViewLevel(
            zoom = chosen,
            width = width,
            height = height,
            tileSize = ts,
            columns = (width + ts - 1) / ts,
            rows = (height + ts - 1) / ts,
        )
    }

    fun baseLevel(pano: StreetViewPano): StreetViewLevel = level(pano, BASE_MAX_WIDTH)

    fun detailLevel(pano: StreetViewPano): StreetViewLevel = level(pano, DETAIL_MAX_WIDTH)

    /** The pano's own pyramid, or the modern default when the reply carried none. */
    internal fun levelsOf(pano: StreetViewPano): List<Pair<Int, Int>> {
        val own = pano.levelDims.filter { it.first > 0 && it.second > 0 }
        if (own.isNotEmpty()) return own
        return List(MODERN_LEVELS) { z -> (512 shl z) to (256 shl z) }
    }

    /** Renderer yaw (degrees) that looks at compass [compassDeg]. See the class comment. */
    fun yawForCompass(compassDeg: Double, panoHeadingDeg: Double): Double =
        normalizeDeg(compassDeg - panoHeadingDeg - 90.0)

    /** Compass bearing (degrees) the renderer's [yawDeg] faces. */
    fun compassForYaw(yawDeg: Double, panoHeadingDeg: Double): Double =
        normalizeDeg(yawDeg + panoHeadingDeg + 90.0)

    /**
     * The tiles at [level] that overlap the current view. [yawDeg] and [pitchDeg] are renderer
     * angles, [fovXDeg] the canonical horizontal field of view and [aspect] the pane's width over
     * height (the vertical field of view is derived from them, as on Android). [margin] widens the
     * set by that many tiles on every side, so a small drag does not empty it. Columns wrap around
     * the 360 degree seam; rows clamp at the poles.
     */
    fun visibleTiles(
        level: StreetViewLevel,
        yawDeg: Double,
        fovXDeg: Double,
        pitchDeg: Double,
        aspect: Double,
        margin: Int,
    ): List<StreetViewTileRef> {
        val cols = level.columns.coerceAtLeast(1)
        val rows = level.rows.coerceAtLeast(1)
        val a = aspect.coerceAtLeast(0.05)
        val vFov = 2.0 * atan(tan(fovXDeg / 2.0 * PI / 180.0) / a) * 180.0 / PI
        val uCenter = 0.75 + yawDeg / 360.0
        val uHalf = fovXDeg / 720.0
        val vCenter = 0.5 - pitchDeg / 180.0
        val vHalf = vFov / 360.0
        val m = margin.coerceAtLeast(0)

        val startCol = floor((uCenter - uHalf) * cols).toInt() - m
        val endCol = floor((uCenter + uHalf) * cols).toInt() + m
        val startRow = floor((vCenter - vHalf) * rows).toInt() - m
        val endRow = floor((vCenter + vHalf) * rows).toInt() + m

        val out = ArrayList<StreetViewTileRef>()
        val seen = HashSet<Int>()
        for (x in startCol..endCol) {
            val wrapped = ((x % cols) + cols) % cols
            if (!seen.add(wrapped)) continue
            for (y in startRow..endRow) {
                if (y < 0 || y >= rows) continue
                out += StreetViewTileRef(level.zoom, wrapped, y)
            }
        }
        return out
    }

    private fun normalizeDeg(d: Double): Double {
        val v = d % 360.0
        return if (v < 0) v + 360.0 else v
    }

    private fun safe(id: String): String =
        id.map { c -> if (c.isLetterOrDigit() || c == '-' || c == '_') c else '_' }.joinToString("")
}
