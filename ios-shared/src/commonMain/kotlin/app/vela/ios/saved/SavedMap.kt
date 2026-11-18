package app.vela.ios.saved

import kotlin.math.PI
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** One saved or listed place as the map draws it (SAV-MARK): Android's pin rules, typed for Swift. */
data class SavedMapPin(
    /** The marker key: list-qualified for a list entry, "saved:<id>" for a quick save, "parking". */
    val key: String,
    val placeId: String,
    val listId: String?,
    val name: String,
    val lat: Double,
    val lng: Double,
    /** ARGB, the place's own colour first, else its list's; every quick save is Google blue. */
    val color: Int,
    /** The icon key the pin draws: the place's own icon, else its list's, else "bookmark". */
    val icon: String,
    val parking: Boolean,
)

/** One line or area of a list as the map draws it: colours and opacities already resolved. */
data class SavedMapShape(
    /** Identity inside its list: shapes carry no id, so the stored index is the key. */
    val index: Int,
    val listId: String,
    val listName: String,
    val name: String,
    /** True for an area: a closed ring of three points or more. */
    val closed: Boolean,
    /** lat, lng, lat, lng... exactly as stored. */
    val points: DoubleArray,
    val lineColor: Int,
    val lineOpacity: Double,
    val width: Double,
    /** The fill colour, or null when the shape is a line or carries no fill. */
    val fillColor: Int?,
    val fillOpacity: Double,
) {
    val key: String get() = "$listId:$index"
}

/** A camera and view size, enough to project a point onto the screen as MapLibre does. */
data class SavedMapCamera(
    val centerLat: Double,
    val centerLng: Double,
    val zoom: Double,
    val width: Double,
    val height: Double,
)

data class SavedScreenPoint(val x: Double, val y: Double)

/**
 * The saved places' map rules, shared by the Swift renderer and its JVM tests: Android's zoom
 * thresholds, pin sizes, colours, deduplication and the tap radius. Rendering itself (the disc
 * image, the annotation views, the style layers) stays in Swift.
 */
object SavedMap {
    /** Google blue for a quick save, as Android's `savedPinData` falls back to. */
    const val DEFAULT_COLOR = 0xFF1A73E8.toInt()
    /** Android's grey parking pin. */
    const val PARKING_COLOR = 0xFF5F6368.toInt()
    const val DEFAULT_ICON = "bookmark"
    const val PARKING_ICON = "car.fill"

    /** Android's SAVED_PIN_FULL_ZOOM: the full pin from here. */
    const val PIN_FULL_ZOOM = 8.0
    /** Android's SAVED_PIN_FAR_ZOOM: the pin is at its smallest here and below. */
    const val PIN_FAR_ZOOM = 3.0
    /** Android's SAVED_PIN_FAR_SCALE. */
    const val PIN_FAR_SCALE = 0.45
    /** Android's SAVED_PIN_SCALE. */
    const val PIN_SCALE = 1.35
    /**
     * The disc's diameter in points before Android's scale: Android draws a 64 px bitmap whose
     * disc is 46 px wide, read at the phone's density (about 2.75 on the reference device), and
     * an iOS point is one logical pixel.
     */
    const val PIN_DIAMETER = 16.7
    /** Android's SAVED_LABEL_ZOOM: the place's name under its pin from here. */
    const val LABEL_ZOOM = 14.0
    /** Android's shape label min zoom, for a line's or an area's name. */
    const val SHAPE_LABEL_ZOOM = 12.0
    /** Android's saved-pin tap box is 44 dp square, so 22 dp each way. */
    const val TOUCH_RADIUS = 22.0

    private const val MIN_LINE_OPACITY = 0.35
    private const val MIN_FILL_OPACITY = 0.08
    private const val MAX_FILL_OPACITY = 0.7
    private const val HALF_WORLD = 256.0

    /** Android's linear icon-size interpolation between the far and full pin zooms, clamped. */
    fun zoomFactor(zoom: Double): Double = when {
        zoom <= PIN_FAR_ZOOM -> PIN_FAR_SCALE
        zoom >= PIN_FULL_ZOOM -> 1.0
        else -> PIN_FAR_SCALE +
            (zoom - PIN_FAR_ZOOM) / (PIN_FULL_ZOOM - PIN_FAR_ZOOM) * (1.0 - PIN_FAR_SCALE)
    }

    /** The disc's diameter in points at [zoom]. */
    fun pinDiameter(zoom: Double): Double = PIN_DIAMETER * PIN_SCALE * zoomFactor(zoom)

    /** True when place names draw under the pins. */
    fun showsNames(zoom: Double): Boolean = zoom >= LABEL_ZOOM

    /** True when a shape's name draws. */
    fun showsShapeNames(zoom: Double): Boolean = zoom >= SHAPE_LABEL_ZOOM

    /** The shape-name zoom, for the style layers Swift builds. */
    fun shapeLabelZoom(): Double = SHAPE_LABEL_ZOOM

    /** The place-name zoom, read by the Swift label rule and its tests. */
    fun labelZoom(): Double = LABEL_ZOOM

    /**
     * Every pin the browse map draws, in Android's order: list places (newest list first, its own
     * icon and colour before its list's), then quick saves, then the parking spot. A place kept in
     * several lists draws once, under the first list that holds it; a place on a hidden custom-map
     * layer draws not at all.
     */
    fun pins(state: SavedState): List<SavedMapPin> {
        val out = ArrayList<SavedMapPin>()
        val seen = HashSet<String>()
        state.lists.forEach { list ->
            list.places.forEach { p ->
                if (p.layer != null && p.layer in list.hiddenLayers) return@forEach
                if (!seen.add(p.id)) return@forEach
                out += SavedMapPin(
                    key = "list:${list.id}:${p.id}",
                    placeId = p.id,
                    listId = list.id,
                    name = p.name,
                    lat = p.lat,
                    lng = p.lng,
                    color = (p.color ?: list.color).toInt(),
                    icon = p.icon ?: list.icon,
                    parking = false,
                )
            }
        }
        state.saved.forEach { p ->
            if (!seen.add(p.id)) return@forEach
            out += SavedMapPin(
                key = "saved:${p.id}",
                placeId = p.id,
                listId = null,
                name = p.name,
                lat = p.lat,
                lng = p.lng,
                color = DEFAULT_COLOR,
                icon = p.icon ?: DEFAULT_ICON,
                parking = false,
            )
        }
        state.parking?.let {
            out += SavedMapPin(
                key = "parking",
                placeId = "parking",
                listId = null,
                name = "",
                lat = it.lat,
                lng = it.lng,
                color = PARKING_COLOR,
                icon = PARKING_ICON,
                parking = true,
            )
        }
        return out
    }

    /**
     * Every line and area of every list, as Android draws them: a shape on a hidden layer is
     * skipped; an area is a closed shape with three points or more; the line keeps its colour and
     * width, and only a shape with a fill colour is filled.
     */
    fun shapes(state: SavedState): List<SavedMapShape> {
        val out = ArrayList<SavedMapShape>()
        state.lists.forEach { list ->
            list.shapes.forEachIndexed { index, shape ->
                if (shape.layer != null && shape.layer in list.hiddenLayers) return@forEachIndexed
                if (shape.pts.size < 4 || shape.pts.size % 2 != 0) return@forEachIndexed
                val area = shape.closed && shape.pts.size >= 6
                val color = shape.color.toInt()
                val fill = if (area) shape.fill?.toInt() else null
                out += SavedMapShape(
                    index = index,
                    listId = list.id,
                    listName = list.name,
                    name = shape.name,
                    closed = area,
                    points = shape.pts.toDoubleArray(),
                    lineColor = color,
                    lineOpacity = alpha(color).coerceAtLeast(MIN_LINE_OPACITY),
                    width = shape.width.toDouble(),
                    fillColor = fill,
                    fillOpacity = fill?.let { alpha(it).coerceIn(MIN_FILL_OPACITY, MAX_FILL_OPACITY) } ?: 0.0,
                )
            }
        }
        return out
    }

    /** Android's shape fill for a closed shape the editor just closed: the colour at 25 % alpha. */
    fun defaultFill(color: Long): Long = (color and 0x00FFFFFFL) or 0x40000000L

    fun alpha(argb: Int): Double = ((argb ushr 24) and 0xFF) / 255.0

    /**
     * A point projected onto the map view the way MapLibre's 512 px tiles lay it out: the camera
     * centre lands in the middle, east is +x and north is -y. [SavedMapCamera.width] and
     * [SavedMapCamera.height] are the view's points.
     */
    fun project(lat: Double, lng: Double, camera: SavedMapCamera): SavedScreenPoint {
        val world = 512.0 * pow2(camera.zoom)
        val x = camera.width / 2 + (normX(lng) - normX(camera.centerLng)) * world
        val y = camera.height / 2 + (normY(lat) - normY(camera.centerLat)) * world
        return SavedScreenPoint(x, y)
    }

    /**
     * The saved pin under ([x], [y]), as Android's saved-layer hit test: the nearest one inside
     * [radius], or -1. An equal-distance tie keeps the later pin, which the map draws on top.
     */
    fun nearest(pins: List<SavedMapPin>, camera: SavedMapCamera, x: Double, y: Double, radius: Double = TOUCH_RADIUS): Int {
        var best = -1
        var bestDistance = radius
        pins.forEachIndexed { index, pin ->
            val projected = project(pin.lat, pin.lng, camera)
            val distance = hypot(projected.x - x, projected.y - y)
            if (distance <= bestDistance) {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private fun normX(lng: Double): Double = (lng + 180.0) / 360.0

    private fun normY(lat: Double): Double {
        val clamped = lat.coerceIn(-85.05112878, 85.05112878)
        val s = sin(clamped * PI / 180.0)
        return 0.5 - ln((1 + s) / (1 - s)) / (4 * PI)
    }

    private fun pow2(zoom: Double): Double = 2.0.pow(zoom)

    /** The distance the tap test uses, so the JVM tests cover the exact formula. */
    private fun hypot(dx: Double, dy: Double): Double = sqrt(dx * dx + dy * dy)
}
