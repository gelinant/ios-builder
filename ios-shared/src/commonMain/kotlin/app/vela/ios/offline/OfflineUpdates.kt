package app.vela.ios.offline

import app.vela.core.offline.RoutingRegion

/**
 * Whether an installed piece can take the published delta. A delta is only usable when the
 * installed revision equals the patch's `fromRev`; anything else is downloaded whole, which is
 * what the update would have done anyway.
 */
internal object OfflineUpdates {
    enum class Mode { NONE, DELTA, FULL }

    fun decide(installedRev: Int, rev: Int, deltaFromRev: Int, deltaUrl: String?): Mode = when {
        rev <= installedRev -> Mode.NONE
        deltaUrl != null && installedRev == deltaFromRev -> Mode.DELTA
        else -> Mode.FULL
    }

    fun deltaUrl(installedRev: Int, row: RoutingRegion): String? =
        row.deltaUrl?.takeIf { decide(installedRev, row.rev, row.deltaFromRev, row.deltaUrl) == Mode.DELTA }
}

/**
 * The free-space gate before a download. A plan is refused when the volume cannot hold the pieces
 * plus a margin, so a long download never stops halfway through with a partial install.
 */
internal object OfflineStorage {
    /** Headroom for the glyph pack, temporary bodies and the atomic swap beside a target. */
    const val MARGIN_BYTES = 64L * 1024 * 1024
    private const val MB = 1024L * 1024L

    /** Estimated download bytes for [assets]. Deltas count at their own size. */
    fun neededBytes(assets: List<OfflineAssetPlan>): Long =
        assets.sumOf { asset -> maxOf(0, asset.sizeMb).toLong() * MB }

    fun fits(freeBytes: Long, neededBytes: Long): Boolean =
        freeBytes <= 0 || freeBytes >= neededBytes + MARGIN_BYTES

    /** One category's bytes, for the sheet's per-category delete controls. */
    fun categoryBytes(region: OfflineRegionBytes, category: String): Long = when (category) {
        OfflineStore.KIND_PACK -> region.packBytes
        OfflineStore.KIND_PLACES -> region.placesBytes
        OfflineStore.KIND_BASEMAP -> region.basemapBytes
        else -> 0
    }
}
