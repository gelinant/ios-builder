package app.vela.ios.offline

import app.vela.core.offline.RegionPolys
import app.vela.core.offline.RoutingRegion
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.tan

/**
 * The area picker's geometry and estimate. Android draws a fixed frame over the map (pan and pinch
 * choose what it covers) with the same inset fractions, so the rectangle the user sees is the one
 * these helpers describe. The insets are fractions of the viewport, measured from each edge.
 */
data class OfflineAreaInsets(
    val left: Double = 0.07,
    val right: Double = 0.07,
    val top: Double = 0.18,
    val bottom: Double = 0.34,
)

/** A rectangle on the map. Latitude is linear in Mercator y, as in the Android picker. */
data class OfflineAreaBounds(
    val south: Double,
    val west: Double,
    val north: Double,
    val east: Double,
) {
    val centerLat: Double get() = (south + north) / 2
    val centerLng: Double get() = (west + east) / 2

    /** The box widened to at least [minSpan] degrees around its center, for address coverage. */
    fun padded(minSpan: Double): OfflineAreaBounds = OfflineAreaBounds(
        south = minOf(south, centerLat - minSpan / 2),
        west = minOf(west, centerLng - minSpan / 2),
        north = maxOf(north, centerLat + minSpan / 2),
        east = maxOf(east, centerLng + minSpan / 2),
    )
}

/** What an area download should include. Persisted under the Android-compatible places key. */
data class OfflineAreaPreferences(
    val places: Boolean = true,
    val cameras: Boolean = true,
    val addresses: Boolean = true,
) {
    companion object {
        const val KEY_PLACES = "offline_places_with_downloads"
        const val KEY_CAMERAS = "offline_area_cameras"
        const val KEY_ADDRESSES = "offline_area_addresses"
    }
}

/**
 * The picker's live answer: what covers the frame, what it will download, whether the volume can
 * hold it, and why not when it cannot. Sizes are manifest estimates, not measured bytes.
 */
data class OfflineAreaPlan(
    val regionId: String?,
    val regionName: String,
    val installed: Boolean,
    val estimatedMb: Int,
    val neededBytes: Long,
    val freeBytes: Long,
    val fits: Boolean,
    val tooLarge: Boolean,
    val reasonKey: String,
    val south: Double,
    val west: Double,
    val north: Double,
    val east: Double,
    val placesIncluded: Boolean,
    val camerasIncluded: Boolean,
    val addressesIncluded: Boolean,
) {
    /** The frame has a catalog region, enough room and something left to fetch. */
    val canDownload: Boolean get() = reasonKey.isEmpty()
}

internal object OfflineArea {
    const val FRAME_LEFT = 0.07
    const val FRAME_RIGHT = 0.07
    const val FRAME_TOP = 0.18
    const val FRAME_BOTTOM = 0.34

    /** Street detail ends at the vector tiles' last zoom; closer zooms draw from those tiles. */
    const val LAST_TILE_ZOOM = 14
    /** Average saved-tile size, the same OpenFreeMap sample Android uses. */
    const val AREA_TILE_KB = 110.0
    /** More tiles than this is too large to treat as one area, as on Android. */
    const val AREA_MAX_TILES = 60_000
    /** Address coverage reaches about 10 km around the frame, like Android's 0.09 degree pad. */
    const val GEOCODE_PAD_DEG = 0.09
    /** Larger boxes are not queried for addresses: a whole state is not an address download. */
    const val ADDRESS_MAX_SPAN = 2.0

    /** The frame's bounds inside a viewport. Longitude is linear, latitude is linear in Mercator y. */
    fun framedBounds(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        insets: OfflineAreaInsets = OfflineAreaInsets(),
    ): OfflineAreaBounds {
        fun mercatorY(lat: Double) = ln(
            tan(kotlin.math.PI / 4 + (lat.coerceIn(-85.0511, 85.0511) * kotlin.math.PI / 180) / 2))
        fun latitude(y: Double) = (2 * atan(exp(y)) - kotlin.math.PI / 2) * 180 / kotlin.math.PI
        val ys = mercatorY(south)
        val yn = mercatorY(north)
        return OfflineAreaBounds(
            south = latitude(ys + (yn - ys) * insets.bottom),
            west = west + (east - west) * insets.left,
            north = latitude(yn - (yn - ys) * insets.top),
            east = east - (east - west) * insets.right,
        )
    }

    /** Web-mercator tiles covering [bounds] from [minZoom] through [LAST_TILE_ZOOM]. */
    fun tiles(bounds: OfflineAreaBounds, minZoom: Double): Int {
        val first = kotlin.math.floor(minZoom).toInt().coerceIn(0, LAST_TILE_ZOOM)
        return (first..LAST_TILE_ZOOM).sumOf { z -> tileCount(bounds, z) }
    }

    fun tileCount(bounds: OfflineAreaBounds, zoom: Int): Int {
        val scale = 1 shl zoom
        fun x(lng: Double) = ((lng + 180.0) / 360.0 * scale).toInt().coerceIn(0, scale - 1)
        fun y(lat: Double): Int {
            val r = lat.coerceIn(-85.0511, 85.0511) * kotlin.math.PI / 180
            return ((1 - ln(tan(r) + 1 / cos(r)) / kotlin.math.PI) / 2 * scale)
                .toInt().coerceIn(0, scale - 1)
        }
        return (x(bounds.east) - x(bounds.west) + 1) * (y(bounds.south) - y(bounds.north) + 1)
    }

    /** The tile-based estimate, kept for the frame's map footprint. */
    fun tileEstimateMb(tiles: Int, kbPerTile: Double = AREA_TILE_KB): Int =
        max(1, (tiles * kbPerTile / 1024.0).roundToInt())

    /** KB per tile where a basemap archive covers the point, else the shared average. */
    fun kbPerTile(archiveSizeMb: Int?, archiveTiles: Int): Double {
        if (archiveSizeMb == null || archiveSizeMb <= 0 || archiveTiles <= 0) return AREA_TILE_KB
        return (archiveSizeMb * 1024.0 / archiveTiles).coerceIn(10.0, 170.0)
    }

    /** Drops the place pack and place archives when the user chose not to include places. */
    fun applyPreferences(
        assets: List<OfflineAssetPlan>,
        preferences: OfflineAreaPreferences,
    ): List<OfflineAssetPlan> = if (preferences.places) assets else assets.filter {
        it.kind != OfflineStore.KIND_PACK && it.kind != OfflineStore.KIND_PLACES
    }

    /** The network extras the downloader can really run after the map pieces are installed. */
    fun extras(preferences: OfflineAreaPreferences): List<String> = buildList {
        if (preferences.cameras) add(OfflineStore.KIND_CAMERAS)
        if (preferences.addresses) add(OfflineStore.KIND_ADDRESSES)
    }

    /** The padded box the address index covers for [bounds], or null when it is too large. */
    fun addressBounds(bounds: OfflineAreaBounds): OfflineAreaBounds? {
        if (bounds.east - bounds.west > ADDRESS_MAX_SPAN || bounds.north - bounds.south > ADDRESS_MAX_SPAN) {
            return null
        }
        return bounds.padded(GEOCODE_PAD_DEG)
    }

    /**
     * The smallest catalog region that answers for a point. A polygon claim wins; when no polygon
     * claims it but a region box holds it, the box answers. A coarse catalog polygon can exclude a
     * point its own box holds (the Monaco polygon is a three-point triangle that misses the city),
     * and an area download is the whole region either way. [claims] is a seam for the JVM test.
     */
    fun pickRegion(
        regions: List<RoutingRegion>,
        lat: Double,
        lng: Double,
        claims: (RoutingRegion) -> Boolean = { it.covers(lat, lng) },
    ): RoutingRegion? {
        val claimed = regions.filter(claims)
        val candidates = claimed.ifEmpty {
            regions.filter { RegionPolys.boxCovers(it.s, it.w, it.n, it.e, lat, lng) }
        }
        return candidates.minByOrNull { it.boxArea() }
    }
}

/**
 * Why an area download cannot start. [NO_REGION] is a hole in the catalog, [NO_SPACE] the volume
 * refusing the estimated bytes plus the storage margin, [INSTALLED] a region already complete with
 * no extra data asked for.
 */
internal object OfflineAreaGate {
    const val NO_REGION = "no_region"
    const val NO_SPACE = "no_space"
    const val INSTALLED = "installed"
    const val READY = ""

    fun reason(
        freeBytes: Long,
        neededBytes: Long,
        installed: Boolean,
        extrasRequested: Boolean,
    ): String = when {
        !OfflineStorage.fits(freeBytes, neededBytes) -> NO_SPACE
        installed && !extrasRequested -> INSTALLED
        else -> READY
    }
}
