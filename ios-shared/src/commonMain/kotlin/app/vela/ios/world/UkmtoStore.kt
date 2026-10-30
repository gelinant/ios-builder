package app.vela.ios.world

import app.vela.core.VelaConfig
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Clock
import kotlin.time.Instant

/** One UKMTO incident, reduced to the three fields the lot is allowed to show: a title built
 *  from the number and the type, the incident date, and the link. The summary body and the
 *  coordinates the source carries are deliberately not read. */
data class UkmtoIncident(
    val id: String,
    val title: String,
    val dateMs: Long,
    val dateLabel: String,
    val link: String,
)

/** The UKMTO list as the sheet shows it: a header that calls itself a link list, then at most
 *  [MAX_ROWS] incidents, newest first. No row carries a coordinate. */
data class UkmtoSnapshot(
    val updatedAtMs: Long,
    val rows: List<MaritimeRow>,
    val incidents: List<UkmtoIncident>,
)

/**
 * The UKMTO recent incidents list, read from the public JSON the UKMTO site itself loads. Only
 * title, date and link are kept; every entry links to the recent-incidents page. Crown copyright,
 * no open reuse terms, so no summary text is copied and no zone or point reaches the map.
 *
 * A fetch is cached for ten minutes. A failure keeps the previous list; with no earlier list the
 * layer adds an explicit unavailable row instead of an empty list.
 */
class UkmtoStore internal constructor(
    private val fetchText: suspend () -> String?,
    private val now: () -> Long = { Clock.System.now().toEpochMilliseconds() },
) {
    constructor(http: VelaHttp) : this({ fetchBody(http) })

    private var cached: UkmtoSnapshot? = null
    private var cachedAtMs = 0L

    suspend fun refresh(): UkmtoSnapshot? {
        val nowMs = now()
        val previous = cached
        if (previous != null && nowMs - cachedAtMs in 0 until CACHE_MS) return previous
        val text = try {
            fetchText()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            null
        } ?: return previous
        val incidents = try {
            parse(text)
        } catch (e: Throwable) {
            return previous
        }
        val rows = ArrayList<MaritimeRow>(incidents.size + 1)
        rows += MaritimeRow(
            id = "maritime-ukmto-header",
            title = "UKMTO incidents: link list only",
            detail = "Newest first. Title, date and link only. Not a live advisory feed; " +
                "no zone is drawn.")
        if (incidents.isEmpty()) {
            rows += MaritimeRow(
                id = "maritime-ukmto-empty",
                title = "UKMTO: no incident listed",
                detail = "The link list is empty. This is not a live advisory feed.")
        } else {
            for (incident in incidents) {
                rows += MaritimeRow(
                    id = "maritime-ukmto-${incident.id}",
                    title = incident.title,
                    detail = "${incident.dateLabel} · Link only · ${incident.link}")
            }
        }
        val snapshot = UkmtoSnapshot(updatedAtMs = nowMs, rows = rows, incidents = incidents)
        cached = snapshot
        cachedAtMs = nowMs
        return snapshot
    }

    companion object {
        const val URL = "https://sccd.royalnavy.mod.uk/api/ukmto/all"
        const val PAGE = "https://www.ukmto.org/recent-incidents"
        const val CACHE_MS = 10L * 60L * 1_000L
        const val MAX_ROWS = 20

        private val MONTHS = listOf(
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

        /** Title, date and link only. A record without a site id has no link and is dropped; a
         *  record without a date cannot be ordered and is dropped. */
        fun parse(text: String): List<UkmtoIncident> {
            val root = Json.parseToJsonElement(text) as? JsonArray
                ?: throw IllegalArgumentException("UKMTO answer is not a list")
            val byId = LinkedHashMap<String, UkmtoIncident>()
            for (entry in root) {
                val item = entry as? JsonObject ?: continue
                val id = (item["sitecoreId"] as? JsonPrimitive)?.contentOrNull
                    ?.trim()?.takeIf { it.isNotEmpty() } ?: continue
                val rawDate = (item["utcDateOfIncident"] as? JsonPrimitive)?.contentOrNull
                    ?: (item["utcDateCreated"] as? JsonPrimitive)?.contentOrNull
                    ?: continue
                val dateMs = runCatching { Instant.parse(rawDate).toEpochMilliseconds() }
                    .getOrElse { continue }
                val number = (item["incidentNumber"] as? JsonPrimitive)?.intOrNull
                val type = (item["incidentTypeName"] as? JsonPrimitive)?.contentOrNull
                    ?.trim()?.takeIf { it.isNotEmpty() } ?: "Incident"
                val prefix = number?.let { "UKMTO #$it " } ?: "UKMTO "
                byId[id] = UkmtoIncident(
                    id = id,
                    title = "$prefix$type",
                    dateMs = dateMs,
                    dateLabel = dateLabel(rawDate),
                    link = "$PAGE#$id")
            }
            return byId.values
                .sortedWith(compareByDescending<UkmtoIncident> { it.dateMs }.thenByDescending { it.id })
                .take(MAX_ROWS)
        }

        /** `12 Oct 2026`, in UTC, with an English month as the rest of the sheet uses. */
        fun dateLabel(iso: String): String {
            val date = Instant.parse(iso).toLocalDateTime(TimeZone.UTC).date
            val month = MONTHS[date.month.ordinal]
            return "${date.day} $month ${date.year}"
        }
    }
}

private suspend fun fetchBody(http: VelaHttp): String? {
    val request = HttpRequest(
        UkmtoStore.URL,
        headers = listOf(HttpHeader("User-Agent", VelaConfig.VELA_UA)),
        timeoutMillis = 20_000L)
    val response = try {
        http.call(request)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Throwable) {
        return null
    }
    if (!response.isSuccessful) return null
    return response.body.decodeToString()
}
