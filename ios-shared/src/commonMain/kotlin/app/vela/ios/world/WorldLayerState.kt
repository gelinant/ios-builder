package app.vela.ios.world

/** What one world layer needs from the shared layer: a stable id, a freshness window and whether
 *  it only works with a user key. Titles, sources and drawing stay in the Swift layer file. */
data class WorldLayerSpec(
    val id: String,
    val maxAgeSeconds: Long,
    val needsKey: Boolean,
)

/** The six layers the host accepts. No entry is installed by WLD-1: each business lot owns its
 *  Swift file and flips its own installation flag there. The ids are the persisted key stems. */
object WorldLayerCatalog {
    val AVIATION = WorldLayerSpec("aviation", 60L, false)
    val MARITIME = WorldLayerSpec("maritime", 300L, false)
    val ENERGY = WorldLayerSpec("energy", 1_800L, false)
    val NOTAM = WorldLayerSpec("notam", 900L, true)
    val SATELLITE = WorldLayerSpec("satellite", 7_200L, false)
    val WIKI = WorldLayerSpec("wiki", 86_400L, false)

    /** The sheet's order, fresh data first. */
    val ALL: List<WorldLayerSpec> = listOf(AVIATION, MARITIME, ENERGY, NOTAM, SATELLITE, WIKI)

    fun find(id: String): WorldLayerSpec? = ALL.firstOrNull { it.id == id }
}

/** The three states the sheet shows. `unavailable` covers a missing install, a required key that
 *  is absent, and a layer that has no data yet; it never pretends a timestamp is fresh. */
object WorldLayerStatuses {
    const val FRESH = "fresh"
    const val LATE = "late"
    const val UNAVAILABLE = "unavailable"
}

/**
 * One layer's state at a given instant, computed without a request. A layer is fresh while its
 * data is no older than its own [maxAgeSeconds]; past that it is late, even when the feed called
 * itself live. Unknown ids keep zero bounds and report unavailable.
 */
data class WorldLayerState(
    val id: String,
    val enabled: Boolean,
    val installed: Boolean,
    val needsKey: Boolean,
    val keyPresent: Boolean,
    val updatedAtMs: Long,
    val nowMs: Long,
    val maxAgeSeconds: Long,
) {
    /** Installed and, when the layer demands one, keyed. */
    val available: Boolean
        get() = installed && (!needsKey || keyPresent)

    /** Whole seconds since the last data, 0 when there is none. */
    val ageSeconds: Long
        get() = if (updatedAtMs <= 0L) 0L else ((nowMs - updatedAtMs).coerceAtLeast(0L)) / 1_000L

    val hasData: Boolean
        get() = updatedAtMs > 0L

    val status: String
        get() = when {
            !available -> WorldLayerStatuses.UNAVAILABLE
            updatedAtMs <= 0L -> WorldLayerStatuses.UNAVAILABLE
            ageSeconds > maxAgeSeconds -> WorldLayerStatuses.LATE
            else -> WorldLayerStatuses.FRESH
        }

    val isFresh: Boolean get() = status == WorldLayerStatuses.FRESH
    val isLate: Boolean get() = status == WorldLayerStatuses.LATE
    val isUnavailable: Boolean get() = status == WorldLayerStatuses.UNAVAILABLE
}
