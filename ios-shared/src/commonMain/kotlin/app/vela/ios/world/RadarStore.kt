package app.vela.ios.world

import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import kotlin.concurrent.Volatile
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * One Cloudflare Radar annotation. `kind` is `outage` or `attack`; `locations` holds alpha-2
 * country codes, never a latitude and longitude invented by this app.
 */
data class RadarEvent(
    val id: String,
    val kind: String,
    val title: String,
    val detail: String,
    val startedAtMs: Long,
    val endedAtMs: Long,
    val locations: List<String>,
    val url: String,
)

data class RadarSnapshot(
    val fetchedAtMs: Long,
    val events: List<RadarEvent>,
)

data class RadarState(
    val tokenPresent: Boolean,
    val eventCount: Int,
    val fetchedAtMs: Long,
    val ageSeconds: Long,
    val status: String,
) {
    /** Presence and counts only: no token, no header, no request URL with a secret. */
    val debugLine: String
        get() = "radar_state=$status radar_events=$eventCount"
}

/**
 * Cloudflare Radar outages and layer 3 attacks with a user token (CC BY-NC 4.0). The token is
 * passed per call and never stored. Radar only sees traffic that crosses Cloudflare, so a quiet
 * answer is not evidence that the wider Internet is quiet; the layer says that in the UI.
 *
 * Without a token, [refresh] makes no request and [state] reports `key_required`. It never
 * presents an empty list as "no traffic".
 */
class RadarStore(
    private val http: VelaHttp,
    private val baseUrl: String = BASE_URL,
) {
    @Volatile
    private var snapshot: RadarSnapshot? = null

    @Volatile
    var tokenPresent: Boolean = false
        private set

    suspend fun refresh(token: String?, nowMs: Long): RadarSnapshot? {
        val value = token?.trim().orEmpty()
        tokenPresent = value.isNotEmpty()
        if (!tokenPresent) {
            snapshot = null
            return null
        }
        val outages = runCatching { fetchOutages(value, nowMs) }.getOrNull()
        val attacks = runCatching { fetchAttacks(value, nowMs) }.getOrNull()
        if (outages == null && attacks == null) return null
        val events = (outages.orEmpty() + attacks.orEmpty()).sortedByDescending { it.startedAtMs }
        val next = RadarSnapshot(fetchedAtMs = nowMs, events = events)
        snapshot = next
        return next
    }

    fun state(nowMs: Long): RadarState {
        val data = snapshot
        val ageSeconds = data?.let { ((nowMs - it.fetchedAtMs).coerceAtLeast(0L)) / 1_000L } ?: 0L
        val status = when {
            !tokenPresent -> "key_required"
            data == null -> WorldLayerStatuses.UNAVAILABLE
            ageSeconds > MAX_AGE_SECONDS -> WorldLayerStatuses.LATE
            else -> WorldLayerStatuses.FRESH
        }
        return RadarState(
            tokenPresent = tokenPresent,
            eventCount = data?.events?.size ?: 0,
            fetchedAtMs = data?.fetchedAtMs ?: 0L,
            ageSeconds = ageSeconds,
            status = status,
        )
    }

    private suspend fun fetchOutages(token: String, nowMs: Long): List<RadarEvent>? {
        val url = baseUrl.trimEnd('/') + "/radar/annotations/outages?limit=50&dateRange=7d&format=json"
        val root = get(url, token) ?: return null
        val result = root["result"]?.jsonObject ?: return null
        return result["annotations"]?.jsonArray.orEmpty().mapIndexedNotNull { index, element ->
            val item = element.jsonObject
            val id = item.str("id") ?: "outage-$index"
            val outage = item["outage"]?.jsonObject
            val cause = outage?.str("outageCause").orEmpty()
            val type = outage?.str("outageType").orEmpty()
            val scope = item.str("scope") ?: item.str("description") ?: "Internet outage"
            RadarEvent(
                id = "outage-$id",
                kind = "outage",
                title = scope,
                detail = listOfNotNull(
                    cause.takeIf { it.isNotEmpty() }?.replace('_', ' ')?.lowercase(),
                    type.takeIf { it.isNotEmpty() }?.replace('_', ' ')?.lowercase(),
                ).joinToString(", ").ifEmpty { "Cloudflare outage annotation" },
                startedAtMs = isoEpochMs(item.str("startDate")) ?: nowMs,
                endedAtMs = isoEpochMs(item.str("endDate")) ?: 0L,
                locations = item["locations"]?.jsonArray.orEmpty().mapNotNull {
                    it.jsonPrimitive.contentOrNull?.uppercase()
                },
                url = item.str("linkedUrl").orEmpty(),
            )
        }
    }

    private suspend fun fetchAttacks(token: String, nowMs: Long): List<RadarEvent>? {
        val url = baseUrl.trimEnd('/') + "/radar/attacks/layer3/top/attacks?limit=20&dateRange=7d&format=json"
        val root = get(url, token) ?: return null
        val result = root["result"]?.jsonObject ?: return null
        val meta = result["meta"]?.jsonObject
        val range = meta?.get("dateRange")?.jsonObject
        val started = isoEpochMs(range?.str("startTime")) ?: isoEpochMs(range?.str("endTime")) ?: 0L
        val top = result["top_0"]?.jsonArray ?: result["top_1"]?.jsonArray ?: return emptyList()
        return top.mapIndexedNotNull { index, element ->
            val item = element.jsonObject
            val origin = item.str("originCountryAlpha2")?.uppercase().orEmpty()
            val originName = item.str("originCountryName") ?: origin
            val target = item.str("targetCountryAlpha2")?.uppercase().orEmpty()
            val targetName = item.str("targetCountryName").orEmpty()
            val value = item.str("value") ?: "0"
            val destination = if (targetName.isNotEmpty()) targetName else target
            RadarEvent(
                id = "attack-$index-$origin-$target",
                kind = "attack",
                title = if (destination.isNotEmpty()) {
                    "Attack from $originName to $destination"
                } else {
                    "Layer 3 attack from $originName"
                },
                detail = "Share of layer 3 attack traffic: $value%" + if (destination.isNotEmpty()) "" else
                    " (origin only)",
                startedAtMs = started.takeIf { it > 0L } ?: nowMs,
                endedAtMs = 0L,
                locations = listOfNotNull(origin.takeIf { it.isNotEmpty() }, target.takeIf { it.isNotEmpty() }),
                url = "https://radar.cloudflare.com/attacks",
            )
        }
    }

    private suspend fun get(url: String, token: String): JsonObject? {
        val request = HttpRequest(
            url = url,
            timeoutMillis = 15_000,
            headers = listOf(
                HttpHeader("Accept", "application/json"),
                HttpHeader("Authorization", "Bearer $token"),
            ),
        )
        val response = runCatching { http.call(request) }.getOrNull() ?: return null
        if (!response.isSuccessful) return null
        return runCatching { Json.parseToJsonElement(response.bodyText()).jsonObject }.getOrNull()
    }

    companion object {
        const val HOST = "api.cloudflare.com"
        const val BASE_URL = "https://$HOST/client/v4"
        const val MAX_AGE_SECONDS = 30L * 60L
        const val MAX_AGE_MS = MAX_AGE_SECONDS * 1_000L

        private fun JsonObject.str(name: String): String? =
            this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }
    }
}
