package app.vela.ios.world

import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * One aircraft from adsb.lol. [identification] is the callsign when the feed carries one and the
 * ICAO hex otherwise: the store never invents a flight number or a route.
 *
 * [altitudeFt] is -1 when the feed does not say (on the ground or unknown); [headingDeg] is -1
 * when the feed has no track. Neither value is interpolated between polls.
 */
data class AviationAircraft(
    val hex: String,
    val identification: String,
    val lat: Double,
    val lng: Double,
    val altitudeFt: Int,
    val headingDeg: Double,
    val groundSpeedKt: Double,
    val onGround: Boolean,
)

/**
 * What the aviation layer may draw and what the sheet says about it. [phase] is one of
 * [AviationPhases]; [aircraft] is empty unless the phase is fresh, so a late or quota result can
 * never be drawn as live traffic.
 */
data class AviationFetch(
    val updatedAtMs: Long,
    val aircraft: List<AviationAircraft>,
    val phase: String,
    val detail: String,
    val live: Boolean,
    val quotaRemainingSeconds: Long,
)

object AviationPhases {
    const val FRESH = "fresh"
    const val LATE = "late"
    const val QUOTA = "quota"
    const val UNAVAILABLE = "unavailable"
}

/**
 * Reads aircraft around the current view from adsb.lol (ODbL 1.0), under the A-1 rules:
 *
 * - one request at most per viewport change, for a radius derived from the viewport and capped
 *   at 100 NM, with [MAX_AIRCRAFT] aircraft nearest to the view center kept;
 * - a successful answer stays usable for [CACHE_MS] so a pan inside the same second does not
 *   spend another request;
 * - a 429 puts the layer in the quota phase and refuses every request for [QUOTA_MS];
 * - the last accepted answer expires after [MAX_AGE_MS]: [snapshot] then returns no aircraft, so
 *   the layer stops drawing instead of showing stale positions as live.
 *
 * No position is predicted between polls, and a missing callsign keeps its hex.
 */
class AviationStore(private val http: VelaHttp?) {
    private var lastAccepted: List<AviationAircraft> = emptyList()
    private var lastAcceptedAtMs = 0L
    private var quotaUntilMs = 0L
    private var sourceWasLive = false
    private var lastNotice = ""

    /** Fetches the viewport once. A cache hit, a quota window or a missing client make no request. */
    suspend fun fetch(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        nowMs: Long,
    ): AviationFetch {
        if (quotaUntilMs > nowMs) return snapshot(nowMs)
        if (lastAccepted.isNotEmpty() && nowMs - lastAcceptedAtMs in 0 until CACHE_MS) {
            return snapshot(nowMs)
        }
        val client = http
        if (client == null) {
            lastNotice = "No network client"
            return snapshot(nowMs)
        }
        val center = centerOf(south, west, north, east)
        val radius = radiusNm(south, west, north, east)
        val url = "$BASE_URL/${decimal(center.first, 4)}/${decimal(center.second, 4)}/$radius"
        val response = try {
            client.call(HttpRequest(
                url = url,
                headers = listOf(
                    HttpHeader("Accept", "application/json"),
                    HttpHeader("User-Agent", "Vela/0.1 (iOS)"),
                ),
                timeoutMillis = 15_000,
            ))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            lastNotice = "adsb.lol unavailable"
            return snapshot(nowMs)
        }
        if (response.code == 429) {
            quotaUntilMs = nowMs + QUOTA_MS
            lastAccepted = emptyList()
            lastAcceptedAtMs = 0L
            sourceWasLive = false
            lastNotice = "Quota reached"
            return snapshot(nowMs)
        }
        if (!response.isSuccessful) {
            lastNotice = "adsb.lol unavailable (HTTP ${response.code})"
            return snapshot(nowMs)
        }
        val parsed = try {
            parseAircraft(response.bodyText(), south, west, north, east, center)
        } catch (_: Throwable) {
            lastNotice = "adsb.lol answer not readable"
            return snapshot(nowMs)
        }
        lastAccepted = parsed
        lastAcceptedAtMs = nowMs
        sourceWasLive = true
        lastNotice = if (parsed.isEmpty()) "No aircraft in view" else ""
        return snapshot(nowMs)
    }

    /**
     * The fixture path used by the UI scenario. It applies the same viewport filter, cap and
     * freshness rule as a network answer, but the data is explicitly not live.
     */
    fun parseFixture(
        json: String,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        nowMs: Long,
    ): AviationFetch {
        val center = centerOf(south, west, north, east)
        val parsed = try {
            parseAircraft(json, south, west, north, east, center)
        } catch (_: Throwable) {
            emptyList()
        }
        lastAccepted = parsed
        lastAcceptedAtMs = if (parsed.isEmpty()) 0L else nowMs
        quotaUntilMs = 0L
        sourceWasLive = false
        lastNotice = if (parsed.isEmpty()) "No aircraft in view" else ""
        return snapshot(nowMs)
    }

    /** The drawable answer at [nowMs], without a request. Past the window it carries no aircraft. */
    fun snapshot(nowMs: Long): AviationFetch {
        val quotaSeconds = ((quotaUntilMs - nowMs + 999L) / 1_000L).coerceAtLeast(0L)
        val ageMs = if (lastAcceptedAtMs > 0L) (nowMs - lastAcceptedAtMs).coerceAtLeast(0L) else Long.MAX_VALUE
        val phase = when {
            quotaSeconds > 0L -> AviationPhases.QUOTA
            lastAcceptedAtMs <= 0L -> AviationPhases.UNAVAILABLE
            ageMs > MAX_AGE_MS -> AviationPhases.LATE
            else -> AviationPhases.FRESH
        }
        val aircraft = if (phase == AviationPhases.FRESH) lastAccepted else emptyList()
        val detail = when (phase) {
            AviationPhases.QUOTA -> "Quota reached, retry in $quotaSeconds s"
            AviationPhases.LATE -> "Data older than ${MAX_AGE_MS / 1_000L} s, not drawn"
            AviationPhases.UNAVAILABLE -> lastNotice.ifEmpty { "No data yet" }
            else -> lastNotice
        }
        return AviationFetch(
            updatedAtMs = lastAcceptedAtMs,
            aircraft = aircraft,
            phase = phase,
            detail = detail,
            live = phase == AviationPhases.FRESH && sourceWasLive,
            quotaRemainingSeconds = quotaSeconds,
        )
    }

    private fun parseAircraft(
        body: String,
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        center: Pair<Double, Double>,
    ): List<AviationAircraft> {
        val root = Json.parseToJsonElement(body).jsonObject
        val list = root["ac"]?.jsonArray ?: return emptyList()
        val accepted = ArrayList<AviationAircraft>(list.size)
        for (element in list) {
            val plane = element.jsonObject
            val lat = plane.double("lat") ?: continue
            val lng = plane.double("lon") ?: continue
            if (lat < south || lat > north || lng < west || lng > east) continue
            val hex = plane.string("hex")?.lowercase() ?: continue
            val callsign = plane.string("flight")?.trim()?.uppercase().orEmpty()
            val ground = plane["alt_baro"]?.jsonPrimitive?.content?.equals("ground", ignoreCase = true) == true ||
                plane["on_ground"]?.jsonPrimitive?.booleanOrNull == true
            val altitude = plane.int("alt_baro") ?: plane.int("alt_geom") ?: -1
            val heading = plane.double("track") ?: plane.double("true_heading")
                ?: plane.double("mag_heading") ?: -1.0
            val speed = plane.double("gs") ?: -1.0
            accepted += AviationAircraft(
                hex = hex,
                identification = callsign.ifEmpty { hex.uppercase() },
                lat = lat,
                lng = lng,
                altitudeFt = if (ground) -1 else altitude,
                headingDeg = heading,
                groundSpeedKt = speed,
                onGround = ground,
            )
        }
        val dLat = cos(center.first * PI / 180.0)
        val nearest = accepted.sortedBy { plane ->
            val dy = plane.lat - center.first
            val dx = (plane.lng - center.second) * dLat
            dy * dy + dx * dx
        }
        return nearest.take(MAX_AIRCRAFT)
    }

    companion object {
        /** The only adsb.lol endpoint A-1 uses: point/radius, no route or airport query. */
        const val BASE_URL = "https://api.adsb.lol/v2/point"

        /** The sheet's freshness window, shared with `WorldLayerCatalog.AVIATION`. */
        const val MAX_AGE_MS = 60_000L

        /** A successful answer is reused for this long before another request. */
        const val CACHE_MS = 10_000L

        /** A 429 blocks every request for this long. */
        const val QUOTA_MS = 60_000L

        /** Nearest aircraft kept from one answer. */
        const val MAX_AIRCRAFT = 300

        /** The API accepts 250 NM; A-1 asks for a useful radius no larger than this. */
        const val MAX_RADIUS_NM = 100

        fun centerOf(south: Double, west: Double, north: Double, east: Double): Pair<Double, Double> =
            (south + north) / 2 to (west + east) / 2

        /** Half the viewport diagonal in nautical miles, clamped to a useful 1..100 NM. */
        fun radiusNm(south: Double, west: Double, north: Double, east: Double): Int {
            val center = centerOf(south, west, north, east)
            val latNm = (north - south) * 60.0
            val lngNm = (east - west) * 60.0 * cos(center.first * PI / 180.0)
            val half = sqrt(latNm * latNm + lngNm * lngNm) / 2.0
            return half.roundToInt().coerceIn(1, MAX_RADIUS_NM)
        }

        private fun decimal(value: Double, places: Int): String {
            var scale = 1.0
            repeat(places) { scale *= 10.0 }
            val scaled = (value * scale).roundToInt()
            val sign = if (scaled < 0) "-" else ""
            val whole = abs(scaled) / scale.toInt()
            val fraction = abs(scaled) % scale.toInt()
            val pad = places - fraction.toString().length
            return sign + whole.toString() + "." + "0".repeat(pad.coerceAtLeast(0)) + fraction.toString()
        }

        private fun JsonObject.string(name: String): String? {
            val primitive = this[name] as? JsonPrimitive ?: return null
            if (primitive is JsonNull) return null
            return primitive.content
        }

        private fun JsonObject.double(name: String): Double? =
            (this[name] as? JsonPrimitive)?.doubleOrNull

        private fun JsonObject.int(name: String): Int? {
            val number = (this[name] as? JsonPrimitive)?.doubleOrNull ?: return null
            return number.roundToInt()
        }
    }
}
