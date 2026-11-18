package app.vela.ios.place

import app.vela.core.platform.Clock
import app.vela.core.platform.CoreGraph
import app.vela.core.platform.HttpHeader
import app.vela.core.platform.HttpRequest
import app.vela.core.platform.KeyValueStore
import app.vela.core.platform.KeyValueStores
import app.vela.core.platform.PlatformLocale
import app.vela.core.platform.VelaHttp
import app.vela.core.platform.call
import app.vela.core.util.UrlCodec
import kotlinx.serialization.KSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Wikidata and Wikivoyage for the place sheet and the map layer (W-1).
 *
 * Two hosts only: `www.wikidata.org` for `wbgetentities` (facts, coordinates and sitelinks) and
 * `api.wikimedia.org` for the Wikivoyage page. A place reaches Wikidata through an explicit id on
 * its own identifier (`wikidata:Q90`, `wd:Q90` or plain `Q90`); without one this store makes no
 * request at all. It also makes none while the wiki layer is off.
 *
 * Every payload is cached for 24 hours under `vela_wiki`, keyed by the language list so a switch
 * of interface language never serves a stale language. The extract is cleaned from the page HTML;
 * no image URL is kept, which is the W-1 rule.
 */
class WikiStore(
    private val http: VelaHttp,
    stores: KeyValueStores,
    private val locale: PlatformLocale,
    private val clock: Clock,
) {
    private val cache: KeyValueStore = stores.open(STORE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /** The Q id a place identifier names, or null when it names none. */
    fun wikidataId(placeId: String?): String? {
        val trimmed = placeId?.trim().orEmpty()
        return ID.matchEntire(trimmed)?.groupValues?.get(1)?.uppercase()
    }

    /**
     * The interface language first, then the platform's other preferred languages, then English.
     * Duplicates and regional subtags are dropped; at most three languages are asked for.
     */
    fun languages(language: String? = null): List<String> {
        val explicit = language?.trim()?.lowercase()?.substringBefore('-')
        val tags = if (!explicit.isNullOrEmpty()) {
            listOf(explicit)
        } else {
            locale.preferredTags() + locale.defaultTag()
        }
        val out = tags.map { it.trim().lowercase().substringBefore('-') }
            .filter { it.matches(LANGUAGE) }
            .distinct()
            .take(3)
            .toMutableList()
        if ("en" !in out) out += "en"
        return out
    }

    /**
     * The whole section, or null when there is nothing to ask: the layer is off or the place has
     * no Wikidata id. Neither case touches the network.
     */
    suspend fun knowledge(placeId: String?, layerOn: Boolean, language: String? = null): WikiKnowledge? {
        if (!layerOn) return null
        val id = wikidataId(placeId) ?: return null
        return knowledgeFor(id, language)
    }

    suspend fun knowledgeFor(wikidataId: String, language: String? = null): WikiKnowledge? {
        val langs = languages(language)
        val facts = facts(wikidataId, langs) ?: return null
        val article = article(facts, langs)
        return WikiKnowledge(
            facts = facts,
            article = article,
            fetchedAtMs = maxOf(facts.fetchedAtMs, article?.fetchedAtMs ?: 0L),
        )
    }

    /** The cached section, for a reopened sheet: no request and no freshness claim past 24 h. */
    fun cachedKnowledge(placeId: String?, language: String? = null): WikiKnowledge? {
        val id = wikidataId(placeId) ?: return null
        val langs = languages(language)
        val facts = cachedFacts(id, langs) ?: return null
        val article = cachedArticle(facts, langs)
        return WikiKnowledge(facts, article, maxOf(facts.fetchedAtMs, article?.fetchedAtMs ?: 0L))
    }

    suspend fun facts(wikidataId: String, langs: List<String> = languages()): WikiFacts? {
        cachedFacts(wikidataId, langs)?.let { return it }
        val entity = fetchEntity(wikidataId, langs) ?: return null
        val facts = parseFacts(entity, wikidataId, langs, clock.nowMillis())
        cache.edit().putString(factsKey(wikidataId, langs), json.encodeToString(facts)).apply()
        return facts
    }

    suspend fun article(facts: WikiFacts, langs: List<String> = languages()): WikiArticle? {
        cachedArticle(facts, langs)?.let { return it }
        val order = langs.filter { facts.wikivoyage[it] != null }
        if (order.isEmpty()) return null
        for (language in order) {
            val title = facts.wikivoyage[language] ?: continue
            val page = fetchPage(language, title)
            if (page != null) {
                val article = WikiArticle(
                    title = title,
                    language = language,
                    extract = cleanExtract(page),
                    url = pageUrl(language, title),
                    latitude = facts.latitude,
                    longitude = facts.longitude,
                    fetchedAtMs = clock.nowMillis(),
                )
                cache.edit().putString(articleKey(facts.wikidataId, language), json.encodeToString(article)).apply()
                return article
            }
        }
        return null
    }

    /**
     * The curated Wikivoyage destinations that fall inside the viewport, for the map layer. One
     * `wbgetentities` request at most, cached for 24 h; an article without a point is never
     * returned, so the layer can hide until it has something to draw.
     */
    suspend fun articlesNear(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        language: String? = null,
    ): List<WikiArticle> {
        val langs = languages(language)
        val all = layerItems(langs)
        return all.filter { item ->
            val lat = item.latitude ?: return@filter false
            val lng = item.longitude ?: return@filter false
            lat in south..north && longitudeIn(lng, west, east)
        }.take(MAX_ROWS)
    }

    private suspend fun layerItems(langs: List<String>): List<WikiArticle> {
        val key = "layer:${langs.joinToString("-")}"
        read(WikiLayerCache.serializer(), key)?.let { cached ->
            if (fresh(cached.fetchedAtMs)) return cached.items
        }
        val ids = DESTINATIONS.joinToString("%7C")
        val sitefilter = langs.joinToString("%7C") { "${it}wikivoyage" }
        val url = "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=$ids"
            .plus("&props=claims%7Csitelinks&sitefilter=$sitefilter&format=json")
        val body = request(url, MEDIAWIKI_TIMEOUT_MS) ?: return emptyList()
        val entities = runCatching {
            json.parseToJsonElement(body).jsonObject["entities"]?.jsonObject
        }.getOrNull() ?: return emptyList()
        // Sitelinks come back for every item; the item's label is not needed for a row.
        val items = buildList {
            for ((id, element) in entities) {
                val entity = element.jsonObject
                val coords = coordinates(entity) ?: continue
                val titles = sitelinks(entity)
                val language = langs.firstOrNull { titles[it] != null } ?: continue
                val title = titles[language] ?: continue
                add(WikiArticle(
                    title = title,
                    language = language,
                    url = pageUrl(language, title),
                    latitude = coords.first,
                    longitude = coords.second,
                ))
            }
        }
        val stamped = clock.nowMillis()
        cache.edit().putString(key, json.encodeToString(WikiLayerCache(items, stamped))).apply()
        return items
    }

    private fun cachedFacts(wikidataId: String, langs: List<String>): WikiFacts? =
        read(WikiFacts.serializer(), factsKey(wikidataId, langs))?.takeIf { fresh(it.fetchedAtMs) }

    private fun cachedArticle(facts: WikiFacts, langs: List<String>): WikiArticle? {
        for (language in langs) {
            if (facts.wikivoyage[language] == null) continue
            val cached = read(WikiArticle.serializer(), articleKey(facts.wikidataId, language))
            if (cached != null && fresh(cached.fetchedAtMs)) return cached
        }
        return null
    }

    private suspend fun fetchEntity(wikidataId: String, langs: List<String>): JsonObject? {
        val sites = langs.joinToString("%7C") { "${it}wikivoyage" }
        val languages = langs.joinToString("%7C")
        val url = "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=$wikidataId"
            .plus("&props=claims%7Csitelinks%7Clabels&languages=$languages&sitefilter=$sites&format=json")
        val body = request(url, MEDIAWIKI_TIMEOUT_MS) ?: return null
        return runCatching {
            json.parseToJsonElement(body).jsonObject["entities"]?.jsonObject
                ?.get(wikidataId)?.jsonObject
        }.getOrNull()
    }

    private suspend fun fetchPage(language: String, title: String): String? {
        val url = "https://api.wikimedia.org/core/v1/wikivoyage/$language/page/${path(title)}/html"
        return request(url, MEDIAWIKI_TIMEOUT_MS)
    }

    /**
     * Wikimedia refuses a request without a descriptive User-Agent (HTTP 403), so every call
     * carries one. The page HTML is close to a megabyte, hence the longer deadline.
     */
    private suspend fun request(url: String, timeoutMs: Long): String? = runCatching {
        val response = http.call(HttpRequest(
            url = url,
            headers = listOf(
                HttpHeader("User-Agent", USER_AGENT),
                HttpHeader("Accept", "application/json, text/html;q=0.9"),
            ),
            timeoutMillis = timeoutMs,
        ))
        if (!response.isSuccessful) return null
        response.bodyText()
    }.getOrNull()

    private fun parseFacts(
        entity: JsonObject,
        wikidataId: String,
        langs: List<String>,
        nowMs: Long,
    ): WikiFacts {
        val labels = entity["labels"]?.jsonObject
        val language = langs.firstOrNull { labels?.get(it) != null } ?: "en"
        val label = labels?.get(language)?.jsonObject?.get("value")?.jsonPrimitive?.contentOrNull
        val coords = coordinates(entity)
        return WikiFacts(
            wikidataId = wikidataId,
            label = label,
            population = population(entity),
            opened = opened(entity),
            website = website(entity),
            latitude = coords?.first,
            longitude = coords?.second,
            language = language,
            wikivoyage = sitelinks(entity),
            fetchedAtMs = nowMs,
        )
    }

    private fun coordinates(entity: JsonObject): Pair<Double, Double>? {
        val value = snakValue(entity, "P625")?.jsonObject ?: return null
        val lat = value["latitude"]?.jsonPrimitive?.doubleOrNull ?: return null
        val lng = value["longitude"]?.jsonPrimitive?.doubleOrNull ?: return null
        if (lat !in -90.0..90.0 || lng !in -180.0..180.0) return null
        return lat to lng
    }

    private fun population(entity: JsonObject): Long? {
        val amount = snakValue(entity, "P1082")?.jsonObject?.get("amount")
            ?.jsonPrimitive?.contentOrNull ?: return null
        val digits = amount.removePrefix("+").substringBefore('.')
        return digits.toLongOrNull()?.takeIf { it >= 0 }
    }

    private fun website(entity: JsonObject): String? {
        val value = snakValue(entity, "P856")?.jsonPrimitive?.contentOrNull?.trim() ?: return null
        return value.takeIf { it.startsWith("http://") || it.startsWith("https://") }
    }

    /** P1619 sliced by the statement precision: year, month or day, never a zero-padded guess. */
    private fun opened(entity: JsonObject): String? {
        val claim = bestClaim(entity, "P1619") ?: return null
        val value = claim["mainsnak"]?.jsonObject?.get("datavalue")?.jsonObject?.get("value")?.jsonObject
        val time = value?.get("time")?.jsonPrimitive?.contentOrNull ?: return null
        val precision = value["precision"]?.jsonPrimitive?.intOrNull ?: 11
        val clean = time.removePrefix("+")
        val year = clean.take(4)
        if (year.toIntOrNull() == null) return null
        return when {
            precision >= 11 && clean.length >= 10 -> clean.take(10)
            precision == 10 && clean.length >= 7 -> clean.take(7)
            else -> year
        }
    }

    private fun sitelinks(entity: JsonObject): Map<String, String> {
        val links = entity["sitelinks"]?.jsonObject ?: return emptyMap()
        val out = mutableMapOf<String, String>()
        for ((site, element) in links) {
            if (!site.endsWith("wikivoyage")) continue
            val language = site.removeSuffix("wikivoyage")
            val title = element.jsonObject["title"]?.jsonPrimitive?.contentOrNull ?: continue
            if (language.isNotEmpty()) out[language] = title
        }
        return out
    }

    /** The first non-deprecated statement's value, an object or a literal depending on the type. */
    private fun snakValue(entity: JsonObject, property: String): JsonElement? {
        val claim = bestClaim(entity, property) ?: return null
        return claim["mainsnak"]?.jsonObject?.get("datavalue")?.jsonObject?.get("value")
    }

    private fun bestClaim(entity: JsonObject, property: String): JsonObject? {
        val element = entity["claims"]?.jsonObject?.get(property) ?: return null
        val claims: JsonArray = runCatching { element.jsonArray }.getOrNull() ?: return null
        val usable = claims.map { it.jsonObject }
            .filter { it["rank"]?.jsonPrimitive?.contentOrNull != "deprecated" }
        return usable.firstOrNull { it["rank"]?.jsonPrimitive?.contentOrNull == "preferred" }
            ?: usable.firstOrNull()
    }

    private fun factsKey(wikidataId: String, langs: List<String>): String =
        "facts:${langs.joinToString("-")}:$wikidataId"

    private fun articleKey(wikidataId: String, language: String): String =
        "article:$language:$wikidataId"

    private fun fresh(fetchedAtMs: Long): Boolean {
        val age = clock.nowMillis() - fetchedAtMs
        return fetchedAtMs > 0L && age in 0 until CACHE_MS
    }

    private fun <T> read(serializer: KSerializer<T>, key: String): T? {
        val raw = cache.getString(key, null) ?: return null
        return runCatching { json.decodeFromString(serializer, raw) }.getOrNull()
    }

    companion object {
        private const val STORE = "vela_wiki"
        private const val MAX_ROWS = 24
        private const val MEDIAWIKI_TIMEOUT_MS = 25_000L
        private const val USER_AGENT = "VelaMaps/1.0 (https://velamaps.org)"

        /** 24 hours in milliseconds: the WLD-1 freshness window for the wiki layer. */
        const val CACHE_MS = 24L * 60L * 60L * 1_000L

        private val ID = Regex("^(?:wikidata:|wd:)?(Q\\d{1,12})$", RegexOption.IGNORE_CASE)
        private val LANGUAGE = Regex("^[a-z]{2,3}$")
        private val TAG = Regex("<[^>]+>")
        private val DROP = Regex("(?is)<(script|style|noscript|figure|table|sup)\\b[^>]*>.*?</\\1>")
        private val IMG = Regex("(?is)<img\\b[^>]*>")
        private val PARAGRAPH = Regex("(?is)<p\\b[^>]*>(.*?)</p>")

        /**
         * The destinations the layer offers. Only articles that carry a Wikidata point are used,
         * so an item that moves or loses its coordinate simply leaves the layer. The list is
         * curated because Wikidata's API has no "items near this box that have a Wikivoyage page"
         * call on the two hosts W-1 may use.
         */
        private val DESTINATIONS = listOf(
            "Q90", "Q84", "Q60", "Q62", "Q65", "Q1297", "Q61", "Q64", "Q220", "Q2807",
            "Q1492", "Q727", "Q174", "Q1085", "Q597", "Q1524", "Q406", "Q649", "Q1490", "Q956",
        )

        /**
         * The lead paragraphs of a Wikivoyage page as plain text. Scripts, styles, figures, tables,
         * images and markup are stripped, entities decoded, and the result cut at a sentence
         * boundary near [maxChars]. Images never survive: W-1 shows none.
         */
        fun cleanExtract(html: String, maxChars: Int = 900): String {
            var text = DROP.replace(html, " ")
            text = IMG.replace(text, " ")
            val paragraphs = PARAGRAPH.findAll(text).map { stripEntities(TAG.replace(it.groupValues[1], " ")) }
                .map { it.trim() }
                .filter { it.length > 40 }
                .take(3)
                .toList()
            val joined = if (paragraphs.isNotEmpty()) {
                paragraphs.joinToString("\n\n")
            } else {
                val lead = text.substringBefore("<h2", text).substringBefore("<div class=\"mw-heading", text)
                stripEntities(TAG.replace(lead, " ")).trim()
            }
            val collapsed = joined.lines().joinToString("\n") { line ->
                line.replace(Regex("\\s+"), " ").trim()
            }.trim()
            if (collapsed.length <= maxChars) return collapsed
            val cut = collapsed.take(maxChars)
            val boundary = maxOf(cut.lastIndexOf(". "), cut.lastIndexOf("! "), cut.lastIndexOf("? "))
            return (if (boundary > maxChars / 2) cut.take(boundary + 1) else cut).trim()
        }

        private fun stripEntities(input: String): String {
            var out = input
                .replace("&nbsp;", " ")
                .replace("&amp;", "&")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .replace("&apos;", "'")
                .replace("&lt;", "<")
                .replace("&gt;", ">")
            out = Regex("&#(\\d+);").replace(out) { match ->
                val code = match.groupValues[1].toIntOrNull() ?: return@replace " "
                if (code in 32..0x10FFFF) code.toChar().toString() else " "
            }
            return out
        }

        /** A public Wikivoyage page URL, built without a literal per-language host in the tree. */
        fun pageUrl(language: String, title: String): String =
            "https://$language.wikivoyage.org/wiki/" + path(title).replace("%20", "_")

        private fun path(title: String): String =
            UrlCodec.encode(title.trim()).replace("+", "%20")

        /** A viewport whose west edge is past its east edge crosses the antimeridian. */
        private fun longitudeIn(lng: Double, west: Double, east: Double): Boolean =
            if (west <= east) lng in west..east else lng >= west || lng <= east
    }
}

/**
 * The one store shape Swift needs. Keeping construction here means the Swift side never repeats
 * the platform parameters, and the JVM test never loads the iOS graph.
 */
object WikiResources {
    fun forCore(core: CoreGraph): WikiStore =
        WikiStore(core.http, core.keyValues, core.locale, core.clock)
}
