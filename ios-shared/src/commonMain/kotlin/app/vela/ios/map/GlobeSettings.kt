package app.vela.ios.map

import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores

/**
 * The native MapLibre globe projection introduced by G-2.
 *
 * The projection lives at style level: the style document carries `"projection": {"type":
 * "globe"}` and a style reload switches between the two. The stored value is a string so a
 * settings file stays readable outside Swift and the Kotlin test can pin it without a map.
 *
 * The zoom floor is G-1's measured value: at z0 the planet fills only 45 % of the screen width
 * (docs/ios/GLOBE-SPIKE.md, section 3.4). [GLOBE_MIN_ZOOM] keeps the globe at z1 until the
 * surround gets a real atmosphere.
 */
object GlobeProjection {
    /** Stable key shared by every process and by the settings test. */
    const val KEY = "map_projection"
    const val MERCATOR = "mercator"
    const val GLOBE = "globe"

    const val MERCATOR_MIN_ZOOM = 0.0
    const val GLOBE_MIN_ZOOM = 1.0

    /** Unknown or missing values fall back to Mercator, never to a half-configured globe. */
    fun normalize(value: String?): String = if (value == GLOBE) GLOBE else MERCATOR

    fun isGlobe(value: String?): Boolean = normalize(value) == GLOBE

    fun minimumZoom(value: String?): Double =
        if (isGlobe(value)) GLOBE_MIN_ZOOM else MERCATOR_MIN_ZOOM

    /** The explicit clamp G-1 asks for: `minimumZoomLevel` alone accepts a programmatic -0.09. */
    fun clampZoom(zoom: Double, value: String?): Double = maxOf(zoom, minimumZoom(value))
}

/** Reads and writes the projection in the shared `vela_settings` suite. */
class GlobeSettingsStore(stores: KeyValueStores) {
    private val settings: KeyValueStore = stores.open("vela_settings")

    val projection: String
        get() = GlobeProjection.normalize(
            settings.getString(GlobeProjection.KEY, GlobeProjection.MERCATOR))

    fun setProjection(value: String) {
        settings.edit().putString(GlobeProjection.KEY, GlobeProjection.normalize(value)).apply()
    }

    fun minimumZoom(): Double = GlobeProjection.minimumZoom(projection)

    fun clampZoom(zoom: Double): Double = GlobeProjection.clampZoom(zoom, projection)
}
