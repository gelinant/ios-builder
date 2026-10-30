package app.vela.ios.world

import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One Electricity Maps zone reading. The service has no anonymous tier: this only runs with a
 *  user key and is never reported as "zero carbon" when the key is absent. */
data class ElectricityMapsReading(
    val zone: String,
    val carbonIntensity: Int,
    val updatedAtMs: Long,
)

/**
 * Electricity Maps v3 latest carbon intensity for one zone, with the user's key in the
 * `auth-token` header. The key is passed per call and never stored on the object.
 */
class ElectricityMapsSource(
    private val http: VelaHttp,
    private val baseUrl: String = BASE_URL,
) {
    suspend fun fetch(apiKey: String, zone: String = "GB", nowMs: Long = 0L): ElectricityMapsReading? {
        val key = apiKey.trim()
        if (key.isEmpty()) return null
        val request = HttpRequest(
            url = baseUrl.trimEnd('/') + "/v3/carbon-intensity/latest?zone=" + zone,
            timeoutMillis = 15_000,
            headers = listOf(
                HttpHeader("Accept", "application/json"),
                HttpHeader("auth-token", key),
            ),
        )
        val response = runCatching { http.call(request) }.getOrNull() ?: return null
        if (!response.isSuccessful) return null
        return runCatching { parse(response.bodyText(), zone, nowMs) }.getOrNull()
    }

    companion object {
        const val HOST = "api.electricitymaps.com"
        const val BASE_URL = "https://$HOST"

        /** Accepts the v3 object and a `data` wrapper, which the history endpoints use. */
        fun parse(text: String, zone: String = "GB", nowMs: Long = 0L): ElectricityMapsReading? =
            runCatching {
                val root = Json.parseToJsonElement(text).jsonObject
                val body = root["data"]?.jsonArray?.firstOrNull()?.jsonObject ?: root
                val value = body["carbonIntensity"]?.jsonPrimitive?.intOrNull
                    ?: body["carbon_intensity"]?.jsonPrimitive?.intOrNull
                    ?: return@runCatching null
                val at = isoEpochMs(body.str("updatedAt"))
                    ?: isoEpochMs(body.str("datetime")) ?: nowMs
                ElectricityMapsReading(
                    zone = body.str("zone") ?: zone,
                    carbonIntensity = value,
                    updatedAtMs = at,
                )
            }.getOrNull()

        private fun JsonObject.str(name: String): String? =
            this[name]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }

    }
}
