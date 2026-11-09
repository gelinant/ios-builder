package app.vela.ios.world

import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import kotlinx.datetime.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * ISO 8601 to epoch milliseconds. The Carbon Intensity API writes `2026-10-28T11:00Z` without
 * seconds, which kotlinx-datetime rejects; a minute-only timestamp gets `:00` before parsing.
 */
private val ISO_WITHOUT_SECONDS = Regex("(T\\d{2}:\\d{2})(Z|[+-]\\d{2}:\\d{2})$")

internal fun isoEpochMs(text: String?): Long? {
    val value = text?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    val normalized = ISO_WITHOUT_SECONDS.replace(value) { match ->
        match.groupValues[1] + ":00" + match.groupValues[2]
    }
    return runCatching { Instant.parse(normalized).toEpochMilliseconds() }.getOrNull()
}

/**
 * One approximate NESO region, read from the bundled `neso-regions.json`. The center is used to
 * recenter the map from a row; the polygons in the same file are what the layer draws. Both are
 * derived from the NESO DNO license areas and are not official boundaries.
 */
data class NesoZone(
    val regionId: Int,
    val name: String,
    val latitude: Double,
    val longitude: Double,
    val radiusKm: Double,
)

/** The bundled region file, shared by the Swift drawing code and the Kotlin parser. */
object NesoZones {
    fun parse(json: String): List<NesoZone> = runCatching {
        val root = Json.parseToJsonElement(json).jsonObject
        root["regions"]?.jsonArray.orEmpty().mapNotNull { element ->
            val region = element.jsonObject
            val id = region["regionId"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
            val name = region["name"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            val center = region["center"]?.jsonArray ?: return@mapNotNull null
            if (center.size < 2) return@mapNotNull null
            val lat = center[0].jsonPrimitive.doubleOrNull ?: return@mapNotNull null
            val lng = center[1].jsonPrimitive.doubleOrNull ?: return@mapNotNull null
            val radius = region["radiusKm"]?.jsonPrimitive?.doubleOrNull ?: 50.0
            NesoZone(id, name, lat, lng, radius)
        }.filter { it.regionId in 1..14 }.sortedBy { it.regionId }
    }.getOrDefault(emptyList())
}

/** A British regional forecast, already matched with its approximate NESO zone. */
data class CarbonRegion(
    val regionId: Int,
    val name: String,
    val dnoregion: String,
    val forecastGrams: Int,
    val index: String,
    val latitude: Double,
    val longitude: Double,
)

/** One accepted half-hour forecast. [fromMs] is the API's half-hour start, not the fetch time. */
data class CarbonSnapshot(
    val fromMs: Long,
    val toMs: Long,
    val regions: List<CarbonRegion>,
)

/**
 * The keyless Carbon Intensity API for Great Britain (CC BY 4.0).
 *
 * One call returns the 14 DNO regions; the national aggregates 15 to 18 and any region without a
 * bundled center are dropped, so a row or a polygon never appears at an invented place. A failure
 * returns null and leaves the caller's last accepted forecast in place.
 */
class CarbonIntensitySource(
    private val http: VelaHttp,
    private val baseUrl: String = BASE_URL,
) {
    suspend fun fetch(zones: List<NesoZone>): CarbonSnapshot? {
        if (zones.isEmpty()) return null
        val request = HttpRequest(
            url = baseUrl.trimEnd('/') + "/regional",
            timeoutMillis = 15_000,
            headers = listOf(
                app.vela.core.platform.HttpHeader("Accept", "application/json"),
            ),
        )
        val response = runCatching { http.call(request) }.getOrNull() ?: return null
        if (!response.isSuccessful) return null
        return runCatching { parse(response.bodyText(), zones) }.getOrNull()
    }

    companion object {
        /** Plain host without a scheme; the layer file is what notices scan. */
        const val HOST = "api.carbonintensity.org.uk"
        const val BASE_URL = "https://$HOST"
        const val HALF_HOUR_MS = 30L * 60L * 1_000L

        /**
         * Reads the first half-hour of `/regional`. The endpoint wraps its answer in `data`; a
         * bare `regions` array is also accepted so a fixture can stay small.
         */
        fun parse(text: String, zones: List<NesoZone>): CarbonSnapshot? = runCatching {
            val root = Json.parseToJsonElement(text).jsonObject
            val first = root["data"]?.jsonArray?.firstOrNull()?.jsonObject ?: root
            val fromMs = isoEpochMs(first.str("from")) ?: 0L
            val toMs = isoEpochMs(first.str("to")) ?: (fromMs.takeIf { it > 0L }?.plus(HALF_HOUR_MS) ?: 0L)
            if (fromMs <= 0L) return null
            val byId = zones.associateBy { it.regionId }
            val regions = first["regions"]?.jsonArray.orEmpty().mapNotNull { element ->
                val region = element.jsonObject
                val id = region["regionid"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
                val zone = byId[id] ?: return@mapNotNull null
                val intensity = region["intensity"]?.jsonObject ?: return@mapNotNull null
                val forecast = intensity["forecast"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
                CarbonRegion(
                    regionId = id,
                    name = region.str("shortname") ?: zone.name,
                    dnoregion = region.str("dnoregion").orEmpty(),
                    forecastGrams = forecast,
                    index = intensity.str("index") ?: indexFor(forecast),
                    latitude = zone.latitude,
                    longitude = zone.longitude,
                )
            }.sortedBy { it.regionId }
            if (regions.isEmpty()) return null
            CarbonSnapshot(fromMs = fromMs, toMs = toMs, regions = regions)
        }.getOrNull()

        /** The six API labels, with a numeric fallback so an unknown label still gets a band. */
        fun indexFor(forecast: Int): String = when {
            forecast <= 50 -> "very low"
            forecast <= 100 -> "low"
            forecast <= 150 -> "moderate"
            forecast <= 200 -> "high"
            else -> "very high"
        }

        private fun JsonObject.str(name: String): String? =
            this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }

    }
}
