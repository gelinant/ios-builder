package app.vela.ios.world

import app.vela.core.VelaConfig
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.util.XmlPull
import app.vela.core.util.gunzip
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.time.Clock
import kotlin.time.Instant

/** The visible map, as the AIS sources take it. The box is the same one the host passes to a
 *  layer refresh. */
data class MaritimeBox(val south: Double, val west: Double, val north: Double, val east: Double) {
    val isValid: Boolean
        get() = south.isFinite() && west.isFinite() && north.isFinite() && east.isFinite() &&
            south >= -90.0 && north <= 90.0 && west >= -180.0 && east <= 180.0 &&
            south < north && west < east

    val centerLat: Double get() = (south + north) / 2.0
    val centerLng: Double get() = (west + east) / 2.0

    fun contains(lat: Double, lng: Double): Boolean =
        lat in south..north && lng in west..east

    /** True when the box touches the waters Digitraffic covers. */
    fun intersectsFinland(): Boolean =
        south <= FINLAND_NORTH && north >= FINLAND_SOUTH &&
            west <= FINLAND_EAST && east >= FINLAND_WEST

    companion object {
        const val FINLAND_SOUTH = 58.5
        const val FINLAND_WEST = 17.5
        const val FINLAND_NORTH = 70.5
        const val FINLAND_EAST = 32.0
    }
}

/** One AIS position. A ship exists only with a numeric MMSI and a plausible position; a source
 *  line without either is dropped before it reaches [MaritimeStore]. */
data class AisShip(
    val mmsi: String,
    val lat: Double,
    val lng: Double,
    val courseDeg: Double?,
    val speedKnots: Double?,
    val shipType: Int?,
    val name: String?,
    val updatedAtMs: Long,
    val source: String,
) {
    /** The name the source gave, or the MMSI. No name is invented. */
    val title: String
        get() = name?.takeIf { it.isNotBlank() } ?: "MMSI $mmsi"

    val typeLabel: String get() = shipTypeLabel(shipType)

    /** Course, speed, type and MMSI, the four fields the lot promises. A field the feed did not
     *  carry says so instead of guessing. */
    val detail: String
        get() {
            val speed = speedKnots?.let { "${oneDecimal(it)} kn" } ?: "speed unknown"
            val course = courseDeg?.let { "course ${it.roundToInt()}°" } ?: "course unknown"
            return "$typeLabel · $speed · $course · MMSI $mmsi"
        }

    fun distanceM(lat: Double, lng: Double): Double {
        val earth = 6_371_000.0
        val dLat = (this.lat - lat) * PI / 180.0
        val dLng = (this.lng - lng) * PI / 180.0
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat * PI / 180.0) * cos(this.lat * PI / 180.0) *
            sin(dLng / 2) * sin(dLng / 2)
        return earth * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/** A row the Swift layer turns into `WorldLayerRow`. A coordinate recenters the map; no
 *  coordinate means a read-only information row. */
data class MaritimeRow(
    val id: String,
    val title: String,
    val detail: String,
    val lat: Double? = null,
    val lng: Double? = null,
)

/** What one AIS source answered. */
internal sealed interface AisAnswer {
    data class Ships(val list: List<AisShip>) : AisAnswer
    data class KeyRequired(val message: String) : AisAnswer
    data class KeyRejected(val message: String) : AisAnswer
    data object Failed : AisAnswer
    data object OutsideCoverage : AisAnswer
}

/** One AIS source. Digitraffic ignores the key; AISHub refuses to answer without one. */
internal fun interface AisSource {
    suspend fun fetch(box: MaritimeBox, key: String?): AisAnswer
}

/** Vessel metadata, the only place Digitraffic carries the ship type and the name. */
internal data class VesselMeta(val name: String?, val shipType: Int?)

/**
 * Digitraffic AIS for Finnish waters, keyless and under CC BY 4.0. Positions come from
 * `locations`; names and types from `vessels`, cached for six hours. The `Digitraffic-User`
 * header is required and a response without it is refused by the service.
 */
internal class DigitrafficSource(
    private val http: VelaHttp,
    private val now: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) : AisSource {
    private var metadata: Map<String, VesselMeta> = emptyMap()
    private var metadataAtMs = 0L

    override suspend fun fetch(box: MaritimeBox, key: String?): AisAnswer {
        if (!box.isValid) return AisAnswer.Failed
        if (!box.intersectsFinland()) return AisAnswer.OutsideCoverage
        if (now() - metadataAtMs !in 0 until METADATA_MAX_AGE_MS) {
            val text = getText(http, vesselsUrl(), listOf(userHeader(), gzipHeader()))
            if (text != null) {
                metadata = runCatching { parseVessels(text) }.getOrElse { emptyMap() }
                metadataAtMs = now()
            }
        }
        val locations = getText(http, locationsUrl(box), listOf(userHeader(), gzipHeader()))
            ?: return AisAnswer.Failed
        val ships = runCatching { parseLocations(locations, metadata) }.getOrElse { emptyList() }
        return AisAnswer.Ships(ships)
    }

    companion object {
        const val LOCATIONS_URL = "https://meri.digitraffic.fi/api/ais/v1/locations"
        const val VESSELS_URL = "https://meri.digitraffic.fi/api/ais/v1/vessels"
        const val USER_HEADER = "Digitraffic-User"
        const val METADATA_MAX_AGE_MS = 6L * 60L * 60L * 1_000L

        fun locationsUrl(box: MaritimeBox): String =
            "$LOCATIONS_URL?south=${coord(box.south)}&west=${coord(box.west)}" +
                "&north=${coord(box.north)}&east=${coord(box.east)}"

        fun vesselsUrl(): String = VESSELS_URL

        fun userHeader(): HttpHeader = HttpHeader(USER_HEADER, VelaConfig.VELA_UA)

        fun gzipHeader(): HttpHeader = HttpHeader("Accept-Encoding", "gzip")

        /** Positions from the GeoJSON `locations` answer. A feature with no point, a non numeric
         *  MMSI or an out of range coordinate is skipped. */
        fun parseLocations(text: String, metadata: Map<String, VesselMeta>): List<AisShip> {
            val root = Json.parseToJsonElement(text).jsonObject
            val features = root["features"] as? JsonArray ?: return emptyList()
            val out = ArrayList<AisShip>(features.size)
            for (feature in features) {
                val item = feature as? JsonObject ?: continue
                val props = item["properties"] as? JsonObject
                val geometry = item["geometry"] as? JsonObject ?: continue
                val coords = geometry["coordinates"] as? JsonArray ?: continue
                if (coords.size < 2) continue
                val lng = (coords[0] as? JsonPrimitive)?.doubleOrNull ?: continue
                val lat = (coords[1] as? JsonPrimitive)?.doubleOrNull ?: continue
                val mmsi = mmsiOf(props?.get("mmsi") ?: item["mmsi"]) ?: continue
                val meta = metadata[mmsi]
                val speed = (props?.get("sog") as? JsonPrimitive)?.doubleOrNull
                    ?.takeIf { it in 0.0..102.2 }
                val course = (props?.get("cog") as? JsonPrimitive)?.doubleOrNull
                    ?.takeIf { it in 0.0..359.9 }
                val stamp = (props?.get("timestampExternal") as? JsonPrimitive)?.longOrNull ?: 0L
                val ship = shipOrNull(
                    mmsi = mmsi, lat = lat, lng = lng, course = course, speed = speed,
                    type = meta?.shipType, name = meta?.name, stamp = stamp,
                    source = "digitraffic")
                if (ship != null) out += ship
            }
            return out
        }

        /** Name and type per MMSI from the `vessels` answer. A record without a numeric MMSI is
         *  skipped. */
        fun parseVessels(text: String): Map<String, VesselMeta> {
            val root = Json.parseToJsonElement(text) as? JsonArray ?: return emptyMap()
            val out = HashMap<String, VesselMeta>(root.size)
            for (entry in root) {
                val item = entry as? JsonObject ?: continue
                val mmsi = mmsiOf(item["mmsi"]) ?: continue
                val name = (item["name"] as? JsonPrimitive)?.contentOrNull
                    ?.trim()?.takeIf { it.isNotEmpty() }
                val type = (item["shipType"] as? JsonPrimitive)?.intOrNull
                out[mmsi] = VesselMeta(name, type)
            }
            return out
        }

        private fun coord(v: Double): String = (v * 100_000).roundToLong().toString()
    }
}

/**
 * AISHub positions with a member's own key, at most one request per minute. The key travels as
 * the `username` query parameter and is never logged, never stored here and never echoed. The
 * service answers XML on error even when JSON was requested, so both shapes are read.
 */
internal class AishubSource(private val http: VelaHttp) : AisSource {
    override suspend fun fetch(box: MaritimeBox, key: String?): AisAnswer {
        if (key.isNullOrBlank()) return AisAnswer.KeyRequired(KEY_REQUIRED)
        if (!box.isValid) return AisAnswer.Failed
        val url = requestUrl(box, key)
        val body = getBytes(http, url, listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA)))
            ?: return AisAnswer.Failed
        return runCatching { parse(body) }.getOrElse { AisAnswer.Failed }
    }

    companion object {
        const val URL = "https://data.aishub.net/ws.php"
        const val KEY_REQUIRED = "An AISHub member key is required."

        fun requestUrl(box: MaritimeBox, key: String): String =
            "$URL?username=${percentEncode(key.trim())}&format=1&output=json" +
                "&latmin=${coord(box.south)}&latmax=${coord(box.north)}" +
                "&lonmin=${coord(box.west)}&lonmax=${coord(box.east)}"

        /** XML or JSON, in one answer. The content decides which reader runs, never the request. */
        fun parse(body: ByteArray): AisAnswer {
            val head = body.decodeToString().trimStart()
            return if (head.startsWith("<")) {
                parseXml(decodeLatin1(body))
            } else {
                parseJson(body.decodeToString())
            }
        }

        fun parseXml(xml: String): AisAnswer {
            val p = XmlPull(xml)
            // An invalid key is reported by an ERROR attribute on VESSELS, not by an ERROR
            // element, and XmlPull does not expose attributes.
            var error = ERROR_ATTRIBUTE.containsMatchIn(xml.take(1_000))
            var message: String? = null
            var inShip = false
            var sawShip = false
            var fields = HashMap<String, String>()
            var flat = HashMap<String, String>()
            var text = StringBuilder()
            val ships = ArrayList<AisShip>()
            fun build(target: Map<String, String>): AisShip? = shipOrNull(
                mmsi = mmsiOf(target["MMSI"]?.let { JsonPrimitive(it) }) ?: return null,
                lat = target["LATITUDE"]?.toDoubleOrNull() ?: return null,
                lng = target["LONGITUDE"]?.toDoubleOrNull() ?: return null,
                course = (target["COURSE"] ?: target["COG"])?.toDoubleOrNull()
                    ?.takeIf { it in 0.0..359.9 },
                speed = (target["SPEED"] ?: target["SOG"])?.toDoubleOrNull()
                    ?.takeIf { it in 0.0..102.2 },
                type = (target["TYPE"] ?: target["SHIPTYPE"])?.toIntOrNull(),
                name = target["NAME"]?.trim()?.takeIf { it.isNotEmpty() },
                stamp = aishubTimeMs(target["TIME"]),
                source = "aishub")
            while (true) {
                when (p.next()) {
                    XmlPull.END_DOCUMENT -> break
                    XmlPull.START_TAG -> {
                        text = StringBuilder()
                        val tag = local(p.name)
                        if (tag == "SHIP") {
                            inShip = true
                            sawShip = true
                            fields = HashMap()
                        }
                    }
                    XmlPull.TEXT -> text.append(p.text)
                    XmlPull.END_TAG -> {
                        val tag = local(p.name)
                        val value = text.toString().trim()
                        when (tag) {
                            "ERROR" -> error = value.equals("true", ignoreCase = true)
                            "ERROR_MESSAGE" -> message = value
                            "MMSI", "LATITUDE", "LONGITUDE", "COURSE", "SPEED", "COG", "SOG",
                            "TYPE", "SHIPTYPE", "NAME", "TIME" ->
                                if (inShip) fields[tag] = value else flat[tag] = value
                            "SHIP" -> {
                                inShip = false
                                build(fields)?.let { ships += it }
                            }
                        }
                        text = StringBuilder()
                    }
                }
            }
            if (error) return AisAnswer.KeyRejected(message ?: "The AISHub key was refused.")
            if (!sawShip) build(flat)?.let { ships += it }
            return AisAnswer.Ships(ships)
        }

        fun parseJson(text: String): AisAnswer {
            val root = Json.parseToJsonElement(text)
            // The documented answer is [metadata, [ship, ship, ...]]; flat
            // [metadata, ship, ship, ...] answers exist too and are read the same way.
            val entries = ArrayList<JsonObject>()
            fun add(value: Any?) {
                when (value) {
                    is JsonObject -> entries += value
                    is JsonArray -> value.forEach { add(it) }
                }
            }
            add(root)
            var error = false
            var message: String? = null
            val ships = ArrayList<AisShip>()
            for (item in entries) {
                val recordError = (item["ERROR"] as? JsonPrimitive)?.booleanOrNull
                if (recordError == true) {
                    error = true
                    message = (item["ERROR_MESSAGE"] as? JsonPrimitive)?.contentOrNull ?: message
                    continue
                }
                val mmsi = mmsiOf(item["MMSI"]) ?: continue
                val lat = (item["LATITUDE"] as? JsonPrimitive)?.doubleOrNull ?: continue
                val lng = (item["LONGITUDE"] as? JsonPrimitive)?.doubleOrNull ?: continue
                val ship = shipOrNull(
                    mmsi = mmsi, lat = lat, lng = lng,
                    course = ((item["COURSE"] ?: item["COG"]) as? JsonPrimitive)?.doubleOrNull
                        ?.takeIf { it in 0.0..359.9 },
                    speed = ((item["SPEED"] ?: item["SOG"]) as? JsonPrimitive)?.doubleOrNull
                        ?.takeIf { it in 0.0..102.2 },
                    type = ((item["TYPE"] ?: item["SHIPTYPE"]) as? JsonPrimitive)?.intOrNull,
                    name = (item["NAME"] as? JsonPrimitive)?.contentOrNull
                        ?.trim()?.takeIf { it.isNotEmpty() },
                    stamp = aishubTimeMs((item["TIME"] as? JsonPrimitive)?.contentOrNull),
                    source = "aishub")
                if (ship != null) ships += ship
            }
            if (error) return AisAnswer.KeyRejected(message ?: "The AISHub key was refused.")
            return AisAnswer.Ships(ships)
        }

        /** `2026-10-27 11:52:13 GMT` and ISO 8601 both give epoch milliseconds; a shape neither
         *  parser knows gives 0, which loses the position to no dedup tie-break but never to a
         *  fabricated time. */
        fun aishubTimeMs(raw: String?): Long {
            if (raw.isNullOrBlank()) return 0L
            val trimmed = raw.trim().removeSuffix(" GMT").removeSuffix(" UTC")
            val iso = trimmed.replace(' ', 'T').let { if (it.endsWith("Z")) it else "${it}Z" }
            return runCatching { Instant.parse(iso).toEpochMilliseconds() }.getOrElse { 0L }
        }

        private fun local(name: String): String = name.substringAfter(':')

        private val ERROR_ATTRIBUTE =
            Regex("""ERROR\s*=\s*["']true["']""", RegexOption.IGNORE_CASE)

        private fun coord(v: Double): String = (v * 100_000).roundToLong().toString()

        /** A member key is a token; anything else is escaped so it cannot add a query parameter. */
        fun percentEncode(value: String): String {
            val hex = "0123456789ABCDEF"
            val out = StringBuilder()
            for (byte in value.encodeToByteArray()) {
                val c = byte.toInt() and 0xFF
                val ch = c.toChar()
                if (ch.isLetterOrDigit() || ch == '-' || ch == '.' || ch == '_' || ch == '~') {
                    out.append(ch)
                } else {
                    out.append('%').append(hex[c shr 4]).append(hex[c and 0x0F])
                }
            }
            return out.toString()
        }
    }
}

/** The ship-type wording of the AIS type ranges. A code the table does not name stays unknown. */
fun shipTypeLabel(code: Int?): String = when (code) {
    null, 0 -> "Type unknown"
    in 20..28 -> "Wing in ground"
    29 -> "Wing in ground (SAR)"
    30 -> "Fishing"
    in 31..32 -> "Towing"
    33 -> "Dredging"
    34 -> "Diving"
    35 -> "Military"
    36 -> "Sailing"
    37 -> "Pleasure craft"
    in 40..49 -> "High-speed craft"
    50 -> "Pilot boat"
    51 -> "Search and rescue"
    52 -> "Tug"
    53 -> "Port tender"
    54 -> "Anti-pollution"
    55 -> "Law enforcement"
    in 56..57 -> "Local craft"
    58 -> "Medical"
    in 60..69 -> "Passenger"
    in 70..79 -> "Cargo"
    in 80..89 -> "Tanker"
    in 90..99 -> "Other"
    else -> "Type unknown"
}

private fun shipOrNull(
    mmsi: String,
    lat: Double,
    lng: Double,
    course: Double?,
    speed: Double?,
    type: Int?,
    name: String?,
    stamp: Long,
    source: String,
): AisShip? {
    if (mmsi.isEmpty() || mmsi == "0") return null
    if (!lat.isFinite() || !lng.isFinite()) return null
    if (lat !in -90.0..90.0 || lng !in -180.0..180.0) return null
    return AisShip(
        mmsi = mmsi,
        lat = lat,
        lng = lng,
        courseDeg = course,
        speedKnots = speed,
        shipType = type,
        name = name,
        updatedAtMs = stamp,
        source = source,
    )
}

/** An MMSI is nine digits. A source value of another shape is not a ship identifier and is
 *  dropped rather than padded into a fake one. */
private fun mmsiOf(value: Any?): String? {
    val raw = when (value) {
        is JsonPrimitive -> value.contentOrNull
        else -> null
    }?.trim() ?: return null
    if (raw.length !in 6..9 || raw.any { !it.isDigit() }) return null
    if (raw.all { it == '0' }) return null
    return raw
}

private fun oneDecimal(value: Double): String =
    ((value * 10).roundToInt() / 10.0).toString()

private suspend fun getBytes(
    http: VelaHttp,
    url: String,
    headers: List<HttpHeader>,
): ByteArray? {
    val response = try {
        http.call(HttpRequest(url, headers = headers, timeoutMillis = TIMEOUT_MS))
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        return null
    }
    if (!response.isSuccessful) return null
    return decompress(response.body)
}

private suspend fun getText(
    http: VelaHttp,
    url: String,
    headers: List<HttpHeader>,
): String? = getBytes(http, url, headers)?.decodeToString()

/** URLSession may hand back the decompressed bytes or the gzip member, depending on which layer
 *  added `Accept-Encoding`. The magic number decides; a body that claims gzip but is broken is
 *  kept as is and fails its parse instead of escaping as an exception. */
private fun decompress(body: ByteArray): ByteArray {
    if (body.size < 2) return body
    val gzip = body[0] == 0x1f.toByte() && body[1] == 0x8b.toByte()
    if (!gzip) return body
    return runCatching { gunzip(body) }.getOrElse { body }
}

private fun decodeLatin1(body: ByteArray): String {
    val out = StringBuilder(body.size)
    for (byte in body) out.append((byte.toInt() and 0xFF).toChar())
    return out.toString()
}

private const val TIMEOUT_MS = 20_000L
