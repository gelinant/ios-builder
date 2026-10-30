package app.vela.core.data.tiles

/**
 * The two keyless Google raster overlays the browse map offers, plus the Esri imagery that is the
 * satellite basemap. Android's `VelaMapView` used to own these strings; they now live in
 * `:core-common` so the Android and iOS maps load the same bytes.
 *
 * The templates are copied verbatim from the Android code (issue history in `VelaMapView.kt`), not
 * rebuilt from parts: the traffic URL's `pb` parameter is ordered and any reordering changes what
 * Google serves. MapLibre substitutes `{z}`, `{x}` and `{y}` in the order the template names them.
 *
 * Traffic is Google's own keyless `/maps/vt` PNG: `!2straffic` selects the congestion layer,
 * `!1e2` the overlay, and `!1i{z}!2i{x}!3i{y}` are XYZ coordinates. `3m8!2sen!3sus` fixes the
 * response language to English and the region to the United States, as Android has always sent.
 * There is no scale parameter.
 */
object RasterTiles {
    /** Google live traffic, standard XYZ (z, then x, then y), 256 point tiles. */
    const val TRAFFIC_URL =
        "https://www.google.com/maps/vt/pb=!1m4!1m3!1i{z}!2i{x}!3i{y}!2m9!1e2!2straffic!3i999999" +
            "!4m2!1sincidents!2s1!4m2!1sincidents_text!2s1!3m8!2sen!3sus!5e1105!12m4!1e68!2m2!1sset!2sRoadmap!4e0!5m1!1e0"

    /** Google's map tiles past z16 are thin, and asking for them throttles the connection, so the
     *  source stops at z16 and MapLibre overzooms the parent tile. */
    const val TRAFFIC_MAX_ZOOM = 16

    /** The opacity Android paints the traffic overlay at, so free-flow green recedes. */
    const val TRAFFIC_OPACITY = 0.6

    /** Esri World Imagery, `z/y/x` order, the openly usable satellite basemap. */
    const val SATELLITE_URL =
        "https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"

    /** Esri's safe global maximum. */
    const val SATELLITE_MAX_ZOOM = 19

    /** Google's own imagery, `x/y/z` order, used only as the deep-zoom fallback past [SATELLITE_MAX_ZOOM]. */
    const val SATELLITE_DEEP_URL = "https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}"

    /** Google upsamples outside cities, so the fallback never paints holes where Esri stops. */
    const val SATELLITE_DEEP_MAX_ZOOM = 21

    /** Below this zoom the deep layer is transparent yet would still fetch tiles. */
    const val SATELLITE_DEEP_MIN_ZOOM = 18.6

    /** Esri's imagery is dimmed and desaturated so label halos stay readable (Android's values). */
    const val SATELLITE_BRIGHTNESS_MAX = 0.80
    const val SATELLITE_SATURATION = -0.1

    /** The tile at [x], [y] and [z] in a template, with the platform integer spelling. */
    fun tile(template: String, x: Int, y: Int, z: Int): String = template
        .replace("{z}", z.toString())
        .replace("{x}", x.toString())
        .replace("{y}", y.toString())

    fun trafficTile(x: Int, y: Int, z: Int): String = tile(TRAFFIC_URL, x, y, z)

    fun satelliteTile(x: Int, y: Int, z: Int): String = tile(SATELLITE_URL, x, y, z)

    fun satelliteDeepTile(x: Int, y: Int, z: Int): String = tile(SATELLITE_DEEP_URL, x, y, z)
}
