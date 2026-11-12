package app.vela.ios.search

import app.vela.core.data.transit.Transitous
import app.vela.core.data.transit.TransitousHttp
import app.vela.core.model.LatLng
import app.vela.core.model.distanceTo
import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.util.UrlCodec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Wikivoyage and Wikipedia search (UNIFIED-SEARCH), on the two MediaWiki REST endpoints. Both hosts
 * only answer a read with a descriptive User-Agent; nothing is sent beyond the words and the
 * language wiki. Results are cached in memory for five minutes, so retyping the same words, or
 * deleting a letter and adding it back, costs no request.
 *
 * Wikivoyage rows lead Wikipedia rows: the field belongs to a travel app, and a destination the
 * user can visit is the more useful answer. Nothing is invented: a wiki whose search endpoint
 * fails returns no row, and the other project still answers.
 */
class WikiSearchSource(
    private val http: VelaHttp,
    private val locale: PlatformLocale,
    private val clock: Clock,
    private val language: String? = null,
    override val deadlineMs: Long = 4_500L,
) : UnifiedSource {
    override val name: String = UnifiedSources.WIKI
    private val json = Json { ignoreUnknownKeys = true }
    private val cache = LinkedHashMap<String, CacheEntry>()

    override suspend fun search(query: UnifiedQuery): List<UnifiedHit> {
        val text = query.text.trim()
        if (text.length < 2) return emptyList()
        val lang = wikiLanguage(query.language)
        cache[key(lang, text)]?.let { if (fresh(it)) return it.hits }
        var hits = ask(lang, text)
        if (hits.isEmpty() && lang != "en") hits = ask("en", text)
        cache[key(lang, text)] = CacheEntry(hits, clock.nowMillis())
        while (cache.size > MAX_CACHE) cache.remove(cache.keys.first())
        return hits
    }

    private suspend fun ask(lang: String, text: String): List<UnifiedHit> = coroutineScope {
        val encoded = UrlCodec.encode(text).replace("+", "%20")
        val voyage = async { project("wikivoyage", lang, encoded, 62) }
        val encyclopedia = async { project("wikipedia", lang, encoded, 58) }
        (voyage.await() + encyclopedia.await()).take(MAX_ROWS)
    }

    private suspend fun project(project: String, lang: String, encoded: String, score: Int): List<UnifiedHit> {
        val url = "https://$lang.$project.org/w/rest.php/v1/search/page?q=$encoded&limit=$PER_PROJECT"
        val body = request(url) ?: return emptyList()
        val reply = runCatching { json.decodeFromString<SearchReply>(body) }.getOrNull() ?: return emptyList()
        return reply.pages.mapNotNull { page ->
            val title = page.title?.trim().orEmpty()
            val key = page.key?.trim().orEmpty()
            if (title.isEmpty() || key.isEmpty()) return@mapNotNull null
            UnifiedHits.wiki(
                title = title,
                detail = plain(page.description) ?: plain(page.excerpt),
                url = "https://$lang.$project.org/wiki/$key",
                language = lang,
                lat = null,
                lng = null,
                score = score,
            )
        }
    }

    private suspend fun request(url: String): String? = runCatching {
        val response = http.call(HttpRequest(
            url = url,
            headers = listOf(
                HttpHeader("User-Agent", USER_AGENT),
                HttpHeader("Accept", "application/json"),
            ),
            timeoutMillis = deadlineMs,
        ))
        if (!response.isSuccessful) return null
        response.bodyText()
    }.getOrNull()

    private fun wikiLanguage(explicit: String?): String {
        val tag = (explicit ?: language ?: locale.defaultLanguage()).trim().lowercase()
        val code = tag.substringBefore('-')
        return code.takeIf { it.matches(LANGUAGE) } ?: "en"
    }

    private fun key(lang: String, text: String) = "$lang|${text.lowercase()}"

    private fun fresh(entry: CacheEntry): Boolean {
        val age = clock.nowMillis() - entry.at
        return age in 0 until CACHE_MS
    }

    private data class CacheEntry(val hits: List<UnifiedHit>, val at: Long)

    @Serializable private data class SearchReply(val pages: List<SearchPage> = emptyList())

    @Serializable private data class SearchPage(
        val key: String? = null,
        val title: String? = null,
        val excerpt: String? = null,
        val description: String? = null,
    )

    companion object {
        private const val USER_AGENT = "VelaMaps/1.0 (https://velamaps.org)"
        private const val PER_PROJECT = 3
        private const val MAX_ROWS = 5
        private const val MAX_CACHE = 32
        const val CACHE_MS = 5L * 60L * 1000L
        private val LANGUAGE = Regex("^[a-z]{2,3}$")
        private val TAG = Regex("<[^>]+>")
        private val SPACES = Regex("\\s+")

        /** The REST excerpt is HTML with `<span class="searchmatch">`; the row shows plain text. */
        fun plain(value: String?): String? {
            if (value == null) return null
            val text = value
                .replace("&nbsp;", " ")
                .replace("&amp;", "&")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .replace("&apos;", "'")
                .replace("&lt;", "<")
                .replace("&gt;", ">")
            return TAG.replace(text, " ").replace(SPACES, " ").trim().takeIf { it.isNotEmpty() }
        }
    }
}

/**
 * Transit stops around the visible map (UNIFIED-SEARCH), through Transitous' own `map/stops`, the
 * call the map's stop layer already uses. One request per paused query, at most a 0.12 by 0.18
 * degree box around the centre, and the names are filtered locally: the service has no name query.
 * A point with no stop in the box answers with nothing, which is the honest "No transit stop
 * nearby" the panel shows.
 */
class TransitStopSearchSource(
    private val http: TransitousHttp,
    override val deadlineMs: Long = 3_500L,
) : UnifiedSource {
    override val name: String = UnifiedSources.TRANSIT

    override suspend fun search(query: UnifiedQuery): List<UnifiedHit> {
        val text = query.text.trim().lowercase()
        if (text.length < 2) return emptyList()
        val box = boxOf(query) ?: return emptyList()
        val stops = runCatching { Transitous.stopsInBox(http, box[0], box[1], box[2], box[3]) }
            .getOrNull() ?: return emptyList()
        val near = query.near
        return stops
            .filter { it.name.lowercase().contains(text) }
            .sortedBy { if (near == null) 0.0 else LatLng(it.lat, it.lon).distanceTo(near) }
            .take(MAX_ROWS)
            .map { stop ->
                UnifiedHits.stop(
                    id = stop.stopId.ifBlank { "${stop.lat},${stop.lon}" },
                    name = stop.name,
                    subtitle = subtitle(stop.modes),
                    lat = stop.lat,
                    lng = stop.lon,
                )
            }
    }

    /** The view's own box, clamped so a city-wide zoom cannot ask a continent of stops. */
    private fun boxOf(query: UnifiedQuery): DoubleArray? {
        val s = query.south
        val w = query.west
        val n = query.north
        val e = query.east
        if (s != null && w != null && n != null && e != null && n > s && e > w) {
            val lat = (s + n) / 2
            val lng = (w + e) / 2
            val halfLat = minOf((n - s) / 2, MAX_HALF_LAT)
            val halfLng = minOf((e - w) / 2, MAX_HALF_LNG)
            return doubleArrayOf(lat - halfLat, lng - halfLng, lat + halfLat, lng + halfLng)
        }
        val near = query.near ?: return null
        return doubleArrayOf(
            near.lat - MAX_HALF_LAT, near.lng - MAX_HALF_LNG,
            near.lat + MAX_HALF_LAT, near.lng + MAX_HALF_LNG,
        )
    }

    private fun subtitle(modes: List<String>): String {
        val labels = modes.map(::label).distinct().take(2)
        return if (labels.isEmpty()) "Transit stop" else "${labels.joinToString(", ")} · Transit stop"
    }

    private fun label(mode: String): String = when {
        mode.contains("RAIL") || mode == "TRAIN" || mode == "LONG_DISTANCE" -> "Train"
        mode == "TRAM" || mode == "SUBWAY" || mode == "METRO" -> "Metro"
        mode == "FERRY" -> "Ferry"
        else -> "Bus"
    }

    companion object {
        private const val MAX_ROWS = 6
        private const val MAX_HALF_LAT = 0.06
        private const val MAX_HALF_LNG = 0.09
    }
}

/**
 * The two online sources, wired once at launch. Swift builds this from `IosGraph.shared.core` and
 * asks for a store; the Kotlin side owns the scope so the Swift graph never repeats it.
 */
class UnifiedSearchServices(core: CoreGraph, language: String?) {
    private val sources = listOf(
        WikiSearchSource(core.http, core.locale, core.clock, language),
        TransitStopSearchSource(TransitousHttp(core.http, core.locale, core.text)),
    )

    fun store(): UnifiedSearchStore =
        UnifiedSearchStore(CoroutineScope(SupervisorJob() + Dispatchers.Main), sources)
}

object UnifiedSearchResources {
    fun services(core: CoreGraph, language: String? = null): UnifiedSearchServices =
        UnifiedSearchServices(core, language)
}
