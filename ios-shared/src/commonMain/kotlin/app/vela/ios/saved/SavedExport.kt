package app.vela.ios.saved

import app.vela.core.model.ListPlace
import app.vela.core.model.SavedPlace
import app.vela.core.util.Fmt
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** The portable formats the Saved screen can write. JSON is the full Vela backup, as on
 *  Android; GPX and KML are the interchange formats other map apps read. */
enum class SavedExportFormat { JSON, GPX, KML }

/**
 * Builds the exported documents. Android exports JSON only ([SavedPlaceStore.exportJson] and
 * [PlaceListStore.exportJson]); the GPX and KML writers exist on iOS because Vela already reads
 * both on import, so a place can leave in a format another app understands.
 *
 * What each format carries is deliberately honest:
 * - JSON keeps every stored field and the list membership, so importing it back is lossless;
 * - GPX and KML keep only the name, the coordinate and the address, which is exactly what
 *   [PlaceImport] reads. Ids, icons, notes, colors, photos and list membership are not
 *   representable in those formats and are left out rather than smuggled into private fields.
 */
object SavedExport {
    private val json = Json { encodeDefaults = true }

    fun placesJson(places: List<SavedPlace>): String = json.encodeToString(places)

    fun places(places: List<SavedPlace>, title: String, format: SavedExportFormat): String =
        when (format) {
            SavedExportFormat.JSON -> placesJson(places)
            SavedExportFormat.GPX -> gpx(places, title)
            SavedExportFormat.KML -> kml(places, title)
        }

    fun gpx(places: List<SavedPlace>, title: String): String = buildString {
        append("""<?xml version="1.0" encoding="UTF-8"?>""").append('\n')
        append("""<gpx version="1.1" creator="Vela" xmlns="http://www.topografix.com/GPX/1/1">""").append('\n')
        append("  <metadata><name>").append(xml(title)).append("</name></metadata>\n")
        places.forEach { place ->
            append("  <wpt lat=\"").append(Fmt.fixed(place.lat, 6))
                .append("\" lon=\"").append(Fmt.fixed(place.lng, 6)).append("\">\n")
            append("    <name>").append(xml(place.name)).append("</name>\n")
            place.address?.takeIf { it.isNotBlank() }?.let {
                append("    <desc>").append(xml(it)).append("</desc>\n")
            }
            append("  </wpt>\n")
        }
        append("</gpx>\n")
    }

    fun kml(places: List<SavedPlace>, title: String): String = buildString {
        append("""<?xml version="1.0" encoding="UTF-8"?>""").append('\n')
        append("""<kml xmlns="http://www.opengis.net/kml/2.2"><Document>""").append('\n')
        append("  <name>").append(xml(title)).append("</name>\n")
        places.forEach { place ->
            append("  <Placemark>\n")
            append("    <name>").append(xml(place.name)).append("</name>\n")
            place.address?.takeIf { it.isNotBlank() }?.let {
                append("    <description>").append(xml(it)).append("</description>\n")
            }
            // KML is longitude first: the classic reversed-order import lands in the ocean.
            append("    <Point><coordinates>").append(Fmt.fixed(place.lng, 6)).append(',')
                .append(Fmt.fixed(place.lat, 6)).append("</coordinates></Point>\n")
            append("  </Placemark>\n")
        }
        append("</Document></kml>\n")
    }

    /** A list entry as the quick-save record the JSON format writes. A list entry's feature id
     *  and note only exist in the list document, so a single-place export does not carry them. */
    fun place(entry: ListPlace): SavedPlace = SavedPlace(
        id = entry.id,
        name = entry.name,
        lat = entry.lat,
        lng = entry.lng,
        address = entry.address,
        icon = entry.icon,
    )

    /** A file name the share sheet can show, without path separators or quotes. */
    fun fileName(base: String, format: SavedExportFormat): String {
        val safe = base.map { c ->
            if (c.isLetterOrDigit() || c == ' ' || c == '-' || c == '_') c else '-'
        }.joinToString("").trim().take(40).ifEmpty { "vela" }
        return "$safe.${format.name.lowercase()}"
    }

    private fun xml(value: String): String = value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")
}
